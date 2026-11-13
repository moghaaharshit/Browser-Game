class_name PlayerWalker
extends CharacterBody3D

## The on-foot player.  Everything is procedural: the body is built by
## AvatarModel and posed here every frame (see _animate), so walking, sprinting,
## crouching, lying prone, jumping and the boxing combo all come from a few
## sine waves and easing curves instead of imported animation clips.
##
## Controls  WASD move · Shift sprint · Ctrl crouch · Z prone · Space jump ·
## Left click punch (3 hit combo) · mouse look · F enter the car.

signal threw_punch(kind: int)
signal landed

## Real numbers, in metres and seconds: gravity is Earth's 9.81, a walk is a
## brisk 2.6 m/s, a sprint is 6.4 m/s, and the jump leaves the ground at 4.6 m/s
## which is a 1.08 m high jump that keeps you in the air for 0.94 s.
const WALK_SPEED := 2.6
const RUN_SPEED := 6.4
const CROUCH_SPEED := 1.35
const PRONE_SPEED := 0.8
const ACCEL := 12.0           ## how fast the body reaches walking speed
const AIR_ACCEL := 2.2        ## you cannot change direction much in the air
const JUMP_V := 4.6           ## 1.08 m jump under 9.81 m/s2
const GRAVITY := 9.81         ## Earth gravity
const TURN_RATE := 12.0
const STEP_HEIGHT := 0.46      ## how tall a ledge the player can step over

const CAM_DIST := 4.35
const CAM_HEIGHT := 0.55
const MOUSE_SENS := 0.0026

var model: AvatarModel
var yaw := 0.0                    ## camera yaw
var pitch := -0.06                ## camera pitch
var move_speed := 0.0             ## current ground speed (m/s)
var sprinting := false
var crouching := false
var prone := false
var on_ground := true
var input_enabled := true
var frozen := false               ## used while the big map is open
var cam_zoom := 1.0               ## V toggles a wider walking camera
var holding_gun: Node3D = null    ## equipped weapon / item model (see CombatSystem)
var held_kind := "gun"            ## "gun" / "grenade" / "gloo" / "medkit"
var aiming := false            ## aiming down sights
var health := 100.0
var armor := 0.0
var scoped := false               ## sniper scope = first person
var gun_pitch := 0.0              ## how far up/down the weapon points
var _gun_mount: Node3D = null
var _kick := 0.0
var _face_t := 0.0                ## >0: square up to the aim, not to the movement
var _model_hidden := false

var city_world: CityWorld = null
var _interior: OmniLight3D = null
var _probe_t := 0.0
## On-screen thumb stick (see TouchControls): x = strafe, y = forward, both -1..1.
## When it is non-zero it replaces the WASD keys, and it is analogue, so you can
## walk half speed by pushing the stick half way.
var touch_move := Vector2.ZERO
var touch_sprint := false
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO

var _phase := 0.0                 ## gait phase
var _air_t := 0.0
var _land_t := 0.0
var _punch_t := -1.0
var _punch_kind := 0
var _punch_hit := false
var _combo := 0
var _combo_cd := 0.0
var _breathe := 0.0
var _lean := 0.0

func _ready() -> void:
	name = "PlayerWalker"
	collision_layer = 4
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	slide_on_ceiling = false
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.78
	cs.shape = cap
	cs.position = Vector3(0, 0.89, 0)
	add_child(cs)

	# one soft warm light that switches on when there is a roof overhead, so the
	# insides of the houses are not lit by blue sky ambient only
	_interior = OmniLight3D.new()
	_interior.light_color = Color(1.0, 0.92, 0.78)
	_interior.light_energy = 0.0
	_interior.omni_range = 9.0
	_interior.position = Vector3(0, 2.0, 0)
	_interior.shadow_enabled = false
	add_child(_interior)

	model = AvatarModel.new()
	add_child(model)
	_pose_idle(0.0)

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or frozen:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch -= event.relative.y * MOUSE_SENS
		pitch = clampf(pitch, -1.15, 0.85)

## Touch / gamepad style look: same yaw and pitch as the mouse, driven by the
## on-screen drag pads.  dx and dy are pixels.
func add_look(dx: float, dy: float, sens: float = MOUSE_SENS) -> void:
	if frozen:
		return
	yaw -= dx * sens
	pitch -= dy * sens
	pitch = clampf(pitch, -1.15, 0.85)

func punch() -> void:
	if frozen or _punch_t >= 0.0:
		return
	_combo = (_combo + 1) % 3 if _combo_cd > 0.0 else 0
	_combo_cd = 0.85
	_punch_kind = _combo
	_punch_t = 0.0
	_punch_hit = false
	threw_punch.emit(_punch_kind)

# ------------------------------------------------------------------ movement

func _physics_process(dt: float) -> void:
	var wish := Vector3.ZERO
	var run_in := false
	if input_enabled and not frozen:
		var f := Input.get_axis("brake", "accelerate")     # W = +1 forward
		var s := Input.get_axis("steer_left", "steer_right")
		if touch_move != Vector2.ZERO:
			f = touch_move.y
			s = touch_move.x
		run_in = Input.is_action_pressed("boost") or touch_sprint
		crouching = Input.is_action_pressed("crouch")
		prone = Input.is_action_pressed("prone")
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var rightv := Vector3(cos(yaw), 0, -sin(yaw))
		wish = (fwd * f + rightv * s)
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
		if prone:
			run_in = false
			crouching = false
		elif crouching:
			run_in = false
		sprinting = run_in and (f > 0.1 or touch_move.y > 0.1)
		if Input.is_action_just_pressed("jump") and is_on_floor() and not prone:
			velocity.y = JUMP_V
			_air_t = 0.0
			on_ground = false
	else:
		sprinting = false

	var target := WALK_SPEED
	if prone:
		target = PRONE_SPEED
	elif crouching:
		target = CROUCH_SPEED
	elif sprinting:
		target = RUN_SPEED

	if not is_on_floor():
		velocity.y -= GRAVITY * dt
		_air_t += dt
		var air := wish * target
		velocity.x = lerpf(velocity.x, air.x, 1.0 - exp(-AIR_ACCEL * dt))
		velocity.z = lerpf(velocity.z, air.z, 1.0 - exp(-AIR_ACCEL * dt))
	else:
		if _air_t > 0.15:
			_land_t = 0.28
			landed.emit()
		_air_t = 0.0
		if velocity.y < 0.0:
			velocity.y = -0.5
		var goal := wish * target
		var rate := ACCEL if wish.length_squared() > 0.01 else ACCEL * 1.6
		_lean = lerpf(_lean, -wish.dot(Vector3(-sin(yaw), 0, -cos(yaw))) * (0.5 if sprinting else 0.2), 1.0 - exp(-6.0 * dt))
		velocity.x = lerpf(velocity.x, goal.x, 1.0 - exp(-rate * dt))
		velocity.z = lerpf(velocity.z, goal.z, 1.0 - exp(-rate * dt))

	move_and_slide()
	_try_step(dt)
	_terrain_clamp()

	on_ground = is_on_floor()
	move_speed = Vector2(velocity.x, velocity.z).length()

	# face the way we are moving (camera relative sticks around when idle)
	if move_speed > 0.35:
		var want := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_RATE * dt))
	_face_t = maxf(0.0, _face_t - dt)
	# punching, firing and aiming all square the body up to the camera yaw
	if _punch_t >= 0.0:
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-16.0 * dt))
	elif _face_t > 0.0 or (aiming and holding_gun != null):
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-20.0 * dt))

	if _land_t > 0.0:
		_land_t = maxf(0.0, _land_t - dt)
	if _combo_cd > 0.0:
		_combo_cd = maxf(0.0, _combo_cd - dt)

## CharacterBody3D cannot climb a kerb on its own, so when the horizontal move
## is blocked we look for a free ledge within STEP_HEIGHT and lift the body onto
## it.  That is what gets you up the porch step and into the houses.
func _try_step(dt: float) -> void:
	if not is_on_floor():
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	if motion.length_squared() < 0.00025:
		return
	var here := global_transform
	if not test_move(here, motion):
		return
	var up := Vector3(0, STEP_HEIGHT, 0)
	if test_move(here, up):
		return
	var lifted := Transform3D(here.basis, here.origin + up)
	if test_move(lifted, motion * 1.4):
		return
	global_position = here.origin + up + motion * 1.25

# ------------------------------------------------------------------ animation

func _process(dt: float) -> void:
	if model == null:
		return
	if _punch_t >= 0.0:
		_punch_t += dt
		if not _punch_hit and _punch_t > 0.08:
			_punch_hit = true
			_hit_check()
		if _punch_t > 0.40:
			_punch_t = -1.0

	_probe_t -= dt
	if _probe_t <= 0.0 and _interior != null:
		_probe_t = 0.25
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0),
			global_position + Vector3(0, 30.0, 0), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var want := 1.05 if not hit.is_empty() else 0.0
		_interior.light_energy = lerpf(_interior.light_energy, want, 0.5)
	_breathe += dt
	if _kick > 0.0:
		_kick = maxf(0.0, _kick - dt * 2.6)
	_update_mount()
	if holding_gun != null and _punch_t < 0.0:
		var armed: bool = held_kind == "gun"
		if prone:
			_pose_prone(dt)
			if not armed:
				_hold_item_arms()
		elif not on_ground:
			_pose_air(dt)
			if armed:
				_gun_arms(clampf(gun_pitch, -0.9, 0.9))
			else:
				_hold_item_arms()
		elif crouching:
			_pose_crouch(dt)
			if armed:
				_gun_arms(clampf(gun_pitch, -0.9, 0.9))
			else:
				_hold_item_arms()
		elif armed and move_speed > 0.25:
			_pose_aim_run(dt)
		elif armed:
			_pose_aim_idle(dt)
		else:
			_pose_hold_item(dt)
		return
	if prone:
		_pose_prone(dt)
	elif not on_ground:
		_pose_air(dt)
	elif crouching:
		_pose_crouch(dt)
	elif move_speed > 0.25:
		_pose_run(dt)
	else:
		_pose_idle(dt)
	if _punch_t >= 0.0:
		_apply_punch()
	_update_mount()

## Slide the held object to wherever the hands ended up.  For a gun that is the
## midpoint of the two hands (grip + hand guard), for an item it is the right
## hand — which is what keeps the hands *on* the weapon instead of near it.
func _update_mount() -> void:
	if _gun_mount == null or holding_gun == null:
		return
	var sp := model.spine
	var pr: Vector3 = sp.to_local(model.hand_r.global_position)
	if held_kind == "gun":
		var pl: Vector3 = sp.to_local(model.hand_l.global_position)
		var mid: Vector3 = (pr + pl) * 0.5
		mid += Vector3(0.02, 0.05, -0.05)
		_gun_mount.position = _gun_mount.position.lerp(mid, 0.45)
	else:
		var want: Vector3 = pr + Vector3(0.0, 0.03, -0.03)
		_gun_mount.position = _gun_mount.position.lerp(want, 0.45)
	_gun_mount.rotation = Vector3(gun_pitch, 0.0, 0.0)

func _set_limb(n: Node3D, x: float, y: float = 0.0, z: float = 0.0) -> void:
	if n == null:
		return
	n.rotation = Vector3(x, y, z)

func _reset_pose() -> void:
	model.body.position = Vector3.ZERO
	model.body.rotation = Vector3.ZERO
	model.hips.position = Vector3(0, AvatarModel.HIP_Y, 0)
	model.hips.rotation = Vector3.ZERO
	model.spine.rotation = Vector3.ZERO
	model.neck.rotation = Vector3.ZERO
	model.head.rotation = Vector3.ZERO
	for n in [model.thigh_l, model.thigh_r, model.knee_l, model.knee_r,
			model.foot_l, model.foot_r, model.sh_l, model.sh_r,
			model.el_l, model.el_r, model.hand_l, model.hand_r]:
		(n as Node3D).rotation = Vector3.ZERO

func _pose_idle(dt: float) -> void:
	_reset_pose()
	var br := sin(_breathe * 1.7)
	var sway := sin(_breathe * 0.9)
	model.hips.position.y = AvatarModel.HIP_Y - 0.012 + br * 0.008 - _land_t * 0.22
	model.spine.rotation = Vector3(0.04 + br * 0.012, sway * 0.04, 0.0)
	model.neck.rotation = Vector3(0.02, -sway * 0.06, 0.0)
	model.head.rotation = Vector3(-0.02, sin(_breathe * 0.45) * 0.22, 0.0)
	# relaxed arms: slight bend, hands turned in
	_set_limb(model.sh_l, 0.06 + br * 0.02, 0.0, 0.12)
	_set_limb(model.sh_r, 0.06 - br * 0.02, 0.0, -0.12)
	_set_limb(model.el_l, -0.34, 0.0, 0.0)
	_set_limb(model.el_r, -0.34, 0.0, 0.0)
	_set_limb(model.thigh_l, -0.02, 0.0, 0.05)
	_set_limb(model.thigh_r, -0.02, 0.0, -0.05)
	_set_limb(model.knee_l, -0.05, 0.0, 0.0)
	_set_limb(model.knee_r, -0.05, 0.0, 0.0)
	model.hips.position.y -= _land_t * 0.35

func _pose_run(dt: float) -> void:
	_reset_pose()
	var spd := clampf(move_speed / RUN_SPEED, 0.0, 1.0)
	# stride length grows with speed: a walk is ~0.75 steps/s, a sprint ~1.6
	var cadence := lerpf(2.1, 3.3, spd)
	_phase = fmod(_phase + dt * cadence * TAU, TAU)
	var amp := lerpf(0.26, 0.64, spd)
	var s := sin(_phase)
	var c := cos(_phase)
	# --- legs
	_set_limb(model.thigh_l, s * amp, 0.0, 0.05)
	_set_limb(model.thigh_r, -s * amp, 0.0, -0.05)
	_set_limb(model.knee_l, -(0.20 + maxf(0.0, -s) * amp * 2.30 + (1.0 - spd) * 0.25), 0.0, 0.0)
	_set_limb(model.knee_r, -(0.20 + maxf(0.0, s) * amp * 2.30 + (1.0 - spd) * 0.25), 0.0, 0.0)
	_set_limb(model.foot_l, -s * 0.28 - 0.12, 0.0, 0.0)
	_set_limb(model.foot_r, s * 0.28 - 0.12, 0.0, 0.0)
	# --- pelvis bobs twice per stride and rolls with the planted leg
	model.hips.position.y = AvatarModel.HIP_Y - 0.03 + absf(c) * 0.055 - spd * 0.02 - _land_t * 0.3
	model.hips.rotation = Vector3(0.0, s * 0.10, -s * 0.06)
	# --- torso counter rotates, leans forward as you speed up
	model.spine.rotation = Vector3(0.06 + spd * 0.22, -s * 0.16, s * 0.03)
	model.neck.rotation = Vector3(-0.04 - spd * 0.12, s * 0.06, 0.0)
	model.head.rotation = Vector3(-0.02 - spd * 0.06, 0.0, 0.0)
	# --- arms swing opposite the legs, elbows pump at speed
	var arm_amp := lerpf(0.26, 0.62, spd)
	_set_limb(model.sh_l, -s * arm_amp + 0.05, 0.0, 0.10)
	_set_limb(model.sh_r, s * arm_amp + 0.05, 0.0, -0.10)
	_set_limb(model.el_l, -(0.55 + spd * 0.75) - maxf(0.0, s) * 0.55, 0.0, 0.0)
	_set_limb(model.el_r, -(0.55 + spd * 0.75) - maxf(0.0, -s) * 0.55, 0.0, 0.0)

## Standing with a weapon: both hands on it, arms follow the aim pitch, the
## shoulders take the recoil kick.
func _pose_aim_idle(_dt: float) -> void:
	_reset_pose()
	var br := sin(_breathe * 1.7)
	var aim := clampf(gun_pitch, -0.9, 0.9)
	model.hips.position.y = AvatarModel.HIP_Y - 0.02 + br * 0.008 - _land_t * 0.22
	model.hips.rotation = Vector3(0.0, 0.10, 0.0)
	model.spine.rotation = Vector3(0.10 + aim * 0.16 + _kick, -0.12, 0.0)
	model.neck.rotation = Vector3(-0.06 - aim * 0.20, -0.06, 0.0)
	model.head.rotation = Vector3(-0.02 - aim * 0.22, 0.0, 0.0)
	_set_limb(model.thigh_l, -0.06, 0.0, 0.09)
	_set_limb(model.thigh_r, 0.08, 0.0, -0.09)
	_set_limb(model.knee_l, -0.10, 0.0, 0.0)
	_set_limb(model.knee_r, -0.16, 0.0, 0.0)
	_gun_arms(aim)

## Both hands on the weapon: right hand on the grip, left hand on the hand guard.
func _gun_arms(aim: float) -> void:
	_set_limb(model.sh_r, 0.18 + aim * 0.55 + _kick * 1.2, 0.0, -0.34)
	_set_limb(model.el_r, 1.78 - aim * 0.22, 0.0, 0.0)
	_set_limb(model.sh_l, 0.94 + aim * 0.60 + _kick * 1.2, 0.0, 0.50)
	_set_limb(model.el_l, 1.04 - aim * 0.18, 0.0, 0.0)

## Walking with a weapon: same upper body, moving legs.
func _pose_aim_run(dt: float) -> void:
	_pose_aim_idle(dt)
	var spd := clampf(move_speed / RUN_SPEED, 0.0, 1.0)
	var cadence := lerpf(2.0, 3.1, spd)
	_phase = fmod(_phase + dt * cadence * TAU, TAU)
	var amp := lerpf(0.20, 0.42, spd)
	var s := sin(_phase)
	_set_limb(model.thigh_l, s * amp, 0.0, 0.05)
	_set_limb(model.thigh_r, -s * amp, 0.0, -0.05)
	_set_limb(model.knee_l, -(0.20 + maxf(0.0, -s) * amp * 2.1), 0.0, 0.0)
	_set_limb(model.knee_r, -(0.20 + maxf(0.0, s) * amp * 2.1), 0.0, 0.0)
	model.hips.position.y = AvatarModel.HIP_Y - 0.03 + absf(cos(_phase)) * 0.045

## Arms for a carried item (grenade / gloo canister / medkit): right hand holds
## it up where the mount is, left hand steadies it.
func _hold_item_arms() -> void:
	var aim := clampf(gun_pitch, -0.9, 0.9)
	# arm up in front of the chest, forearm folded so the item sits in the hand
	_set_limb(model.sh_r, 0.38 + aim * 0.55 + _kick * 1.2, 0.0, -0.22)
	_set_limb(model.el_r, 1.34 - aim * 0.20, 0.0, 0.0)
	if held_kind == "gloo" or held_kind == "medkit":
		# both hands on the canister / kit
		_set_limb(model.sh_l, 0.56 + aim * 0.50 + _kick * 1.2, 0.0, 0.34)
		_set_limb(model.el_l, 1.28 - aim * 0.18, 0.0, 0.0)
	else:
		# grenade: the other hand comes up near the pin
		_set_limb(model.sh_l, 0.62 + aim * 0.45, 0.0, 0.30)
		_set_limb(model.el_l, 1.34, 0.0, 0.0)

## Standing / walking with a consumable in hand.
func _pose_hold_item(dt: float) -> void:
	_reset_pose()
	var br := sin(_breathe * 1.7)
	model.hips.position.y = AvatarModel.HIP_Y - 0.02 + br * 0.008 - _land_t * 0.22
	model.spine.rotation = Vector3(0.07, -0.10, 0.0)
	model.neck.rotation = Vector3(-0.05, 0.05, 0.0)
	model.head.rotation = Vector3(-0.02 - clampf(gun_pitch, -0.9, 0.9) * 0.18, 0.0, 0.0)
	_set_limb(model.thigh_l, -0.06, 0.0, 0.09)
	_set_limb(model.thigh_r, 0.08, 0.0, -0.09)
	_set_limb(model.knee_l, -0.10, 0.0, 0.0)
	_set_limb(model.knee_r, -0.16, 0.0, 0.0)
	_hold_item_arms()

func _pose_crouch(dt: float) -> void:
	_reset_pose()
	var moving := move_speed > 0.25
	_phase = fmod(_phase + dt * (2.4 if moving else 1.0) * TAU * 0.5, TAU)
	var s := sin(_phase)
	var amp := 0.34 if moving else 0.0
	# squat: thighs forward, knees folded, hips dropped
	model.hips.position.y = AvatarModel.HIP_Y - 0.40
	model.hips.rotation = Vector3(0.10, 0.0, 0.0)
	model.spine.rotation = Vector3(0.34, -s * 0.12, 0.0)
	model.neck.rotation = Vector3(-0.22, 0.0, 0.0)
	_set_limb(model.thigh_l, 0.95 + s * amp, 0.0, 0.10)
	_set_limb(model.thigh_r, 0.95 - s * amp, 0.0, -0.10)
	_set_limb(model.knee_l, -1.75, 0.0, 0.0)
	_set_limb(model.knee_r, -1.75, 0.0, 0.0)
	_set_limb(model.foot_l, 0.70, 0.0, 0.0)
	_set_limb(model.foot_r, 0.70, 0.0, 0.0)
	_set_limb(model.sh_l, 0.55 - s * 0.25, 0.0, 0.16)
	_set_limb(model.sh_r, 0.55 + s * 0.25, 0.0, -0.16)
	_set_limb(model.el_l, -1.35, 0.0, 0.0)
	_set_limb(model.el_r, -1.35, 0.0, 0.0)

func _pose_prone(dt: float) -> void:
	_reset_pose()
	_phase = fmod(_phase + dt * (3.4 if move_speed > 0.2 else 1.2), TAU)
	var s := sin(_phase)
	# lie face down: body "up" tips forward to -Z, chest ~0.3 m off the floor
	model.body.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	model.body.position = Vector3(0, 0.30, 0.15)
	model.hips.position = Vector3(0, AvatarModel.HIP_Y, 0)
	model.spine.rotation = Vector3(-0.10 - absf(s) * 0.05, 0.0, 0.0)
	model.neck.rotation = Vector3(0.55, 0.0, 0.0)
	model.head.rotation = Vector3(0.30, 0.0, 0.0)
	_set_limb(model.thigh_l, 0.10, 0.0, 0.10)
	_set_limb(model.thigh_r, 0.10, 0.0, -0.10)
	_set_limb(model.knee_l, -0.25 - maxf(0.0, s) * 0.45, 0.0, 0.0)
	_set_limb(model.knee_r, -0.25 - maxf(0.0, -s) * 0.45, 0.0, 0.0)
	_set_limb(model.foot_l, 0.35, 0.0, 0.0)
	_set_limb(model.foot_r, 0.35, 0.0, 0.0)
	# crawl stroke: alternating arms reach ahead and pull
	_set_limb(model.sh_l, 1.45 + s * 0.55, 0.0, 0.25)
	_set_limb(model.sh_r, 1.45 - s * 0.55, 0.0, -0.25)
	_set_limb(model.el_l, -0.45, 0.0, 0.0)
	_set_limb(model.el_r, -0.45, 0.0, 0.0)

func _pose_air(dt: float) -> void:
	_reset_pose()
	var rise := clampf(velocity.y / JUMP_V, -1.0, 1.0)
	# tuck on the way up, reach for the floor on the way down
	model.hips.position.y = AvatarModel.HIP_Y - 0.04
	model.spine.rotation = Vector3(0.12 + maxf(0.0, -rise) * 0.12, 0.0, 0.0)
	_set_limb(model.thigh_l, 0.55 - rise * 0.25, 0.0, 0.08)
	_set_limb(model.thigh_r, 0.20 + rise * 0.30, 0.0, -0.08)
	_set_limb(model.knee_l, -1.35 - maxf(0.0, rise) * 0.35, 0.0, 0.0)
	_set_limb(model.knee_r, -0.65 + maxf(0.0, -rise) * 0.25, 0.0, 0.0)
	_set_limb(model.foot_l, 0.25, 0.0, 0.0)
	_set_limb(model.foot_r, 0.10, 0.0, 0.0)
	# arms swing FORWARD and up as you leave the ground, then come out to the
	# sides for balance on the way down  (+X on the shoulder = forward)
	var fwd_arm := 1.10 + maxf(0.0, rise) * 0.45
	_set_limb(model.sh_l, fwd_arm, 0.0, 0.30)
	_set_limb(model.sh_r, fwd_arm, 0.0, -0.30)
	_set_limb(model.el_l, 0.42 + maxf(0.0, -rise) * 0.30, 0.0, 0.0)
	_set_limb(model.el_r, 0.42 + maxf(0.0, -rise) * 0.30, 0.0, 0.0)

## The boxing combo is an overlay: it wins over whatever the legs are doing.
func _apply_punch() -> void:
	var t := clampf(_punch_t / 0.40, 0.0, 1.0)
	# 0 -> wind up, 0.3 -> extended, 1 -> back to guard
	var out := sin(clampf(t / 0.55, 0.0, 1.0) * PI)
	var back := clampf((t - 0.45) / 0.55, 0.0, 1.0)
	var ext := out * (1.0 - back * 0.75)
	model.spine.rotation.y += -0.45 * ext
	model.spine.rotation.x += 0.10 * ext
	model.hips.rotation.y += -0.18 * ext
	match _punch_kind:
		0:  # straight right through the guard
			_set_limb(model.sh_r, 1.35 * ext + 0.25, -0.25 * ext, -0.10)
			_set_limb(model.el_r, lerpf(-1.6, -0.12, ext), 0.0, 0.0)
			_set_limb(model.sh_l, 0.5 * ext + 0.2, 0.18 * ext, 0.10)
			_set_limb(model.el_l, lerpf(-1.5, -1.9, ext), 0.0, 0.0)
		1:  # left hook, wide arc
			_set_limb(model.sh_l, 0.95 * ext + 0.2, 0.15 * ext, 0.10 + 0.95 * ext)
			_set_limb(model.el_l, lerpf(-1.75, -1.05, ext), 0.0, 0.0)
			_set_limb(model.sh_r, 0.45 * ext + 0.15, 0.0, -0.10)
			_set_limb(model.el_r, -1.85, 0.0, 0.0)
		_:  # uppercut, right hand from the hip
			_set_limb(model.sh_r, lerpf(0.15, 2.05, ext), 0.0, -0.08)
			_set_limb(model.el_r, lerpf(-2.0, -0.55, ext), 0.0, 0.0)
			_set_limb(model.sh_l, 0.6 * ext + 0.2, 0.0, 0.12)
			_set_limb(model.el_l, -1.7, 0.0, 0.0)
	# the whole body drops into the punch a little
	model.hips.position.y -= 0.05 * ext
	if prone or crouching:
		pass

func _hit_check() -> void:
	if city_world == null:
		return
	var fwd := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	var origin := global_position + Vector3(0, 1.15, 0) + fwd * 0.7
	city_world.punch_barrels(origin, fwd, 2.7, 9.0)

# ------------------------------------------------------------------ camera

## Third person over the shoulder rig.  main.gd calls this every frame it is
## the active actor; the returned transform is already collision corrected.
## Nothing may ever end up under the island: if the capsule is below the baked
## terrain height the body is lifted back on top of it.
func _terrain_clamp() -> void:
	if city_world == null or city_world.island == null:
		return
	var gh: float = city_world.island.height(global_position.x, global_position.z)
	if global_position.y < gh - 0.55:
		global_position.y = gh + 0.02
		if velocity.y < 0.0:
			velocity.y = 0.0

## 0 = standing, 1 = crouched, 2 = prone (tightens weapon spread).
func stance() -> int:
	if prone:
		return 2
	if crouching:
		return 1
	return 0

func planar_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func eye_position() -> Vector3:
	return global_position + Vector3(0, 1.45 if not prone else 0.75, 0)

func set_model_visible(v: bool) -> void:
	if model != null and model.visible != v:
		model.visible = v
	_model_hidden = not v

func gun_muzzle() -> Vector3:
	if holding_gun == null or not is_instance_valid(holding_gun):
		return eye_position() + eye_forward() * 0.6
	var b := holding_gun.global_transform
	return b.origin + (-b.basis.z) * 0.75

func kick_arms(amount: float) -> void:
	_kick = minf(_kick + amount * 0.06, 0.45)

func hold_gun(g: Node3D) -> void:
	set_held(g, "gun")

## Put anything in the right hand: a gun, a grenade, a gloo canister or a
## medkit.  `kind` also decides which pose the arms take.
func set_held(node: Node3D, kind: String = "gun") -> void:
	if model == null:
		return
	if _gun_mount == null:
		_gun_mount = Node3D.new()
		_gun_mount.name = "GunMount"
		model.spine.add_child(_gun_mount)
	if holding_gun != null and is_instance_valid(holding_gun):
		holding_gun.queue_free()
	holding_gun = node
	held_kind = kind
	if node == null:
		return
	# the gun sits a little forward and to the right, the consumables closer in
	if kind == "gun":
		_gun_mount.position = Vector3(0.26, 0.34, -0.34)
		node.scale = Vector3(1.45, 1.45, 1.45)
	else:
		_gun_mount.position = Vector3(0.24, 0.30, -0.30)
		node.scale = Vector3(1.3, 1.3, 1.3)
	_gun_mount.add_child(node)
	node.position = Vector3.ZERO
	node.rotation = Vector3.ZERO

## Square the body up to where the camera is looking.  Called by CombatSystem on
## every shot, so if you aim behind you the whole avatar snaps round to that side
## the moment you pull the trigger.
func face_aim(t: float = 0.7) -> void:
	_face_t = maxf(_face_t, t)

func camera_goal() -> Array:
	var head := global_position + Vector3(0, 1.45 if not prone else 0.75, 0)
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var dist := (CAM_DIST + (0.6 if sprinting else 0.0) - (0.5 if prone else 0.0)) * cam_zoom
	if aiming:
		dist = 2.35 * cam_zoom
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	var shoulder := 0.52 if holding_gun != null else 0.0
	if aiming:
		shoulder = 0.85
	if shoulder > 0.0:
		head += side * shoulder
	if aiming:
		head += Vector3(0, 0.12, 0)
	var want := head - dir * dist + Vector3(0, CAM_HEIGHT if not aiming else 0.05, 0)
	# keep the camera out of walls
	var q := PhysicsRayQueryParameters3D.create(head, want, 1 | 2)
	q.hit_from_inside = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit["position"] as Vector3) + (head - hit["position"]).normalized() * 0.35
	return [want, head + dir * 6.0]

func eye_forward() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

## Put the walker down at a position (used when stepping out of the car).
func place_at(p: Vector3, face_yaw: float) -> void:
	global_position = p
	velocity = Vector3.ZERO
	yaw = face_yaw
	rotation.y = face_yaw
	reset_physics_interpolation()
