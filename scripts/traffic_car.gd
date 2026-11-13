class_name TrafficCar
extends AnimatableBody3D

## One AI car.  It follows lane waypoints between intersections, turns at
## random, obeys the traffic lights, brakes for the car in front (and for the
## player) and never leaves the road network.

enum { APPROACH, CROSS }

const DIRS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const LEFT := [3, 2, 0, 1]
const RIGHT := [2, 3, 1, 0]

var heading := 0
var next_ip := Vector2i.ZERO
var phase := APPROACH
var new_heading := 0
var speed := 0.0
var max_speed := 13.0
var color := Color.WHITE
var manager: Node = null

var _target := Vector3.ZERO
var _yaw := 0.0
var _spin := 0.0
var _wheels: Array = []
var _model: Node3D
var _brake := false

static func dir_of(h: int) -> Vector3:
	return DIRS[h]

static func axis_of(h: int) -> int:
	return 0 if h < 2 else 1

func setup(mgr: Node, col: Color, h: int, ip: Vector2i, start: Vector3) -> void:
	manager = mgr
	color = col
	heading = h
	next_ip = ip
	phase = APPROACH
	position = start
	_yaw = _yaw_for(dir_of(h))
	max_speed = randf_range(10.5, 15.0)
	speed = max_speed * 0.6
	_compute_target()
	rotation = Vector3(0, _yaw, 0)

func _ready() -> void:
	name = "TrafficCar"
	# spawned (not teleported) cars must not slide in from their old transform
	reset_physics_interpolation()
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.3, 4.2)
	cs.shape = shape
	cs.position = Vector3(0, 0.68, 0)
	add_child(cs)
	var model := CarModel.build(color, "sedan", false, false)
	_model = model.root
	_wheels = model.wheels
	add_child(_model)

func _yaw_for(d: Vector3) -> float:
	return atan2(-d.x, -d.z)

func _compute_target() -> void:
	var ic := CityConfig.intersection_center(next_ip.x, next_ip.y)
	if phase == APPROACH:
		var d := dir_of(heading)
		_target = ic - d * (CityConfig.HALF_ROAD + 2.5) + CityConfig.right_of(d) * CityConfig.LANE
	else:
		var d2 := dir_of(new_heading)
		_target = ic + d2 * (CityConfig.HALF_ROAD + 2.5) + CityConfig.right_of(d2) * CityConfig.LANE

func _physics_process(dt: float) -> void:
	_compute_target()
	var to_t := _target - global_position
	to_t.y = 0.0
	var dist := to_t.length()
	var desired := max_speed

	# ---- traffic light
	if phase == APPROACH:
		var st := TrafficManager.axis_state(axis_of(heading))
		if st != 0 and dist < 26.0:
			var stop_gap := 2.0 if st == 2 else 0.0
			if dist > stop_gap:
				desired = minf(desired, maxf(0.0, (dist - stop_gap) * 0.85))
			elif st == 2:
				desired = 0.0
	# ---- car / player ahead
	if manager != null:
		var gap: float = manager.gap_ahead(self)
		if gap < 24.0:
			desired = minf(desired, maxf(0.0, (gap - 5.0) * 0.8))
	_brake = desired < speed - 0.5
	speed = move_toward(speed, desired, 10.0 * dt)

	# ---- advance along the lane
	if dist > 0.02:
		var dirv := to_t / dist
		var step := minf(speed * dt, dist)
		global_position += dirv * step
		var want := _yaw_for(dirv)
		_yaw = lerp_angle(_yaw, want, 1.0 - exp(-9.0 * dt))
		rotation = Vector3(0, _yaw, 0)
	if dist < 0.7:
		if phase == APPROACH:
			var st2 := TrafficManager.axis_state(axis_of(heading))
			if st2 == 0 or dist < 0.2:
				# pick a turn (or straight on) that stays inside the grid
				new_heading = _choose_heading()
				phase = CROSS
				_compute_target()
			else:
				speed = 0.0
		else:
			heading = new_heading
			var d := dir_of(heading)
			var step_ip := Vector2i(int(round(d.x)), int(round(d.z)))
			next_ip += step_ip
			next_ip.x = clampi(next_ip.x, 0, CityConfig.GRID)
			next_ip.y = clampi(next_ip.y, 0, CityConfig.GRID)
			phase = APPROACH
			_compute_target()

	_spin += (speed / 0.35) * dt
	for entry in _wheels:
		var w: Node3D = entry[0]
		w.rotation.x = _spin
		w.rotation.y = 0.0

func _valid(h: int) -> bool:
	var d := dir_of(h)
	var ip := next_ip + Vector2i(int(round(d.x)), int(round(d.z)))
	return ip.x >= 0 and ip.y >= 0 and ip.x <= CityConfig.GRID and ip.y <= CityConfig.GRID

func _choose_heading() -> int:
	var options: Array = []
	var weights: Array = []
	if _valid(heading):
		options.append(heading)
		weights.append(5)
	var l: int = LEFT[heading]
	if _valid(l):
		options.append(l)
		weights.append(3)
	var r: int = RIGHT[heading]
	if _valid(r):
		options.append(r)
		weights.append(3)
	if options.is_empty():
		# dead end (map edge): reverse is the only option
		return (heading + 1) % 4 if _valid((heading + 1) % 4) else (heading + 2) % 4
	var total := 0
	for w in weights:
		total += w
	var pick := randi_range(0, total - 1)
	for i in options.size():
		pick -= weights[i]
		if pick < 0:
			return options[i]
	return options[0]

## Called by the manager when the player crashes into us.
func bump() -> void:
	speed = 0.0
