class_name PlayerCar
extends CharacterBody3D

## Arcade car physics: speed lives along the car's forward axis, steering is
## speed sensitive, lateral velocity is damped by "grip" so you can drift with
## the handbrake, and hitting a wall scrubs off speed.

signal crashed(strength: float)

## Every type has its own numbers, see CarModel.SPEC.  These are the defaults
## (sedan) and get replaced by _apply_spec() in _ready().
const MAX_SPEED := 50.0        ## kept for the speedo / other scripts (sedan)
## Real gravity.  At 9.81 a car leaves a crest at the same rate a real one does;
## the ground clamp and the suspension keep it planted instead of extra gravity.
const GRAVITY := 9.81
const BODY_LIFT := 0.12        ## how far the origin sits above the ground
## A kerb, a road edge or the edge of a town's asphalt plate is only a few
## centimetres high, but a CharacterBody3D stops dead against it.  When the car is
## blocked and there is room 34 cm higher up, it simply climbs.
const STEP_ASSIST := 0.34

var max_speed := MAX_SPEED
var boost_mult := 1.35
var accel_p := 17.0
var brake_p := 34.0
var reverse_p := 13.0
var coast_p := 6.5
var steer_rate := 1.85
var grip_p := 9.5
var drift_grip := 2.0
var wheel_r := 0.35

var kind := "sedan"
var paint: Color = Color("e63b2e")
## The height field of the island: an analytic second opinion on where the
## ground is, so the clamp can never be fooled by a missed ray.
var island: Island = null
var road_net: RoadNet = null
var speed := 0.0
var steer := 0.0
var boosting := false
var _spin := 0.0
var _wheels: Array = []
var _model: Node3D
var _body_pitch := 0.0
var _body_roll := 0.0
var _slope_pitch := 0.0     ## how steep the ground is under the car (radians)
var _slope_roll := 0.0
var _bob := 0.0             ## suspension travel, metres
var _bob_v := 0.0
var _bob_phase := 0.0
var _wheel_y: Array = [0.0, 0.0, 0.0, 0.0]
var _prev_vy := 0.0
var _hint := -1.0e9          ## terrain height to fall back on when a ray misses

func _ready() -> void:
	name = "PlayerCar"
	collision_layer = 2
	collision_mask = 1 | 4
	# a steep mountain road must not turn the car loose: 62 degrees is still
	# "floor", and the cast-iron ground clamp below catches everything else
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.9
	floor_stop_on_slope = false
	slide_on_ceiling = false
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	safe_margin = 0.02
	_apply_spec()

	var sp := CarModel.spec(kind)
	var h: float = float(sp["mass_h"])
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(sp["wid"]) * 0.94, h, float(sp["len"]) * 0.96)
	cs.shape = shape
	cs.position = Vector3(0, BODY_LIFT + h * 0.5, 0)
	add_child(cs)

	var model := CarModel.build(paint, kind, false, true)
	_model = model.root
	_wheels = model.wheels
	wheel_r = float(model["wheel_r"])
	_wheel_y = []
	for i in _wheels.size():
		_wheel_y.append(0.0)
	# the model is authored standing on y = 0, but the body origin rides
	# BODY_LIFT above the ground, so the whole model hangs that much lower
	_model.position.y = -BODY_LIFT
	add_child(_model)
	for entry in _wheels:
		var w0: Node3D = entry[0]
		w0.position.y = wheel_r

## Copy the type's handling numbers into this car.
func _apply_spec() -> void:
	var sp := CarModel.spec(kind)
	max_speed = float(sp["top"])
	accel_p = float(sp["accel"])
	steer_rate = float(sp["steer"])
	grip_p = float(sp["grip"])
	brake_p = float(sp["brake"])
	reverse_p = maxf(8.0, float(sp["top"]) * 0.26)
	coast_p = 6.5
	boost_mult = float(sp["boost"])
	drift_grip = grip_p * 0.22
	wheel_r = float(sp["wheel_r"])

func is_bike() -> bool:
	return kind == "bike"

## Hard guarantee that the car can never be inside the ground: after the physics
## step we look straight down and lift the body back on top of whatever is under
## it.  This is what stops the car sinking into a mountain at speed.
func _ground_clamp() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from: Vector3 = global_position + Vector3(0, 6.0, 0)
	var to: Vector3 = global_position - Vector3(0, 12.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	# analytic height of the terrain: the ray can miss when the body is already
	# buried, the height field never can
	var gy: float = -1.0e9
	if island != null:
		gy = island.height(global_position.x, global_position.z)
	if not hit.is_empty():
		gy = maxf(gy, float(hit["position"].y))
	if gy < -1.0e8:
		if global_position.y < -30.0:
			respawn()
		return
	if global_position.y < gy + BODY_LIFT:
		global_position.y = gy + BODY_LIFT
		if velocity.y < 0.0:
			velocity.y = 0.0
		reset_physics_interpolation()

## On-screen controls (see TouchControls).  The right thumb stick steers, and
## pushing it up is the throttle and down is the brake, so a phone player drives
## with the same stick they walk with.
var touch_throttle := 0.0
var touch_brake := 0.0
var touch_steer := 0.0
var touch_boost := false

func _physics_process(dt: float) -> void:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var throttle := maxf(Input.get_action_strength("accelerate"), touch_throttle)
	var braking := maxf(Input.get_action_strength("brake"), touch_brake)
	var steer_in := clampf(Input.get_axis("steer_left", "steer_right") + touch_steer, -1.0, 1.0)
	var handbrake := Input.is_action_pressed("handbrake") or touch_brake > 0.85
	boosting = (Input.is_action_pressed("boost") or touch_boost) and throttle > 0.05

	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	elif velocity.y < 0.0:
		velocity.y = -0.5

	var top := max_speed * (boost_mult if boosting else 1.0)
	# ---- longitudinal
	if throttle > 0.02:
		var a := accel_p * throttle
		if speed < 0.0:
			a *= 2.2
		if boosting:
			a *= 1.6
		speed = move_toward(speed, top, a * dt)
	elif braking > 0.02:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, brake_p * braking * dt)
		else:
			speed = move_toward(speed, -reverse_p, brake_p * 0.45 * braking * dt)
	else:
		speed = move_toward(speed, 0.0, coast_p * dt)
	if handbrake:
		speed = move_toward(speed, 0.0, 24.0 * dt)

	# ---- steering
	steer = lerpf(steer, steer_in, 1.0 - exp(-11.0 * dt))
	var sf := clampf(absf(speed) / 8.0, 0.0, 1.0)
	var damp := clampf(1.0 - absf(speed) / (max_speed * 2.6), 0.42, 1.0)
	rotate_y(-steer * steer_rate * sf * damp * signf(speed) * dt)

	fwd = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	# ---- lateral grip / drift
	var lateral := velocity - fwd * velocity.dot(fwd)
	lateral.y = 0.0
	var grip := drift_grip if handbrake else grip_p
	var keep := exp(-grip * dt)
	velocity.x = fwd.x * speed + lateral.x * keep
	velocity.z = fwd.z * speed + lateral.z * keep

	_try_step(fwd, throttle, dt)
	move_and_slide()

	# ---- scrub speed when we hit something
	var along := velocity.dot(fwd)
	if absf(along) < absf(speed) - 0.4:
		var hit := absf(speed) - absf(along)
		if hit > 6.0:
			crashed.emit(hit)
		speed = along

	_ground_clamp()
	_animate(dt, steer_in)

## Arcade step-up: a kerb or the lip of a road plate is a couple of centimetres
## high, and without this the car would bump into it and stop.  If the body is
## blocked where it is but free one step higher, it hops up.
func _try_step(fwd: Vector3, throttle: float, dt: float) -> void:
	if throttle < 0.05 or not is_on_floor():
		return
	var dist: float = maxf(absf(speed), 3.0) * dt + 0.06
	var motion := fwd * dist * signf(maxf(speed, 1.0))
	if not test_move(global_transform, motion):
		return
	var lifted := global_transform.translated(Vector3(0.0, STEP_ASSIST, 0.0))
	if test_move(lifted, motion):
		return
	global_position.y += STEP_ASSIST
	if velocity.y < 0.0:
		velocity.y = 0.0
	reset_physics_interpolation()

## Ground reading under each wheel.  Returns the world height of the surface, or
## the car's own height when a wheel is hanging over nothing.
func _probe_ground(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return global_position.y
	var from := p + Vector3(0.0, 1.4, 0.0)
	var to := p + Vector3(0.0, -1.6, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	var g: float = -1.0e9
	if island != null:
		g = island.height(p.x, p.z)
	if not hit.is_empty():
		g = maxf(g, float(hit["position"].y))
	elif _hint != -1.0e9:
		g = maxf(g, _hint)
	if g < -1.0e8:
		return global_position.y
	return g

## Read the ground under all four wheels -> pitch, roll and per wheel travel.
func _read_suspension() -> void:
	var i := 0
	for entry in _wheels:
		var w: Node3D = entry[0]
		var g := _probe_ground(w.global_position)
		# local y the wheel centre needs to sit exactly on the ground
		_wheel_y[i] = clampf(g - global_position.y + BODY_LIFT, -0.34, 0.34)
		i += 1
	var sp := CarModel.spec(kind)
	var base: float = float(sp["base"]) * 2.0
	var track: float = maxf(0.6, float(sp["track"]) * 2.0)
	if _wheels.size() >= 4:
		# build order is [0]=front-left, [1]=front-right, [2]=rear-left, [3]=rear-right
		var fl: float = _wheel_y[0]
		var fr: float = _wheel_y[1]
		var rl: float = _wheel_y[2]
		var rr: float = _wheel_y[3]
		# +X is the car's right, +X rotation lifts the nose, +Z lifts the right side
		var target_pitch := atan2(((fl + fr) - (rl + rr)) * 0.5, base)
		var target_roll := atan2(((fr + rr) - (fl + rl)) * 0.5, track)
		_slope_pitch = lerpf(_slope_pitch, clampf(target_pitch, -0.62, 0.62), 1.0 - exp(-12.0 * dt_safe()))
		_slope_roll = lerpf(_slope_roll, clampf(target_roll, -0.62, 0.62), 1.0 - exp(-12.0 * dt_safe()))
	else:
		# two wheels: pitch from front vs rear, roll is the rider leaning over
		var f: float = _wheel_y[0]
		var r: float = _wheel_y[1]
		_slope_pitch = lerpf(_slope_pitch, clampf(atan2(f - r, base), -0.62, 0.62),
			1.0 - exp(-12.0 * dt_safe()))
		_slope_roll = 0.0

func dt_safe() -> float:
	return 1.0 / maxf(Engine.get_physics_ticks_per_second(), 1)

func _animate(dt: float, steer_in: float) -> void:
	# tread spins at the real rolling speed for this wheel size
	_spin = fmod(_spin + (speed / maxf(wheel_r, 0.1)) * dt, TAU)
	_read_suspension()
	# ---- wheels: roll, steer, and ride the bumps
	var i := 0
	var bike := is_bike()
	for entry in _wheels:
		var w: Node3D = entry[0]
		var front: bool = entry[1]
		w.rotation.x = _spin
		# +Y yaw points a wheel to the LEFT, so a right turn needs -steer
		if bike:
			w.rotation.y = 0.0
			w.rotation.z = -steer * 0.18 if front else 0.0
		else:
			w.rotation.y = (-steer * 0.62) if front else 0.0
		i += 1
	# ---- body: weight transfer + the slope of the mountain under the tyres
	var accel_est := (Input.get_action_strength("accelerate") - Input.get_action_strength("brake")) * 0.035
	var airborne := not is_on_floor()
	var dive := 0.0
	if airborne:
		dive = clampf(-velocity.y * 0.012, -0.10, 0.10)
	var speed_k := clampf(absf(speed) / maxf(max_speed, 1.0), 0.0, 1.0)
	_body_pitch = lerpf(_body_pitch, -accel_est + dive + _slope_pitch, 1.0 - exp(-8.0 * dt))
	# a bike leans hard into the corner, a car leans out of it a little
	var lean_amt := -0.62 if bike else -0.07
	var roll_target := steer_in * speed_k * lean_amt + _slope_roll
	_body_roll = lerpf(_body_roll, roll_target, 1.0 - exp(-(11.0 if bike else 8.0) * dt))
	# ---- suspension spring: dips on landing, floats over crests
	var rough := speed_k
	_bob_phase += dt * (7.0 + absf(speed) * 0.6)
	var bump := sin(_bob_phase) * 0.010 * rough
	if is_on_floor():
		var dv: float = velocity.y - _prev_vy
		if dv < -1.5:
			_bob_v += clampf(dv * 0.085, -0.5, 0.0)
		_bob_v += (bump - _bob) * 26.0 * dt
		_bob_v *= exp(-6.0 * dt)
		_bob = clampf(_bob + _bob_v, -0.16, 0.12)
	_prev_vy = velocity.y
	if _model != null:
		_model.rotation = Vector3(_body_pitch, 0.0, _body_roll)
		_model.position.y = _bob - BODY_LIFT
		_place_wheels()

## Second and final pass on the wheels: now that the body has its real pitch and
## roll, put every tyre centre exactly one radius above the surface below it.
## Solving in model space is what stops a tyre dipping into the road when the
## body leans on a bank.
func _place_wheels() -> void:
	if _model == null or _wheels.is_empty():
		return
	var inv := _model.global_transform.affine_inverse()
	var i := 0
	for entry in _wheels:
		var w: Node3D = entry[0]
		var wp := w.global_position
		var g := _probe_ground(wp)
		var ly: float = (inv * Vector3(wp.x, g + wheel_r, wp.z)).y
		w.position.y = clampf(ly, wheel_r - 0.34, wheel_r + 0.34)
		i += 1

## Park the car flat on whatever it is standing on (used by the road cars).
func sit_on_ground(hint: float = -1.0e9) -> void:
	_hint = hint
	var p := global_position
	var g := _probe_ground(p)
	global_position.y = g + BODY_LIFT
	var spb := CarModel.spec(kind)
	var hb: float = float(spb["base"])
	var ht: float = maxf(0.6, float(spb["track"]))
	var h_f := _probe_ground(p + global_transform.basis * Vector3(0, 0, -hb))
	var h_b := _probe_ground(p + global_transform.basis * Vector3(0, 0, hb))
	var h_l := _probe_ground(p + global_transform.basis * Vector3(-ht, 0, 0))
	var h_r := _probe_ground(p + global_transform.basis * Vector3(ht, 0, 0))
	var sp := CarModel.spec(kind)
	var pitch := clampf(atan2(h_f - h_b, float(sp["base"]) * 2.0), -0.5, 0.5)
	var roll := clampf(atan2(h_r - h_l, maxf(0.6, float(sp["track"]) * 2.0)), -0.5, 0.5)
	if is_bike():
		roll = 0.0
	_model.rotation = Vector3(pitch, 0.0, roll)
	_model.position.y = -BODY_LIFT
	_body_pitch = pitch
	_body_roll = roll
	# and set the wheels down on their own patch of ground, so a parked car on a
	# slope does not hover on one axle
	_read_suspension()
	_place_wheels()
	_hint = -1.0e9

func speed_kmh() -> float:
	return absf(speed) * 3.6

## Put the car back on the nearest road lane, facing along it.
func respawn() -> void:
	if road_net != null:
		var seg: Array = road_net.nearest_road_segment(global_position)
		var rp: Vector3 = seg[0]
		var rd: Vector3 = seg[1]
		speed = 0.0
		velocity = Vector3.ZERO
		global_position = Vector3(rp.x, rp.y + 0.7, rp.z)
		rotation = Vector3(0, atan2(-rd.x, -rd.z), 0)
		reset_physics_interpolation()
		return
	_legacy_respawn()

func _legacy_respawn() -> void:
	var lx := clampi(int(roundf((global_position.x - CityConfig.ORIGIN) / CityConfig.CELL)), 0, CityConfig.GRID)
	var lz := clampi(int(roundf((global_position.z - CityConfig.ORIGIN) / CityConfig.CELL)), 0, CityConfig.GRID)
	var rx := CityConfig.road_coord(lx)
	var rz := CityConfig.road_coord(lz)
	var pos: Vector3
	var yaw: float
	if absf(global_position.x - rx) < absf(global_position.z - rz):
		# road running along Z: drive towards -Z on the right hand lane
		pos = Vector3(rx + CityConfig.LANE, 0.4, global_position.z)
		yaw = 0.0
	else:
		# road running along X: drive towards +X
		pos = Vector3(global_position.x, 0.4, rz + CityConfig.LANE)
		yaw = -PI * 0.5
	speed = 0.0
	velocity = Vector3.ZERO
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	reset_physics_interpolation()
