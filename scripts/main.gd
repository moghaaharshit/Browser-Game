extends Node3D

## Entry point. Builds the sky, the world, the player car, the camera rig, the
## traffic system and the HUD.  No scene files, no imported assets: everything
## is generated at runtime, so the project is tiny and loads fast.

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"boost": [KEY_SHIFT],
	"camera": [KEY_V, KEY_C],
	"respawn": [KEY_R],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL],
	"prone": [KEY_Z],
	"enter_car": [KEY_F],
	"shadow_toggle": [KEY_L],
	"help": [KEY_F1],
	"melee": [KEY_X],
	"reload": [KEY_R],
	"gloo": [KEY_G],
	"grenade": [KEY_H],
	"slot1": [KEY_1],
	"slot2": [KEY_2],
	"slot3": [KEY_3],
	"slot4": [KEY_4],
	"slot5": [KEY_5],
	"slot6": [KEY_6],
	"slot7": [KEY_7],
	"slot8": [KEY_8],
	"slot9": [KEY_9],
	"slot0": [KEY_0],
	"map": [KEY_M],
	"wheel": [KEY_TAB],
	"pickup": [KEY_E],
	"medkit": [KEY_K],
	"quit": [KEY_ESCAPE],
	"touch_ui": [KEY_F9],
}

## Three camera angles, cycled with V (C works too).
const CAM_CLOSE := 0      ## tight chase cam, hugs the car
const CAM_SPEED := 1      ## pulls back and widens the lens as you go faster
const CAM_CINE := 2       ## slow cinematic orbit / drone shot
const CAM_NAMES := ["CLOSE CAM", "SPEED CAM", "CINEMATIC CAM"]

var world: CityWorld
var car: PlayerCar
var walker: PlayerWalker
var on_foot := true
var traffic: TrafficManager
var hud: GameHUD
var map_ui: GameMapUI
var combat: CombatSystem
var combat_hud: CombatHUD
var radial: RadialMenu
var touch: TouchControls
var _prompt_t := 0.0
var cam: Camera3D
var sun: DirectionalLight3D

var _cam_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _cam_yaw := 0.0
var _cam_mode := 0
var _cine_t := 0.0
var _area_name := ""
var _shake := 0.0
var _fps_avg := 60.0
var _adapt_cd := 4.0
var _stats_t := 0.0
var _help_on := true
var _shadows := true
var _fog_base := 0.000055
var _map_fog := false
var _web := false             ## browsers only give pointer lock on a real click
var _hint: Label              ## "CLICK TO PLAY", web only

func _init() -> void:
	_register_inputs()
	_web = OS.has_feature("web")

func _ready() -> void:
	_setup_environment()

	world = CityWorld.new()
	add_child(world)

	# every car in the world is drivable; we start on foot next to one of them
	var sp: Dictionary = world.spawn_point()
	var near: PlayerCar = world.nearest_car(sp["pos"], 400.0)
	if near != null:
		car = near
	else:
		car = PlayerCar.new()
		car.kind = "sports"
		car.paint = Color("e63b2e")
		car.island = world.island
		car.position = sp["pos"]
		add_child(car)
	car.crashed.connect(_on_crash)
	car.road_net = world.roads

	walker = PlayerWalker.new()
	add_child(walker)
	walker.city_world = world
	walker.place_at(sp["walk"], sp["yaw"])
	walker.crouching = false

	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = 70.0
	cam.near = 0.25
	cam.far = 20000.0
	add_child(cam)
	cam.current = true

	hud = GameHUD.new()
	add_child(hud)

	map_ui = GameMapUI.new()
	add_child(map_ui)
	map_ui.set_player(walker)

	# --- gunplay
	combat = CombatSystem.new()
	add_child(combat)
	combat.setup(walker, cam, world)
	combat_hud = CombatHUD.new()
	add_child(combat_hud)
	combat_hud.attach(combat)
	radial = RadialMenu.new()
	add_child(radial)
	radial.attach(combat)
	combat.spawn_dummies(walker.global_position, 6)

	# on-screen thumb controls: they switch themselves on when the device has a
	# touch screen (phone, tablet, browser tab on a phone) and stay out of the way
	# on a desktop.  F9 forces them on or off.
	touch = TouchControls.new()
	add_child(touch)
	touch.attach(self, walker, car)
	if touch.enabled:
		hud.toast("TOUCH CONTROLS  ·  stick to walk, drag FIRE to aim, BAG for weapons", 6.0)

	if _web:
		_make_click_hint()

	_cam_pos = walker.global_position + Vector3(0, 2.4, 3.2)
	_look = walker.global_position + Vector3(0, 1.3, 0)
	cam.global_position = _cam_pos
	cam.look_at(_look, Vector3.UP)

	# the game starts on foot: walk up to the car and press F to drive
	on_foot = true
	car.set_physics_process(false)
	walker.city_world = world
	world.set_player(walker)
	world.barrel_exploded.connect(_on_barrel_exploded)
	if not _web:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.set_on_foot(true)
	combat.active = true
	combat_hud.armed = true
	var hint := "ON FOOT  ·  1-0 / wheel pick a gun, LMB fire, RMB aim, R reload, G gloo, H grenade, X punch"
	if _web:
		hint = "CLICK TO GRAB THE MOUSE  ·  WASD walk, F drive, TAB weapons, M map"
	hud.toast(hint, 7.0)

# ------------------------------------------------------------------ setup

## A browser tab cannot grab the mouse until the player clicks, and it also needs
## one click before the keyboard goes to the canvas — so say so, once.
func _make_click_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 13
	add_child(layer)
	_hint = Label.new()
	_hint.text = "CLICK TO PLAY\n\nWASD walk · F drive · TAB weapons · M map"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint.add_theme_font_size_override("font_size", 30)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("outline_size", 8)
	layer.add_child(_hint)
	var t := get_tree().create_timer(14.0)
	t.timeout.connect(_hide_hint)

func _hide_hint() -> void:
	if is_instance_valid(_hint):
		_hint.visible = false

func _register_inputs() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.15)
		for k in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if InputMap.has_action("punch"):
		InputMap.erase_action("punch")
	InputMap.add_action("punch", 0.1)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("punch", mb)
	if InputMap.has_action("aim"):
		InputMap.erase_action("aim")
	InputMap.add_action("aim", 0.1)
	var rm := InputEventMouseButton.new()
	rm.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("aim", rm)

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.20, 0.42, 0.80)
	sm.sky_horizon_color = Color(0.74, 0.83, 0.90)
	sm.sky_curve = 0.16
	sm.ground_bottom_color = Color(0.55, 0.66, 0.72)
	sm.ground_horizon_color = Color(0.72, 0.80, 0.88)
	sm.sun_angle_max = 14.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.5
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.88)
	env.fog_light_energy = 0.7
	env.fog_density = _fog_base
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.12
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -50, 0)
	sun.light_energy = 1.85
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.24
	sun.directional_shadow_split_3 = 0.55
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	add_child(sun)

# ------------------------------------------------------------------ loop

## Web only: grab the pointer on the click itself, which is the one moment the
## browser allows it.  Without this every frame logs a "user gesture required"
## error and the mouse look never engages.
func _input(event: InputEvent) -> void:
	if not _web or not on_foot:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		return
	if touch != null and touch.enabled:
		return
	if (map_ui != null and map_ui.is_open()) or (radial != null and radial.open):
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_hide_hint()

func _process(delta: float) -> void:
	if car == null or walker == null:
		return
	var map_open := map_ui.is_open()
	var wheel_open := radial != null and radial.open

	# mouse: captured while on foot, free in the car, over the map and on the wheel
	var touch_on: bool = touch != null and touch.enabled
	if on_foot and not map_open and not wheel_open and not touch_on:
		# a browser refuses pointer lock that was not asked for by a real click, so
		# on the web the capture happens in _input() instead of every frame
		if not _web and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	walker.frozen = map_open or wheel_open
	if combat != null:
		combat.active = on_foot and not map_open and not wheel_open
		if combat_hud != null:
			combat_hud.armed = on_foot and not wheel_open
		if not on_foot and combat.ads:
			combat.ads = false
			walker.aiming = false
	# pull the haze back while the big map is up: the terrain, the coast and the
	# ocean read clearly at 12 km
	if map_open != _map_fog:
		_map_fog = map_open
		var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we == null:
			for c in get_children():
				if c is WorldEnvironment:
					we = c
		if we != null and we.environment != null:
			we.environment.fog_density = _fog_base * (0.12 if map_open else 1.0)

	if Input.is_action_just_pressed("touch_ui") and touch != null:
		touch.set_enabled(not touch.enabled)
		hud.toast("Touch controls %s" % ("on" if touch.enabled else "off"), 1.4)
	if Input.is_action_just_pressed("camera"):
		_cycle_camera()
	if Input.is_action_just_pressed("respawn") and not on_foot:
		car.respawn()
		hud.toast("Respawned on the road", 1.4)
	if Input.is_action_just_pressed("shadow_toggle"):
		_shadows = not _shadows
		sun.shadow_enabled = _shadows
		for c in world.get_children():
			if c is Node3D and c.name.begins_with("Block_"):
				for m in c.get_children():
					if m is MeshInstance3D:
						m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows \
							else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hud.toast("Shadows %s" % ("on" if _shadows else "off"), 1.2)
	if Input.is_action_just_pressed("help"):
		_help_on = not _help_on
		hud.set_help_visible(_help_on)
	if Input.is_action_just_pressed("map"):
		map_ui.toggle()
	if Input.is_action_just_pressed("enter_car") and not map_open:
		_toggle_vehicle()
	if on_foot and not map_open and combat != null:
		var armed := combat_hud != null and combat_hud.armed
		if Input.is_action_just_pressed("reload") and armed:
			combat.start_reload()
		elif Input.is_action_just_pressed("reload"):
			pass
		if Input.is_action_just_pressed("melee"):
			walker.punch()
		if Input.is_action_just_pressed("gloo"):
			if combat.place_gloo():
				hud.toast("GLOO WALL  %d / %d" % [combat.gloo_walls.size(), 3], 1.2)
			else:
				hud.toast("No gloo wall", 1.0)
		if Input.is_action_just_pressed("grenade"):
			if combat.throw_grenade():
				hud.toast("GRENADE OUT", 1.0)
			else:
				hud.toast("Out of grenades", 1.0)
		if Input.is_action_just_pressed("pickup"):
			var loot := LootItem.nearest(walker.global_position, 2.9)
			if loot != null:
				var msg := loot.collect(combat)
				if msg != "":
					hud.toast(msg, 1.5)
			else:
				hud.toast("Nothing here to pick up", 0.9)
		if Input.is_action_just_pressed("medkit"):
			if combat.use_medkit():
				hud.toast("MEDKIT USED", 1.0)
			else:
				hud.toast("No medkit", 0.9)
		for i in 10:
			var slot := i
			var act := "slot%d" % (slot + 1 if slot < 9 else 0)
			if InputMap.has_action(act) and Input.is_action_just_pressed(act):
				combat.equip_slot(slot)
	if on_foot and not map_open and not (combat_hud != null and combat_hud.armed):
		if Input.is_action_just_pressed("punch"):
			walker.punch()
	else:
		# ramming a barrel at speed sets it off
		if absf(car.speed) > 7.0:
			world.ram_barrels(car.global_position, 2.5, 1.2)
	if Input.is_action_just_pressed("quit"):
		if map_open:
			map_ui.close()
		elif Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			get_tree().quit()

	_update_camera(delta)
	_adaptive_quality(delta)

	# hud
	if on_foot:
		hud.update_drive(0.0, false)
	else:
		hud.update_drive(car.speed_kmh(), car.boosting)
	var here: Vector3 = walker.global_position if on_foot else car.global_position
	_prompt_t -= delta
	if _prompt_t <= 0.0:
		_prompt_t = 0.18
		if combat_hud != null:
			combat_hud.prompt = ""
			if on_foot and combat_hud.armed:
				var near := LootItem.nearest(walker.global_position, 2.9)
				if near != null:
					combat_hud.prompt = "[E]  " + near.pretty_name()
	_stats_t -= delta
	if _stats_t <= 0.0:
		_stats_t = 0.25
		var an := world.area_name(here)
		if an != _area_name:
			_area_name = an
			hud.update_area(an)
		hud.update_stats(Engine.get_frames_per_second(), world.chunk_count(), world.pending_count(),
			world.cars.size(), 0, 4)

# ------------------------------------------------------------------ on foot / driving

func _toggle_vehicle() -> void:
	if touch != null:
		touch.call("_release_all")
	if on_foot:
		var target: PlayerCar = world.nearest_car(walker.global_position, 6.5)
		if target == null:
			hud.toast("Walk closer to a car to get in", 1.6)
			return
		car = target
		car.road_net = world.roads
		_enter_car()
	else:
		_exit_car()

func _enter_car() -> void:
	on_foot = false
	walker.set_physics_process(false)
	walker.set_process(false)
	walker.visible = false
	walker.collision_layer = 0
	walker.collision_mask = 0
	car.set_physics_process(true)
	car.set_process(true)
	car.speed = 0.0
	car.reset_physics_interpolation()
	if not car.crashed.is_connected(_on_crash):
		car.crashed.connect(_on_crash)
	world.set_player(car)
	map_ui.set_player(car)
	hud.set_on_foot(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_cam_pos = walker.global_position + Vector3(0, 2.4, 3.2)
	_look = walker.global_position + Vector3(0, 1.3, 0)
	hud.toast("DRIVING  ·  WASD drive, Shift boost, Space handbrake, F get out", 2.6)

func _exit_car() -> void:
	on_foot = true
	var b := car.global_transform.basis
	var side := -b.x.normalized()          # step out on the left
	var spot := car.global_position + side * 2.6 + Vector3(0, 0.5, 0)
	walker.visible = true
	walker.collision_layer = 4
	walker.collision_mask = 1 | 2
	walker.set_physics_process(true)
	walker.set_process(true)
	walker.place_at(spot, car.global_rotation.y)
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.set_physics_process(false)
	world.set_player(walker)
	map_ui.set_player(walker)
	hud.set_on_foot(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_cam_pos = spot + Vector3(0, 2.0, 3.0)
	_look = spot + Vector3(0, 1.4, 0)
	hud.toast("ON FOOT  ·  F to get back in the car", 2.2)

func is_map_open() -> bool:
	return map_ui != null and map_ui.is_open()

func is_wheel_open() -> bool:
	return radial != null and radial.open

## --- small helpers used by the screenshot / self-test scripts
func house_door_near(p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1.0e9
	for d in HouseBuilder.doors:
		var dist: float = (d["pos"] as Vector3).distance_to(p)
		if dist < bd:
			bd = dist
			best = d
	return best

func stair_near(p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1.0e9
	for st in HouseBuilder.stairs:
		var dist: float = (st["start"] as Vector3).distance_to(p)
		if dist < bd:
			bd = dist
			best = st
	return best

func world_nearest_barrel(p: Vector3) -> Node3D:
	return world.nearest_barrel(p)

func _on_barrel_exploded(pos: Vector3, radius: float, power: float) -> void:
	_shake = maxf(_shake, 0.55 + power * 0.25)
	var actor: Node3D = walker if on_foot else car
	var d: Vector3 = actor.global_position - pos
	d.y = 0.0
	if d.length() < radius * 2.2:
		var push := d.normalized() * clampf(1.0 - d.length() / (radius * 2.2), 0.0, 1.0)
		if on_foot:
			walker.velocity += push * 14.0 + Vector3(0, 4.0, 0)
		else:
			car.velocity += push * 6.0

func _update_camera(delta: float) -> void:
	if on_foot and walker != null:
		_update_walk_camera(delta)
		return
	# read the *interpolated* transform so the camera follows the smooth sub-tick
	# position of the car instead of stepping with the 60 Hz physics tick
	var ct: Transform3D = car.get_global_transform_interpolated()
	var cpos := ct.origin
	var spd := absf(car.speed)
	var k := clampf(spd / PlayerCar.MAX_SPEED, 0.0, 1.25)
	_cam_yaw = lerp_angle(_cam_yaw, ct.basis.get_euler().y, 1.0 - exp(-8.0 * delta))

	var desired := cpos
	var look_target := cpos + Vector3(0, 1.4, 0)
	var fov_target := 68.0
	var smooth := 13.0
	var follow := 1.0 - exp(-8.0 * delta)
	follow = lerp_angle(0.0, 1.0, follow)

	match _cam_mode:
		CAM_CLOSE:
			# tight chase cam
			var basis := Basis(Vector3.UP, _cam_yaw)
			desired = cpos + basis * Vector3(0.0, 2.10 + k * 0.30, 5.35 + k * 1.15)
			look_target = cpos + Vector3(0, 1.15, 0) + (-basis.z) * (2.0 + spd * 0.06)
			fov_target = 70.0 + k * 8.0
			smooth = 13.0
		CAM_SPEED:
			# the faster you go, the further back the camera sits and the wider
			# the lens gets: strong sense of speed
			var basis := Basis(Vector3.UP, _cam_yaw)
			desired = cpos + basis * Vector3(0.0, 3.0 + k * 1.9, 9.2 + k * 7.6)
			look_target = cpos + Vector3(0, 1.5, 0) + (-basis.z) * (5.0 + spd * 0.20)
			fov_target = 58.0 + k * 34.0        # 58 deg standing -> 100 deg flat out
			smooth = 7.5
		CAM_CINE:
			# slow drone that drifts around the car
			_cine_t += delta
			var ang := car.global_rotation.y + 2.0 + sin(_cine_t * 0.23) * 1.15
			var rad := 17.5 + sin(_cine_t * 0.17) * 4.0 + k * 5.0
			var hgt := 5.4 + sin(_cine_t * 0.31) * 2.0 + k * 2.0
			desired = cpos + Vector3(sin(ang) * rad, hgt, cos(ang) * rad)
			var fwd := -Basis(Vector3.UP, car.global_rotation.y).z
			look_target = cpos + Vector3(0, 1.5, 0) + fwd * (1.5 + spd * 0.05)
			fov_target = 52.0
			smooth = 3.5
			follow = 0.0   # ignore the yaw follow, the orbit owns the angle

	# keep the camera out of walls (not for the drone, it likes the open air)
	if _cam_mode != CAM_CINE:
		var from := cpos + Vector3(0, 1.6, 0)
		var q := PhysicsRayQueryParameters3D.create(from, desired, 1)
		q.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var p: Vector3 = hit["position"]
			desired = p + (desired - p).normalized() * 0.45

	_cam_pos = _cam_pos.lerp(desired, 1.0 - exp(-smooth * delta))
	_look = _look.lerp(look_target, 1.0 - exp(-(smooth + 4.0) * delta))

	var shake := Vector3.ZERO
	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 2.2)
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35
	cam.global_position = _cam_pos + shake
	if (_look - cam.global_position).length_squared() > 0.01:
		cam.look_at(_look + shake * 0.5, Vector3.UP)
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-3.5 * delta))

func _update_walk_camera(delta: float) -> void:
	# sniper scope: first person, zoomed right in, body hidden
	if combat != null and combat.is_scoped() and not on_foot_is_false():
		var eye := walker.eye_position()
		var dir: Vector3 = -cam.global_transform.basis.z
		dir = walker.eye_forward()
		walker.set_model_visible(false)
		_cam_pos = eye + dir * 0.12
		_look = eye + dir * 60.0
		cam.global_position = _cam_pos
		cam.look_at(_look, Vector3.UP)
		cam.fov = lerpf(cam.fov, float(combat.def()["zoom"]), 1.0 - exp(-18.0 * delta))
		return
	walker.set_model_visible(true)

	var goal: Array = walker.camera_goal()
	var want: Vector3 = goal[0]
	var look: Vector3 = goal[1]
	var shake := Vector3.ZERO
	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 2.2)
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.3
	_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-18.0 * delta))
	_look = _look.lerp(look, 1.0 - exp(-22.0 * delta))
	cam.global_position = _cam_pos + shake
	if (_look - cam.global_position).length_squared() > 0.01:
		cam.look_at(_look + shake * 0.4, Vector3.UP)
	var fov_target := 76.0 if walker.sprinting else 72.0
	if combat != null and combat.ads:
		fov_target = float(combat.def()["zoom"]) + 6.0
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-9.0 * delta))

func on_foot_is_false() -> bool:
	return not on_foot

func _cycle_camera() -> void:
	if on_foot:
		walker.cam_zoom = 1.0 if walker.cam_zoom > 1.2 else 1.55
		hud.toast("WALK CAM", 1.1)
		return
	_cam_mode = (_cam_mode + 1) % 3
	_cine_t = 0.0
	hud.toast(CAM_NAMES[_cam_mode], 1.3)

func _on_crash(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength / 30.0, 0.15, 1.0))

func _adaptive_quality(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	if fps > 1:
		_fps_avg = lerpf(_fps_avg, float(fps), 0.08)
	_adapt_cd -= delta
	if _adapt_cd > 0.0:
		return
	pass
