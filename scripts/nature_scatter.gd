class_name NatureScatter
extends Node3D

## Ground cover for the whole island: pines, boulders and shrubs are scattered
## over the terrain in 40 m tiles that live only while the player is near them.
##
## Nothing here casts per-prop nodes: every tile becomes three MultiMeshes (one
## per prop type), so a whole hillside costs three draw calls.  Placement is
## deterministic per tile, so a tile looks identical every time you drive past
## it, and it is skipped on roads and in towns.

const TILE := 48.0
const RADIUS := 180.0        ## how far ground cover is kept alive around the player
const MAX_TILES := 100
const SPAWN_PER_TILE := 52   ## how many candidates we roll per tile

const C_TRUNK := Color("4a3626")
const C_PINE := Color("1d4423")
const C_PINE2 := Color("2a5c2e")
const C_ROCK := Color("6e6a62")
const C_ROCK2 := Color("8d887e")
const C_BUSH := Color("3c6b2c")
const C_BUSH2 := Color("577f33")

var island: Island
var roads: RoadNet
var world: Node = null
var player: Node3D = null

var _tiles: Dictionary = {}          ## Vector2i -> Node3D
var _want: Dictionary = {}           ## Vector2i -> true (rebuilt each update)
var _queue: Array = []               ## Vector2i waiting to be built
var _head := 0
var _mesh_pine: ArrayMesh
var _mesh_rock: ArrayMesh
var _mesh_bush: ArrayMesh
var _dens := FastNoiseLite.new()
var _dens2 := FastNoiseLite.new()

func setup(p_island: Island, p_roads: RoadNet, p_world: Node) -> void:
	island = p_island
	roads = p_roads
	world = p_world
	name = "Nature"
	_dens.seed = 991
	_dens.frequency = 0.0075
	_dens.fractal_octaves = 3
	_dens2.seed = 4242
	_dens2.frequency = 0.021
	_dens2.fractal_octaves = 2
	_mesh_pine = _build_pine()
	_mesh_rock = _build_rock()
	_mesh_bush = _build_bush()

func set_player(p: Node3D) -> void:
	player = p

# ------------------------------------------------------------------ prop meshes

static func _build_pine() -> ArrayMesh:
	var b := MeshBatch.new()
	b.cylinder(MeshBatch.SOLID, Vector3(0, 0, 0), 0.17, 0.12, 1.9, 6, C_TRUNK)
	b.cylinder(MeshBatch.SOLID, Vector3(0, 1.15, 0), 1.45, 0.0, 1.75, 7, C_PINE)
	b.cylinder(MeshBatch.SOLID, Vector3(0, 2.35, 0), 1.12, 0.0, 1.55, 7, C_PINE2)
	b.cylinder(MeshBatch.SOLID, Vector3(0, 3.35, 0), 0.78, 0.0, 1.35, 7, C_PINE)
	return b.commit()

static func _build_rock() -> ArrayMesh:
	var b := MeshBatch.new()
	b.cylinder(MeshBatch.SOLID, Vector3(0, 0, 0), 0.95, 0.74, 0.70, 6, C_ROCK)
	b.cylinder(MeshBatch.SOLID, Vector3(0, 0.62, 0), 0.72, 0.34, 0.62, 5, C_ROCK2)
	b.box(MeshBatch.SOLID, Vector3(0.42, 0.30, -0.30), Vector3(0.60, 0.52, 0.56), C_ROCK2)
	b.box(MeshBatch.SOLID, Vector3(-0.46, 0.22, 0.34), Vector3(0.50, 0.44, 0.60), C_ROCK)
	return b.commit()

static func _build_bush() -> ArrayMesh:
	var b := MeshBatch.new()
	b.cylinder(MeshBatch.SOLID, Vector3(0, 0, 0), 0.62, 0.44, 0.52, 5, C_BUSH)
	b.cylinder(MeshBatch.SOLID, Vector3(0.34, 0, 0.22), 0.46, 0.30, 0.44, 5, C_BUSH2)
	b.cylinder(MeshBatch.SOLID, Vector3(-0.30, 0, -0.26), 0.40, 0.26, 0.38, 5, C_BUSH)
	return b.commit()

# ------------------------------------------------------------------ streaming

func _process(_dt: float) -> void:
	if island == null or player == null:
		return
	_track(global_position_of_player())
	_drain(3)

func global_position_of_player() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.ZERO
	return player.global_position

func _track(p: Vector3) -> void:
	var cx := int(floor(p.x / TILE))
	var cz := int(floor(p.z / TILE))
	var r := int(ceil(RADIUS / TILE))
	_want.clear()
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := Vector2i(cx + dx, cz + dz)
			var centre := Vector3((float(t.x) + 0.5) * TILE, 0.0, (float(t.y) + 0.5) * TILE)
			var d := Vector2(centre.x - p.x, centre.z - p.z).length()
			if d > RADIUS:
				continue
			_want[t] = true
			if not _tiles.has(t):
				_queue.append(t)
	# drop tiles that fell out of range
	for t in _tiles.keys():
		if not _want.has(t):
			var n = _tiles[t]
			if n != null and is_instance_valid(n):
				n.queue_free()
			_tiles.erase(t)

func _drain(budget: int) -> void:
	var made := 0
	while made < budget and _head < _queue.size():
		var t: Vector2i = _queue[_head]
		_head += 1
		if _tiles.has(t) or not _want.has(t) or _tiles.size() >= MAX_TILES:
			continue
		_build_tile(t)
		made += 1
	if _head >= _queue.size():
		_queue.clear()
		_head = 0

func _build_tile(t: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t.x) * 73856093 ^ int(t.y) * 19349663
	var pines: Array = []
	var rocks: Array = []
	var bushes: Array = []
	var x0 := float(t.x) * TILE
	var z0 := float(t.y) * TILE
	for i in SPAWN_PER_TILE:
		var x := x0 + rng.randf() * TILE
		var z := z0 + rng.randf() * TILE
		var h: float = island.height(x, z)
		if h < Island.SEA + 2.0:
			continue
		var slope: float = island.slope_at(x, z)
		if roads != null and roads.near_road(Vector3(x, h, z), 9.5):
			continue
		if world != null and world.has_method("near_town") and world.near_town(Vector3(x, h, z), 12.0):
			continue
		# how wooded this spot is: patches of forest, open meadow between them
		var forest := _dens.get_noise_2d(x, z) * 0.5 + 0.5
		forest = clampf((forest - 0.28) * 1.8, 0.0, 1.0)
		if h > 208.0:
			forest = 0.0
		var roll := rng.randf()
		var pos := Vector3(x, h, z)
		# even the barest meadow keeps a few lone trees, so no slope looks empty
		if slope < 0.33 and roll < maxf(forest * 0.92, 0.055):
			var s := rng.randf_range(0.72, 1.75) * (1.0 - clampf((h - 120.0) / 260.0, 0.0, 0.4))
			# sink the base a little on a bank so the uphill side does not float
			pines.append(_xf(pos - Vector3(0, 0.10 + slope * 0.8 * s, 0), rng.randf() * TAU, s))
		elif slope > 0.06 and roll < 0.52:
			var s: float = rng.randf_range(0.5, 1.15) * (0.75 + minf(slope, 0.4) * 0.8)
			rocks.append(_xf(pos - Vector3(0, (0.20 + slope * 0.9) * s, 0), rng.randf() * TAU, s))
		elif roll < 0.72:
			var s: float = rng.randf_range(0.6, 1.5)
			bushes.append(_xf(pos - Vector3(0, 0.06 + slope * 0.5 * s, 0), rng.randf() * TAU, s))
	# a bare mountain top still gets its boulders
	if rocks.size() == 0 and pines.size() == 0:
		for i in 3:
			var x := x0 + rng.randf() * TILE
			var z := z0 + rng.randf() * TILE
			var h: float = island.height(x, z)
			if h < Island.SEA + 2.0:
				continue
			rocks.append(_xf(Vector3(x, h, z), rng.randf() * TAU, rng.randf_range(0.5, 1.2)))
	if pines.is_empty() and rocks.is_empty() and bushes.is_empty():
		_tiles[t] = null
		return
	var node := Node3D.new()
	node.name = "Nature_%d_%d" % [t.x, t.y]
	if not pines.is_empty():
		node.add_child(_mm(_mesh_pine, pines))
	if not rocks.is_empty():
		node.add_child(_mm(_mesh_rock, rocks))
	if not bushes.is_empty():
		node.add_child(_mm(_mesh_bush, bushes))
	add_child(node)
	_tiles[t] = node

static func _xf(pos: Vector3, yaw: float, s: float) -> Transform3D:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.94 + 0.06 * s, s))
	return Transform3D(b, pos)

func _mm(mesh: ArrayMesh, xfs: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mmi

func tile_count() -> int:
	return _tiles.size()

func prop_count() -> int:
	var n := 0
	for t in _tiles:
		var node: Node3D = _tiles[t]
		if node == null:
			continue
		for c in node.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi != null and mmi.multimesh != null:
				n += mmi.multimesh.instance_count
	return n
