class_name CityWorld
extends Node3D

## The island.  One procedural height field (see Island), eighteen towns that
## are each their own little street grid (see RoadNet), winding roads between
## them, a sea full of coastline, and every house you can walk into.
##
## Streaming: a town is built when you get within CITY_ON metres of it and freed
## again past CITY_OFF.  Inside a town the blocks are queued nearest first and
## built a couple per frame, so driving into a new town never hitches.

signal barrel_exploded(pos: Vector3, radius: float, power: float)

const KIND_INDUSTRIAL := 0
const KIND_TOWN := 1
const KIND_NEON := 2
const KIND_RURAL := 3
const KIND_NATURE := 4

const CITY_ON := 950.0
const CITY_OFF := 1400.0
const BUILD_BUDGET_US := 7000

var island: Island
var roads: RoadNet
var nature: NatureScatter
var cars: Array = []                ## every drivable car in the world
var player: Node3D = null
var seed_value := 20261101

var _chunks: Dictionary = {}        ## key -> Node3D
var _queue: Array = []              ## [[ci, bx, bz], ...]
var _queue_head := 0
var _active_cities: Dictionary = {} ## ci -> true
var _far: Dictionary = {}            ## ci -> MeshInstance3D skyline stand-in
var _plates: Dictionary = {}        ## ci -> Node3D (asphalt / markings)
var _chunk_barrels: Dictionary = {}
var _fuses: Array = []
var _center_city := -99

func _ready() -> void:
	name = "CityWorld"
	island = Island.new(seed_value)
	roads = RoadNet.new()
	roads.generate(island, seed_value % 100000)
	# flatten the towns and the roads into the height field before baking it
	var plateaus: Array = []
	for c in roads.cities:
		plateaus.append({"c": c["c"], "r": float(c["r"]), "h": float(c["h"])})
	island.bake(plateaus, roads.flatten_points())
	_resample_roads()
	# The raw height field gives 50 degree mountain roads and buries the tarmac
	# under the terrain on every crest.  Smooth the profile into a drivable road,
	# then cut/fill the corridor under it.
	_smooth_road_profile()
	_carve_road_corridor()
	_build_terrain()
	_build_water()
	var river := island.build_river_mesh()
	if river != null:
		add_child(river)
	_build_road_meshes()
	_build_city_plates()
	_spawn_cars()
	# ground cover: pines, boulders and shrubs, streamed around the player
	nature = NatureScatter.new()
	add_child(nature)
	nature.setup(island, roads, self)

## Roads are built on the smooth profile from _smooth_road_profile(), so the
## tarmac no longer matches the raw height field.  This pass cuts and fills the
## ground under every road: inside the strip the terrain is levelled 30 cm below
## the tarmac, and it blends back to the natural hill over the next ~15 metres.
## Result: no grass pokes through a road, no car climbs an invisible bump, and a
## mountain road sits in a real cut instead of floating in the air.
const ROAD_CLEAR := 0.30      ## ground sits this far under the tarmac
const ROAD_CORRIDOR := 9.6    ## half width of the strip that must stay clear
const ROAD_RAMP := 24.0       ## blend reaches back to the hill over this distance

func _carve_road_corridor() -> void:
	var res := Island.RES
	var size := island.size
	var half := Island.HALF
	var reach := int(ceil(ROAD_RAMP / res))
	var heights := island.heights
	var count := size * size
	var best_d := PackedFloat32Array()
	best_d.resize(count)
	best_d.fill(1.0e9)
	var best_y := PackedFloat32Array()
	best_y.resize(count)
	# 1. nearest road sample per grid vertex
	for s in roads.samples:
		var p: Vector3 = s
		var ci := int(floor((p.x + half) / res))
		var cj := int(floor((p.z + half) / res))
		for dj in range(-reach, reach + 1):
			var j := cj + dj
			if j < 0 or j >= size:
				continue
			var z := -half + float(j) * res
			var dz := z - p.z
			for di in range(-reach, reach + 1):
				var i := ci + di
				if i < 0 or i >= size:
					continue
				var x := -half + float(i) * res
				var dx := x - p.x
				var d := sqrt(dx * dx + dz * dz)
				if d > ROAD_RAMP:
					continue
				var idx := j * size + i
				if d < best_d[idx]:
					best_d[idx] = d
					best_y[idx] = p.y
	# 2. cut / fill toward the road bed
	var touched := 0
	for idx in count:
		var d := best_d[idx]
		if d > ROAD_RAMP:
			continue
		var road_y := best_y[idx]
		var shelf := road_y - ROAD_CLEAR
		var b := 1.0 - smoothstep(7.6, ROAD_RAMP, d)
		var h: float = lerpf(heights[idx], shelf, b)
		if d < ROAD_CORRIDOR:
			h = minf(h, road_y - ROAD_CLEAR + 0.04)
		heights[idx] = h
		touched += 1
	island.heights = heights
	print("road corridor: %d grid vertices levelled" % touched)

## Mountain roads used to follow the raw height field, which means a road could
## climb 25 m in 20 m (a 50 degree ramp the car simply cannot drive) and the
## terrain bulged through the tarmac on every crest.  This smooths the vertical
## profile of every link and caps the grade at 12%, which is what real mountain
## roads are built to.
const ROAD_MAX_GRADE := 0.12

func _smooth_road_profile() -> void:
	for li in roads.links.size():
		var pts: Array = roads.links[li]
		var n := pts.size()
		if n < 3:
			continue
		var ys := PackedFloat32Array()
		ys.resize(n)
		for i in n:
			ys[i] = (pts[i] as Vector3).y
		# three passes of a 1-2-1 blur, then a hard grade cap in both directions
		for pass_i in 3:
			var out := ys.duplicate()
			for i in range(1, n - 1):
				out[i] = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25
			ys = out
		for i in range(1, n):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var run: float = Vector2(b.x - a.x, b.z - a.z).length()
			var lim := maxf(0.40, run * ROAD_MAX_GRADE)
			ys[i] = clampf(ys[i], ys[i - 1] - lim, ys[i - 1] + lim)
		for i in range(n - 2, -1, -1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var run: float = Vector2(b.x - a.x, b.z - a.z).length()
			var lim := maxf(0.40, run * ROAD_MAX_GRADE)
			ys[i] = clampf(ys[i], ys[i + 1] - lim, ys[i + 1] + lim)
		for i in n:
			var p: Vector3 = pts[i]
			pts[i] = Vector3(p.x, ys[i], p.z)
		roads.links[li] = pts
	roads._sample_roads()
	roads._index_roads()

## The road ribbons were sampled from the *raw* height field; the terrain mesh is
## built from the baked one, so on a crest the grass could poke through the
## asphalt.  Re-reading every road point from the baked field makes the ribbon and
## the mesh agree exactly, which is what keeps the grass off the roads.
func _resample_roads() -> void:
	for li in roads.links.size():
		var pts: Array = roads.links[li]
		for i in pts.size():
			var p: Vector3 = pts[i]
			pts[i] = Vector3(p.x, island.height(p.x, p.z), p.z)
		roads.links[li] = pts
	for i in roads.samples.size():
		var p: Vector3 = roads.samples[i]
		roads.samples[i] = Vector3(p.x, island.height(p.x, p.z), p.z)

# ------------------------------------------------------------------ terrain

func _build_terrain() -> void:
	var mesh := island.build_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = island.size
	hm.map_depth = island.size
	hm.map_data = island.heights
	cs.shape = hm
	cs.scale = Vector3(Island.RES, 1.0, Island.RES)
	body.add_child(cs)
	add_child(body)

func _build_water() -> void:
	var b := MeshBatch.new()
	var w := Island.HALF * 3.2
	b.plate(MeshBatch.SOLID, Vector3(0, Island.SEA - 0.35, 0), Vector2(w, w), Color("2f7fa8"))
	b.plate(MeshBatch.SOLID, Vector3(0, Island.SEA - 1.4, 0), Vector2(w, w), Color("2b6f96"))
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.0
	add_child(mi)

# ------------------------------------------------------------------ roads

func _build_road_meshes() -> void:
	var b := MeshBatch.new()
	var line := MeshBatch.new()
	var asphalt := Color("33373d")
	var shoulder := Color("8a8272")
	for link in roads.links:
		var pts: Array = link
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var dir := c - a
			dir.y = 0.0
			if dir.length() < 0.01:
				continue
			dir = dir.normalized()
			var perp := Vector3(-dir.z, 0.0, dir.x)
			var ha := a + Vector3(0, 0.10, 0)
			var hc := c + Vector3(0, 0.10, 0)
			# asphalt
			_quad(b, ha - perp * 7.4, ha + perp * 7.4, hc + perp * 7.4, hc - perp * 7.4, asphalt)
			# gravel shoulders
			_quad(b, ha - perp * 9.4, ha - perp * 7.4, hc - perp * 7.4, hc - perp * 9.4, shoulder)
			_quad(b, ha + perp * 7.4, ha + perp * 9.4, hc + perp * 9.4, hc + perp * 7.4, shoulder)
			# centre dashes + edge lines
			var seg := a.distance_to(c)
			var acc := float(i) * 0.37
			if fmod(acc, 14.0) < 7.0:
				_quad(line, ha - perp * 0.22 + Vector3(0, 0.05, 0), ha + perp * 0.22 + Vector3(0, 0.05, 0),
					hc + perp * 0.22 + Vector3(0, 0.05, 0), hc - perp * 0.22 + Vector3(0, 0.05, 0),
					CityConfig.C_LINE_Y)
			for s in [-1.0, 1.0]:
				var o: Vector3 = perp * (7.0 * s) + Vector3(0, 0.05, 0)
				_quad(line, ha + o - perp * 0.16 * s, ha + o + perp * 0.16 * s,
					hc + o + perp * 0.16 * s, hc + o - perp * 0.16 * s, CityConfig.C_LINE)
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Same story for the country roads: the asphalt is 10 cm above the terrain,
	# so the strip gets a thin trimesh collider built from the very same points.
	# Without it a car on a mountain road is 10 cm under the tarmac.
	var faces := PackedVector3Array()
	for link in roads.links:
		var pts: Array = link
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var dir := c - a
			dir.y = 0.0
			if dir.length() < 0.01:
				continue
			dir = dir.normalized()
			var perp := Vector3(-dir.z, 0.0, dir.x)
			var ha := a + Vector3(0, 0.10, 0)
			var hc := c + Vector3(0, 0.10, 0)
			var l0 := ha - perp * 7.4
			var r0 := ha + perp * 7.4
			var l1 := hc - perp * 7.4
			var r1 := hc + perp * 7.4
			faces.append_array([l0, r0, r1, l0, r1, l1])
	if faces.size() >= 3:
		var rbody := StaticBody3D.new()
		rbody.name = "RoadBody"
		rbody.collision_layer = 1
		rbody.collision_mask = 0
		var rcs := CollisionShape3D.new()
		var rm := ConcavePolygonShape3D.new()
		rm.set_faces(faces)
		rm.backface_collision = false
		rcs.shape = rm
		rbody.add_child(rcs)
		add_child(rbody)
	var li := MeshInstance3D.new()
	li.name = "RoadMarks"
	li.mesh = line.commit()
	li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(li)

func _quad(b: MeshBatch, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	b.quad(MeshBatch.SOLID, p0, p1, p2, p3, col, Vector3.UP)

# ------------------------------------------------------------------ cities

## The asphalt of every town: one plate right under the block grid, so the
## streets between the blocks are real road and the blocks paint their own
## pavements on top of it.
func _build_city_plates() -> void:
	for ci in roads.cities.size():
		var c: Dictionary = roads.cities[ci]
		var n := float(c["blocks"])
		var size := n * CityConfig.CELL + CityConfig.ROAD + 10.0
		var b := MeshBatch.new()
		var centre := Vector3(float(c["c"].x), float(c["h"]) + 0.06, float(c["c"].y))
		b.plate(MeshBatch.SOLID, centre, Vector2(size, size), CityConfig.C_ASPHALT)
		# a kerb ring around the whole town so it does not just float on grass
		b.plate(MeshBatch.SOLID, centre + Vector3(0, -0.02, 0),
			Vector2(size + 8.0, size + 8.0), CityConfig.C_SIDEWALK_D)
		var mi := MeshInstance3D.new()
		mi.name = "CityPlate_%d" % ci
		mi.mesh = b.commit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_plates[ci] = mi
		# the asphalt is drawn 6 cm above the height field, so it needs its own
		# collider: otherwise every car and every pair of shoes stands 6 cm
		# *inside* the road, which reads as sinking into the ground
		var body := StaticBody3D.new()
		body.name = "CityPlateBody_%d" % ci
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size, 1.2, size)
		cs.shape = shape
		cs.position = centre + Vector3(0, -0.6, 0)
		body.add_child(cs)
		add_child(body)
	_build_far_skylines()

## A cheap silhouette of every town.  While a town is streamed out (you are far
## away) you still see it from the air / from the far side of the island instead
## of an empty asphalt plate.
func _build_far_skylines() -> void:
	for ci in roads.cities.size():
		var c: Dictionary = roads.cities[ci]
		var n := int(c["blocks"])
		var base := float(c["h"])
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (ci + 1)
		var b := MeshBatch.new()
		var walls := [CityConfig.C_WALL_A, CityConfig.C_WALL_B, CityConfig.C_WALL_C,
			CityConfig.C_WALL_D, CityConfig.C_WALL_E, CityConfig.C_STONE, CityConfig.C_IND_WALL,
			CityConfig.C_BRICK, CityConfig.C_CONCRETE, CityConfig.C_SHED_BLUE,
			CityConfig.C_IND_WALL_D, CityConfig.C_STONE_D]
		var kind := int(c["kind"])
		var hmax := 24.0
		if kind == KIND_NEON:
			hmax = 46.0
		elif kind == KIND_NATURE:
			hmax = 8.0
		elif kind == KIND_RURAL:
			hmax = 12.0
		elif kind == KIND_INDUSTRIAL:
			hmax = 18.0
		for bx in n:
			for bz in n:
				var bc: Vector3 = roads.block_center(ci, bx, bz)
				var town_centre := Vector2(bc.x - float(c["c"].x), bc.z - float(c["c"].y)).length()
				var core := clampf(1.0 - town_centre / (float(n) * CityConfig.CELL * 0.7), 0.0, 1.0)
				# pavement plate so the street grid reads from the air
				b.plate(MeshBatch.SOLID, Vector3(bc.x, base + 0.14, bc.z),
					Vector2(CityConfig.BLOCK, CityConfig.BLOCK), CityConfig.C_SIDEWALK_D)
				var count := rng.randi_range(2, 4)
				for k in count:
					var w := rng.randf_range(13.0, 25.0)
					var d := rng.randf_range(13.0, 25.0)
					var h := rng.randf_range(5.0, 11.0) + core * rng.randf_range(4.0, hmax)
					var ox := rng.randf_range(-14.0, 14.0)
					var oz := rng.randf_range(-14.0, 14.0)
					var col: Color = walls[rng.randi_range(0, walls.size() - 1)]
					b.box(MeshBatch.SOLID, Vector3(bc.x + ox, base + h * 0.5, bc.z + oz),
						Vector3(w, h, d), col, col.darkened(0.22))
		if b.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "FarSkyline_%d" % ci
		mi.mesh = b.commit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_far[ci] = mi

func _far_visible(ci: int, on: bool) -> void:
	if _far.has(ci):
		(_far[ci] as MeshInstance3D).visible = on

# ------------------------------------------------------------------ streaming

## True when a point is inside (or just outside) any town footprint.
func near_town(p: Vector3, pad: float = 24.0) -> bool:
	if roads == null:
		return false
	for c in roads.cities:
		var cc: Vector2 = c["c"]
		var r: float = float(c["r"]) + pad
		if Vector2(p.x - cc.x, p.z - cc.y).length_squared() < r * r:
			return true
	return false

func set_player(p: Node3D) -> void:
	player = p
	if nature != null:
		nature.set_player(p)
	_center_city = -99

func _process(delta: float) -> void:
	_process_fuses(delta)
	if player == null:
		return
	var p := player.global_position
	for ci in roads.cities.size():
		var c: Dictionary = roads.cities[ci]
		var d := Vector2(p.x, p.z).distance_to(c["c"])
		if d < CITY_ON and not _active_cities.has(ci):
			_activate(ci, p)
		elif d > CITY_OFF and _active_cities.has(ci):
			_active_cities.erase(ci)
			_free_city(ci)
			_far_visible(ci, true)
	_drain()

func _activate(ci: int, p: Vector3) -> void:
	_active_cities[ci] = true
	_far_visible(ci, false)
	var c: Dictionary = roads.cities[ci]
	var n := int(c["blocks"])
	var list: Array = []
	for bx in n:
		for bz in n:
			var key := _key(ci, bx, bz)
			if _chunks.has(key):
				continue
			var bc := roads.block_center(ci, bx, bz)
			list.append([Vector2(bc.x - p.x, bc.z - p.z).length_squared(), ci, bx, bz])
	list.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for e in list:
		_queue.append(e)

func _key(ci: int, bx: int, bz: int) -> int:
	return ci * 1000 + bx * 32 + bz

func _free_city(ci: int) -> void:
	var kill: Array = []
	for key in _chunks:
		if int(key) / 1000 == ci:
			kill.append(key)
	for k in kill:
		var n: Node = _chunks[k]
		_chunks.erase(k)
		_free_chunk_barrels(k)
		n.queue_free()

func _drain() -> void:
	if _queue_head >= _queue.size():
		return
	var t0 := Time.get_ticks_usec()
	while _queue_head < _queue.size():
		var e: Array = _queue[_queue_head]
		_queue_head += 1
		var key := _key(int(e[1]), int(e[2]), int(e[3]))
		if not _chunks.has(key):
			_build_chunk(int(e[1]), int(e[2]), int(e[3]), key)
		if Time.get_ticks_usec() - t0 > BUILD_BUDGET_US:
			break

func block_center(ci: int, bx: int, bz: int) -> Vector3:
	return roads.block_center(ci, bx, bz)

## What kind of block a town block is: the landmark in the middle, the town
## around it, and open country in any block that is left over.
func block_type(ci: int, bx: int, bz: int) -> int:
	var c: Dictionary = roads.cities[ci]
	var n := int(c["blocks"])
	var mid := (n - 1) / 2
	var h := absi(bx * 73856093) ^ absi(bz * 19349663) ^ int(c["seed"])
	var r := float(absi(h) % 1000) / 1000.0
	var ring := maxi(absi(bx - mid), absi(bz - mid))
	if ring == 0:
		return int(c["landmark"])
	if ring == 1 and r < 0.30:
		return int(c["landmark"])
	return _city_mix(int(c["kind"]), r, ring)

func _city_mix(kind: int, r: float, ring: int) -> int:
	if r < 0.040:
		return CityBuilder.SCHOOL
	if r < 0.075:
		return CityBuilder.POLICE
	if r < 0.105:
		return CityBuilder.HOSPITAL
	if r < 0.145:
		return CityBuilder.CLUB
	match kind:
		KIND_INDUSTRIAL:
			if r < 0.34:
				return CityBuilder.FACTORY if ring == 1 else CityBuilder.WAREHOUSE
			if r < 0.56:
				return CityBuilder.WAREHOUSE
			if r < 0.70:
				return CityBuilder.RESIDENTIAL
			if r < 0.84:
				return CityBuilder.COMMERCIAL
			return CityBuilder.LOT
		KIND_NEON:
			if r < 0.66:
				return CityBuilder.COMMERCIAL
			if r < 0.78:
				return CityBuilder.RESIDENTIAL
			if r < 0.88:
				return CityBuilder.PLAZA
			if r < 0.94:
				return CityBuilder.PARK
			return CityBuilder.COMMERCIAL
		KIND_RURAL:
			if r < 0.58:
				return CityBuilder.RESIDENTIAL
			if r < 0.72:
				return CityBuilder.COMMERCIAL
			if r < 0.84:
				return CityBuilder.PLANTATION
			if r < 0.93:
				return CityBuilder.PARK
			return CityBuilder.RESIDENTIAL
		KIND_NATURE:
			if r < 0.42:
				return CityBuilder.PARK
			if r < 0.58:
				return CityBuilder.RESIDENTIAL
			if r < 0.74:
				return CityBuilder.PLANTATION
			if r < 0.88:
				return CityBuilder.LOT
			return CityBuilder.PEAK
	if r < 0.58:
		return CityBuilder.RESIDENTIAL
	if r < 0.70:
		return CityBuilder.COMMERCIAL
	if r < 0.78:
		return CityBuilder.PARK
	if r < 0.88:
		return CityBuilder.PLAZA
	if r < 0.94:
		return CityBuilder.LOT
	return CityBuilder.RESIDENTIAL

func _build_chunk(ci: int, bx: int, bz: int, key: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = key * 2654435761
	var b := MeshBatch.new()
	var cols: Array = []
	var o := roads.block_center(ci, bx, bz)
	CityBuilder.build(b, block_type(ci, bx, bz), rng, o, cols)

	var node := Node3D.new()
	node.name = "Block_%d_%d_%d" % [ci, bx, bz]
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mi)
	if not cols.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for a in cols:
			var cs := CollisionShape3D.new()
			if a is AABB:
				var ab: AABB = a
				var shape := BoxShape3D.new()
				shape.size = ab.size
				cs.shape = shape
				cs.position = ab.get_center()
			elif a is Dictionary and (a as Dictionary).has("ramp"):
				var rd: Dictionary = a
				var rshape := BoxShape3D.new()
				rshape.size = rd["size"]
				cs.shape = rshape
				cs.position = rd["pos"]
				cs.rotation = rd["rot"]
			else:
				continue
			body.add_child(cs)
		node.add_child(body)
	add_child(node)
	_chunks[key] = node
	_spawn_chunk_barrels(ci, bx, bz, key, node)
	_spawn_chunk_loot(ci, bx, bz, key, node, rng)

## Every house and every shop keeps a few random pickups on its floor: guns and
## ammo, body vests, helmets, grenades, gloo walls and medkits.
const LOOT_TABLE := ["gun", "gun", "vest", "helmet", "grenade", "gloo", "medkit", "medkit"]
## Every house on the island keeps loot: each of its four floor spots is used
## almost every time, so no house is ever empty.
const LOOT_CHANCE := 0.94
const LOOT_PER_BLOCK := 30

func _spawn_chunk_loot(ci: int, bx: int, bz: int, key: int, node: Node3D,
		rng: RandomNumberGenerator) -> void:
	var spots: Array = []
	for r in HouseBuilder.rooms:
		spots.append(r["pos"])
	for p in CityBuilder._loot_spots:
		spots.append(p)
	if spots.is_empty():
		return
	var made := 0
	for p in spots:
		var pos: Vector3 = p
		if rng.randf() > LOOT_CHANCE:
			continue
		var kind: String = LOOT_TABLE[rng.randi_range(0, LOOT_TABLE.size() - 1)]
		var item := LootItem.make(kind, rng)
		var jitter := Vector3(rng.randf_range(-0.55, 0.55), 0.0, rng.randf_range(-0.55, 0.55))
		item.position = pos + jitter
		node.add_child(item)
		made += 1
		if made >= LOOT_PER_BLOCK:
			break

func chunk_count() -> int:
	return _chunks.size()

func pending_count() -> int:
	return maxi(0, _queue.size() - _queue_head)

func set_view_radius(r: int) -> void:
	pass

func view_radius() -> int:
	return 4

# ------------------------------------------------------------------ naming

func area_name(pos: Vector3) -> String:
	return roads.city_name_at(pos)

func map_cities() -> Array:
	var out: Array = []
	for i in roads.cities.size():
		var c: Dictionary = roads.cities[i]
		out.append({
			"name": c["name"],
			"pos": Vector3(float(c["c"].x), float(c["h"]), float(c["c"].y)),
			"kind": c["kind"],
			"r": c["r"],
		})
	return out

func city_index_at(pos: Vector3) -> int:
	return roads.city_at_point(pos)

# ------------------------------------------------------------------ spawn

## A good place to start: on the street of a town near the middle of the island.
func spawn_point() -> Dictionary:
	var ci := roads.nearest_city(Vector3.ZERO)
	var c: Dictionary = roads.cities[ci]
	var n := float(c["blocks"])
	var centre: Vector2 = c["c"]
	var y: float = float(c["h"])
	# stand next to one of the cars parked in this town, so you can press F and go
	var best: Dictionary = {}
	var bd := 1e30
	for spot in roads.street_cars:
		if int(spot["city"]) != ci:
			continue
		var sp: Vector3 = spot["pos"]
		var d := Vector2(sp.x - centre.x, sp.z - centre.y).length_squared()
		if d < bd:
			bd = d
			best = spot
	if not best.is_empty():
		var p: Vector3 = best["pos"]
		var yaw: float = float(best["yaw"])
		var side := Vector3(cos(yaw), 0.0, -sin(yaw)) * 2.4
		return {
			"pos": p + side + Vector3(0, 0.2, 0),
			"yaw": yaw,
			"city": ci,
			"walk": p + side,
		}
	# fallback: middle of the street on the south side of the town
	var off := CityConfig.CELL * 0.5
	return {
		"pos": Vector3(centre.x + CityConfig.LANE, y + 0.6, centre.y + off),
		"yaw": 0.0,
		"city": ci,
		"walk": Vector3(centre.x - 2.6, y + 0.4, centre.y + off),
	}

# ------------------------------------------------------------------ cars

## Bright show-room colours: nothing dark, so no car reads as a black blob.
const CAR_PAINTS := [
	Color("e63b2e"), Color("2f6fa8"), Color("d8b23a"), Color("3f8a4a"),
	Color("e8ecef"), Color("c8752a"), Color("8a49c8"), Color("1fa8a0"),
	Color("d94f8a"), Color("f0f2f4"),
]

## What kind of vehicle a spot gets: town streets are full of ordinary cars and
## the odd bike, the open road gets pickups and 4x4s, the high mountain roads get
## jeeps and the occasional monster truck.
const KINDS_TOWN := ["sedan", "sedan", "sedan", "sports", "van", "pickup", "suv", "bike", "bike"]
const KINDS_OPEN := ["suv", "pickup", "jeep", "sedan", "van", "bike", "sports", "suv"]
const KINDS_HIGH := ["jeep", "jeep", "monster", "pickup", "bike"]

func _kind_for(spot: Dictionary, gy: float) -> String:
	if gy > 115.0:
		return KINDS_HIGH[absi(int(spot["pos"].x) + int(spot["pos"].z) * 7) % KINDS_HIGH.size()]
	if int(spot["city"]) < 0:
		return KINDS_OPEN[absi(int(spot["pos"].x) / 3 + int(spot["pos"].z)) % KINDS_OPEN.size()]
	return KINDS_TOWN[absi(int(spot["pos"].x) + int(spot["pos"].z) * 3) % KINDS_TOWN.size()]

func _spawn_cars() -> void:
	for spot in roads.street_cars:
		var pos: Vector3 = spot["pos"]
		# sit the vehicle on the ground
		var gy: float = island.height(pos.x, pos.z)
		pos.y = gy + 0.45
		var car := PlayerCar.new()
		car.kind = _kind_for(spot, gy)
		car.island = island
		car.position = pos
		car.rotation = Vector3(0, float(spot["yaw"]), 0)
		var tint: Color = CAR_PAINTS[int(spot["city"]) % CAR_PAINTS.size()]
		if int(spot["city"]) < 0:
			tint = CAR_PAINTS[(int(spot["pos"].x) + int(spot["pos"].z) + 4096) % CAR_PAINTS.size()]
		car.paint = tint
		add_child(car)
		car.set_physics_process(false)
		car.sit_on_ground(gy)
		cars.append(car)

func nearest_car(p: Vector3, max_d: float = 6.0) -> PlayerCar:
	var best: PlayerCar = null
	var bd := max_d * max_d
	for c in cars:
		var car: PlayerCar = c
		if not is_instance_valid(car):
			continue
		var d: float = car.global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = car
	return best

# ------------------------------------------------------------------ barrels

const BARREL_CHANCE := 0.55
const BARREL_BLAST := 7.0
const BARREL_DAMAGE := 6.5

func _spawn_chunk_barrels(ci: int, bx: int, bz: int, key: int, node: Node3D) -> void:
	var type := block_type(ci, bx, bz)
	var rng := RandomNumberGenerator.new()
	rng.seed = key * 7717 + 13
	var want := 0
	if type == CityBuilder.COUNTRYSIDE or type == CityBuilder.PARK or type == CityBuilder.OBSERVATORY:
		want = 0
	elif type == CityBuilder.FACTORY or type == CityBuilder.WAREHOUSE or type == CityBuilder.SHIPYARD \
			or type == CityBuilder.MARSELECTRIC or type == CityBuilder.MILL:
		want = rng.randi_range(2, 4)
	else:
		want = rng.randi_range(0, 2)
	if want <= 0 or rng.randf() > BARREL_CHANCE + 0.3:
		return
	var o := roads.block_center(ci, bx, bz)
	var made: Array = []
	var side := rng.randi_range(0, 3)
	var half := CityConfig.BLOCK * 0.5 - 2.6
	var anchor: Vector3
	match side:
		0: anchor = o + Vector3(rng.randf_range(-half * 0.6, half * 0.6), 0.06, -half)
		1: anchor = o + Vector3(rng.randf_range(-half * 0.6, half * 0.6), 0.06, half)
		2: anchor = o + Vector3(-half, 0.06, rng.randf_range(-half * 0.6, half * 0.6))
		_: anchor = o + Vector3(half, 0.06, rng.randf_range(-half * 0.6, half * 0.6))
	for i in want:
		var off := Vector3(rng.randf_range(-1.05, 1.05), 0.0, rng.randf_range(-1.05, 1.05)) if i > 0 else Vector3.ZERO
		var b := ExplosiveBarrel.create(anchor + off, rng.randf() < 0.22)
		node.add_child(b)
		made.append(b)
	_chunk_barrels[key] = made

func _free_chunk_barrels(key: int) -> void:
	_chunk_barrels.erase(key)

func prune_barrel(br: Node) -> void:
	for k in _chunk_barrels.keys():
		var arr: Array = _chunk_barrels[k]
		for i in range(arr.size() - 1, -1, -1):
			var x = arr[i]
			if not is_instance_valid(x) or x == br:
				arr.remove_at(i)

func barrel_count() -> int:
	var t := 0
	for k in _chunk_barrels:
		t += (_chunk_barrels[k] as Array).size()
	return t

func nearest_barrel(p: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 1.0e18
	for k in _chunk_barrels:
		for b in _chunk_barrels[k]:
			if not is_instance_valid(b):
				continue
			var br: ExplosiveBarrel = b
			if not br.alive:
				continue
			var d: float = br.global_position.distance_squared_to(p)
			if d < bd:
				bd = d
				best = br
	return best

func punch_barrels(origin: Vector3, dir: Vector3, reach: float, power: float) -> int:
	var hit := 0
	for k in _chunk_barrels.keys():
		for b in _chunk_barrels[k]:
			if not is_instance_valid(b):
				continue
			var br: ExplosiveBarrel = b
			if not br.alive:
				continue
			var d: Vector3 = br.world_pos() - origin
			if d.length() > reach:
				continue
			if d.normalized().dot(dir.normalized()) < 0.15:
				continue
			_detonate(br, power)
			hit += 1
			break
	return hit

func ram_barrels(pos: Vector3, radius: float, power: float) -> int:
	var hit := 0
	for k in _chunk_barrels.keys():
		for b in _chunk_barrels[k]:
			if not is_instance_valid(b):
				continue
			var br: ExplosiveBarrel = b
			if not br.alive:
				continue
			var wp := br.world_pos()
			if Vector2(wp.x - pos.x, wp.z - pos.z).length() < radius:
				_detonate(br, power)
				hit += 1
	return hit

## Public: shoot a drum and it goes up.
func detonate_barrel(br: ExplosiveBarrel, power: float = 1.1) -> void:
	_detonate(br, power)

func _detonate(br: ExplosiveBarrel, power: float) -> void:
	if not is_instance_valid(br) or not br.alive:
		return
	br.alive = false
	var wp := br.world_pos()
	ExplosionFX.spawn(self, Vector3(wp.x, wp.y - 0.4, wp.z), power)
	prune_barrel(br)
	br.queue_free()
	barrel_exploded.emit(wp, BARREL_DAMAGE, power)
	for k in _chunk_barrels.keys():
		for b in _chunk_barrels[k]:
			if not is_instance_valid(b):
				continue
			var n: ExplosiveBarrel = b
			if not n.alive:
				continue
			var np := n.world_pos()
			if Vector2(np.x - wp.x, np.z - wp.z).length() < BARREL_BLAST:
				var queued := false
				for f in _fuses:
					if f["b"] == n:
						queued = true
				if not queued:
					_fuses.append({"b": n, "t": randf_range(0.10, 0.26), "p": power * 0.9})

func _process_fuses(delta: float) -> void:
	if _fuses.is_empty():
		return
	var keep: Array = []
	for f in _fuses:
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) <= 0.0:
			_detonate(f["b"], float(f["p"]))
		else:
			keep.append(f)
	_fuses = keep
