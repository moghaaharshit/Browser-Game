class_name TrafficManager
extends Node3D

## Owns everything traffic related:
##  * the global signal cycle (both axes of the grid),
##  * the visible traffic light poles around the player,
##  * the AI cars, streamed in and out around the player.

const CYCLE := 20.0
const X_GREEN := 8.0
const X_YELLOW := 10.0
const Z_GREEN := 18.0
const MAX_CARS := 26
const CAR_MIN_DIST := 70.0
const CAR_MAX_DIST := 300.0
const CAR_DESPAWN := 400.0
const LIGHT_RADIUS := 2

static var _t := 0.0

var player: Node3D = null
var cars: Array = []

var _rng := RandomNumberGenerator.new()
var _lights: Dictionary = {}
var _pole_mesh: ArrayMesh
var _lamp_mesh: SphereMesh
var _lamp_mats: Array = []
var _last_state := [-1, -1]
var _spawn_cd := 0.0
var _light_center := Vector2i(-99999, -99999)
var _car_colors := [
	Color("d9dde1"), Color("22262b"), Color("b8332f"), Color("2b4b8f"), Color("2f7a4a"),
	Color("e8c33a"), Color("e07b2a"), Color("7a4fc0"), Color("3aa3a8"), Color("8d9399"),
	Color("f2f4f7"), Color("455a7a"),
]

## 0 = green, 1 = yellow, 2 = red
static func axis_state(axis: int) -> int:
	if axis == 0:
		if _t < X_GREEN:
			return 0
		if _t < X_YELLOW:
			return 1
		return 2
	if _t < X_YELLOW:
		return 2
	if _t < Z_GREEN:
		return 0
	return 1

func _ready() -> void:
	name = "TrafficManager"
	_rng.seed = 90210
	_build_light_assets()
	_lamp_mats = [
		Mats.emissive(Color("ff2b2b"), 1.6),
		Mats.emissive(Color("ffd23b"), 1.6),
		Mats.emissive(Color("22ff66"), 1.6),
	]

func set_player(p: Node3D) -> void:
	player = p

# ------------------------------------------------------------------ assets

func _build_light_assets() -> void:
	var b := MeshBatch.new()
	# post
	b.box(MeshBatch.SOLID, Vector3(0, 2.8, 0), Vector3(0.3, 5.6, 0.3), CityConfig.C_METAL_D)
	b.box(MeshBatch.SOLID, Vector3(0, 0.15, 0), Vector3(0.7, 0.3, 0.7), CityConfig.C_METAL_D)
	# arm out over the lane (local -Z)
	b.box(MeshBatch.SOLID, Vector3(0, 5.5, -3.0), Vector3(0.2, 0.2, 6.0), CityConfig.C_METAL_D)
	# signal head
	b.box(MeshBatch.SOLID, Vector3(0, 4.6, -5.6), Vector3(0.5, 1.7, 0.55), Color("22252a"))
	# the three unlit lenses
	for i in 3:
		b.box(MeshBatch.SOLID, Vector3(-0.28, 4.6 + 0.5 - float(i) * 0.5, -5.6),
			Vector3(0.08, 0.36, 0.36), Color("111318"))
	_pole_mesh = b.commit()

	_lamp_mesh = SphereMesh.new()
	_lamp_mesh.radius = 0.17
	_lamp_mesh.height = 0.34
	_lamp_mesh.radial_segments = 8
	_lamp_mesh.rings = 4

# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	_t = fmod(_t + delta, CYCLE)
	if player == null:
		return
	_update_light_visuals()
	var c := Vector2i(CityConfig.line_at(player.global_position.x), CityConfig.line_at(player.global_position.z))
	if c != _light_center:
		_light_center = c
		_refresh_lights(c)
		_prune_cars()
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 0.35
		_top_up_cars()

func _update_light_visuals() -> void:
	for axis in 2:
		var st := axis_state(axis)
		if st == _last_state[axis]:
			continue
		_last_state[axis] = st
		for key in _lights:
			var e: Dictionary = _lights[key]
			if int(e["axis"]) != axis:
				continue
			var lamp: MeshInstance3D = e["lamp"]
			lamp.position = Vector3(-0.34, 4.6 + 0.5 - float(st) * 0.5, -5.6)
			lamp.material_override = _lamp_mats[st]

# ------------------------------------------------------------------ lights

func _refresh_lights(center: Vector2i) -> void:
	var want: Dictionary = {}
	for dx in range(-LIGHT_RADIUS, LIGHT_RADIUS + 1):
		for dz in range(-LIGHT_RADIUS, LIGHT_RADIUS + 1):
			var li := center.x + dx
			var lj := center.y + dz
			if li < 0 or lj < 0 or li > CityConfig.GRID or lj > CityConfig.GRID:
				continue
			var key := Vector2i(li, lj)
			want[key] = true
			if not _lights.has(key):
				_make_lights(key)
	for key in _lights.keys():
		if not want.has(key):
			var e: Dictionary = _lights[key]
			(e["node"] as Node).queue_free()
			_lights.erase(key)

func _make_lights(key: Vector2i) -> void:
	var ic := CityConfig.intersection_center(key.x, key.y)
	var root := Node3D.new()
	root.name = "Lights_%d_%d" % [key.x, key.y]
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var pole := Node3D.new()
		pole.position = ic - d * (CityConfig.HALF_ROAD + 1.6) + CityConfig.right_of(d) * (CityConfig.HALF_ROAD + 1.6)
		pole.rotation.y = atan2(-d.z, d.x)
		var mi := MeshInstance3D.new()
		mi.mesh = _pole_mesh
		pole.add_child(mi)
		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var axis := 0 if absf(d.x) > 0.5 else 1
		var st := axis_state(axis)
		lamp.position = Vector3(-0.34, 4.6 + 0.5 - float(st) * 0.5, -5.6)
		lamp.material_override = _lamp_mats[st]
		pole.add_child(lamp)
		root.add_child(pole)
		_lights[key] = {"node": root, "axis": axis, "lamp": lamp, "pole": pole}
	add_child(root)

func _exit_tree() -> void:
	_lights.clear()

# ------------------------------------------------------------------ cars

func gap_ahead(car: TrafficCar) -> float:
	var best := 999.0
	var fwd := TrafficCar.dir_of(car.heading)
	var perp := Vector3(-fwd.z, 0, fwd.x)
	var cp := car.global_position
	for other in cars:
		var o: TrafficCar = other
		if o == car:
			continue
		var delta: Vector3 = o.global_position - cp
		delta.y = 0.0
		var along := delta.dot(fwd)
		if along > 0.6 and along < 30.0 and absf(delta.dot(perp)) < 3.0:
			best = minf(best, along)
	if player != null:
		var pd: Vector3 = player.global_position - cp
		pd.y = 0.0
		var palong := pd.dot(fwd)
		if palong > 0.6 and palong < 30.0 and absf(pd.dot(perp)) < 3.4:
			best = minf(best, palong)
	return best

func _top_up_cars() -> void:
	# fill up quickly at first, then trickle
	var budget := 4 if cars.size() < 10 else 1
	for i in budget:
		if cars.size() >= MAX_CARS:
			return
		if not _spawn_car():
			return

func _spawn_car() -> bool:
	if player == null:
		return false
	for attempt in 16:
		var axis := _rng.randi_range(0, 1)
		var m := _rng.randi_range(0, CityConfig.GRID)
		var k := _rng.randi_range(0, CityConfig.GRID - 1)
		var t := _rng.randf_range(0.2, 0.8)
		var along := CityConfig.road_coord(k) + t * CityConfig.CELL
		var cross := CityConfig.road_coord(m)
		var pos: Vector3
		var h: int
		var ip: Vector2i
		if axis == 0:
			# road running along X, at z = cross
			if _rng.randf() < 0.5:
				h = 0
				pos = Vector3(along, 0.0, cross + CityConfig.LANE)
				ip = Vector2i(k + 1, m)
			else:
				h = 1
				pos = Vector3(along, 0.0, cross - CityConfig.LANE)
				ip = Vector2i(k, m)
		else:
			# road running along Z, at x = cross
			if _rng.randf() < 0.5:
				h = 2
				pos = Vector3(cross - CityConfig.LANE, 0.0, along)
				ip = Vector2i(m, k + 1)
			else:
				h = 3
				pos = Vector3(cross + CityConfig.LANE, 0.0, along)
				ip = Vector2i(m, k)
		var dist := pos.distance_to(player.global_position)
		if dist < CAR_MIN_DIST or dist > CAR_MAX_DIST:
			continue
		var ok := true
		for other in cars:
			if (other as Node3D).global_position.distance_to(pos) < 14.0:
				ok = false
				break
		if not ok:
			continue
		var car := TrafficCar.new()
		car.setup(self, _car_colors[_rng.randi_range(0, _car_colors.size() - 1)], h, ip, pos)
		cars.append(car)
		add_child(car)
		return true
	return false

func _prune_cars() -> void:
	if player == null:
		return
	var keep: Array = []
	for other in cars:
		var car: TrafficCar = other
		if car.global_position.distance_to(player.global_position) > CAR_DESPAWN:
			car.queue_free()
		else:
			keep.append(car)
	cars = keep

func car_count() -> int:
	return cars.size()

func light_count() -> int:
	return _lights.size()
