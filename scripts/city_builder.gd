class_name CityBuilder
extends RefCounted

## Procedural block generator.  Every function writes raw triangles into a
## MeshBatch; nothing here creates nodes, so a whole block (buildings, trees,
## fences, neon, street lights) collapses into 2 draw calls.
##
## `cols` collects AABB boxes used for collision.

const SOLID := MeshBatch.SOLID
const GLOW := MeshBatch.GLOW
const GLASS := MeshBatch.GLASS

enum { RESIDENTIAL, COMMERCIAL, PARK, SCHOOL, POLICE, HOSPITAL, CLUB, LOT, PLAZA,
	FACTORY, WAREHOUSE, CLOCKTOWER, STADIUM, PEAK, GRAVEYARD,
	HANGAR, MILL, SHIPYARD, OBSERVATORY, CAPETOWN, SENTOSA, POCHINOK,
	MARSELECTRIC, RIMNAM, KATULISTIWA, BIMASAKTI, BULLSEYE, PLANTATION,
	RIVERSIDE, COUNTRYSIDE }

## Prop functions (trees, lamps, benches, parked props ...) are called from
## dozens of places without a collider list, so `build()` parks the current
## block's list here and the props append to it.  That is how every tree and
## lamp post in the world ends up solid without touching a single call site.
static var cur_cols: Array = []
## Floor spots inside shops / warehouses where loot may be dropped.  Filled while
## the block is being built and read straight after by the world.
static var _loot_spots: Array = []

## Register a simple upright box collider for a prop.
static func _solid(p: Vector3, radius: float, height: float) -> void:
	if cur_cols.is_empty():
		return
	_add_col(cur_cols, p + Vector3(0, height * 0.5, 0), Vector3(radius * 2.0, height, radius * 2.0))

## Register a box collider from a centre + size.  Exact: no skirt, so pieces
## that float (door headers, roof slabs, shelves) never block a doorway.
static func _solid_box(centre: Vector3, size: Vector3) -> void:
	if cur_cols.is_empty():
		return
	cur_cols.append(AABB(centre - size * 0.5, size))

# ============================================================== entry point

static func build(b: MeshBatch, type: int, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	cur_cols = cols
	# loot spawn points are collected per block, exactly like the colliders
	HouseBuilder.rooms.clear()
	_loot_spots.clear()
	_road_marks(b, o)
	_ground(b, o, type, rng)
	var gy := o.y + 0.06
	var p := Vector3(o.x, gy, o.z)
	match type:
		RESIDENTIAL: _residential(b, rng, p, cols)
		COMMERCIAL: _commercial(b, rng, p, cols)
		PARK: _park(b, rng, p)
		SCHOOL: _school(b, rng, p, cols)
		POLICE: _police(b, rng, p, cols)
		HOSPITAL: _hospital(b, rng, p, cols)
		CLUB: _club(b, rng, p, cols)
		LOT: _parking_lot(b, rng, p)
		PLAZA: _plaza(b, rng, p, cols)
		FACTORY: _factory(b, rng, p, cols)
		WAREHOUSE: _warehouse(b, rng, p, cols)
		CLOCKTOWER: _clocktower(b, rng, p, cols)
		STADIUM: _stadium(b, rng, p, cols)
		PEAK: _peak(b, rng, p, cols)
		GRAVEYARD: _graveyard(b, rng, p, cols)
		HANGAR: _hangar(b, rng, p, cols)
		MILL: _mill(b, rng, p, cols)
		SHIPYARD: _shipyard(b, rng, p, cols)
		OBSERVATORY: _observatory(b, rng, p, cols)
		CAPETOWN: _capetown(b, rng, p, cols)
		SENTOSA: _sentosa(b, rng, p, cols)
		POCHINOK: _pochinok(b, rng, p, cols)
		MARSELECTRIC: _marselectric(b, rng, p, cols)
		RIMNAM: _rimnam(b, rng, p, cols)
		KATULISTIWA: _katulistiwa(b, rng, p, cols)
		BIMASAKTI: _bimasakti(b, rng, p, cols)
		BULLSEYE: _bullseye(b, rng, p, cols)
		PLANTATION: _plantation(b, rng, p, cols)
		RIVERSIDE: _riverside(b, rng, p, cols)
		COUNTRYSIDE: _countryside(b, rng, p, cols)

# ============================================================== helpers

static func _add_col(cols: Array, center: Vector3, size: Vector3) -> void:
	# the block sits on whatever height the town was placed at, so the collider
	# is the box itself with a couple of metres of skirt below it (never anchored
	# to y = 0, or every town would have invisible walls under it)
	var bottom := center.y - size.y * 0.5 - 2.0
	var top := center.y + size.y * 0.5
	cols.append(AABB(Vector3(center.x - size.x * 0.5, bottom, center.z - size.z * 0.5),
		Vector3(size.x, top - bottom, size.z)))

static func _box(b: MeshBatch, c: Vector3, s: Vector3, col: Color, top: Color = Color(-1, -1, -1, -1)) -> void:
	b.box(SOLID, c, s, col, top)

## Axis aligned box given in an oriented frame (ax = "length" axis, must be
## one of the world axes; used for parked cars).
static func _obox(b: MeshBatch, c: Vector3, ax: Vector3, along: float, across: float, h: float,
		col: Color, top: Color = Color(-1, -1, -1, -1), surf: int = SOLID) -> void:
	var size: Vector3
	if absf(ax.x) > 0.5:
		size = Vector3(along, h, across)
	else:
		size = Vector3(across, h, along)
	b.box(surf, c, size, col, top)

static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]


## Road markings are generated per block too, so they stream with the city and
## never z-fight in the distance.  Every cell draws the two roads on its
## -X / -Z edges plus the zebra crossing of the junction in that corner.
static func _road_marks(b: MeshBatch, o: Vector3) -> void:
	var y := o.y + 0.1
	var cell := CityConfig.CELL
	var cx := o.x - cell * 0.5
	var cz := o.z - cell * 0.5
	# road running along Z at x = cx
	b.plate(SOLID, Vector3(cx - 0.4, y, o.z), Vector2(0.18, cell), CityConfig.C_LINE_Y)
	b.plate(SOLID, Vector3(cx + 0.4, y, o.z), Vector2(0.18, cell), CityConfig.C_LINE_Y)
	b.plate(SOLID, Vector3(cx - CityConfig.HALF_ROAD + 0.9, y, o.z), Vector2(0.22, cell), CityConfig.C_LINE)
	b.plate(SOLID, Vector3(cx + CityConfig.HALF_ROAD - 0.9, y, o.z), Vector2(0.22, cell), CityConfig.C_LINE)
	# road running along X at z = cz
	b.plate(SOLID, Vector3(o.x, y, cz - 0.4), Vector2(cell, 0.18), CityConfig.C_LINE_Y)
	b.plate(SOLID, Vector3(o.x, y, cz + 0.4), Vector2(cell, 0.18), CityConfig.C_LINE_Y)
	b.plate(SOLID, Vector3(o.x, y, cz - CityConfig.HALF_ROAD + 0.9), Vector2(cell, 0.22), CityConfig.C_LINE)
	b.plate(SOLID, Vector3(o.x, y, cz + CityConfig.HALF_ROAD - 0.9), Vector2(cell, 0.22), CityConfig.C_LINE)
	# zebra crossings + stop lines around the junction at (cx, cz)
	var ic := Vector3(cx, 0, cz)
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var base: Vector3 = ic + d * (CityConfig.HALF_ROAD + 2.2)
		var right: Vector3 = CityConfig.right_of(d)
		for k in 6:
			var o2: Vector3 = right * (float(k) - 2.5) * 2.0
			if absf(d.x) > 0.5:
				b.plate(SOLID, base + o2 + Vector3(0, y, 0), Vector2(3.0, 0.75), CityConfig.C_LINE)
			else:
				b.plate(SOLID, base + o2 + Vector3(0, y, 0), Vector2(0.75, 3.0), CityConfig.C_LINE)
		var sp: Vector3 = ic + d * (CityConfig.HALF_ROAD + 4.6) + right * (CityConfig.HALF_ROAD * 0.5)
		if absf(d.x) > 0.5:
			b.plate(SOLID, sp + Vector3(0, y, 0), Vector2(0.45, CityConfig.HALF_ROAD - 1.2), CityConfig.C_LINE)
		else:
			b.plate(SOLID, sp + Vector3(0, y, 0), Vector2(CityConfig.HALF_ROAD - 1.2, 0.45), CityConfig.C_LINE)

# ---------------------------------------------------------------- block base

static func _ground(b: MeshBatch, o: Vector3, type: int, rng: RandomNumberGenerator) -> void:
	var B := CityConfig.BLOCK
	var h := B * 0.5
	# sidewalk surface (flush with the road, painted on top of the asphalt)
	var rural := type == COUNTRYSIDE
	var walk_col: Color = CityConfig.C_GRASS_D if rural else CityConfig.C_SIDEWALK
	# flush with the asphalt plate (which sits at +0.06) so nobody's feet and no
	# tyre are swallowed by the kerb; 2 cm of clearance keeps the two plates
	# from z-fighting
	b.plate(SOLID, o, Vector2(B, B), walk_col, 0.08)
	# kerb lip ring: purely visual, low enough to drive over
	var lip := 0.36
	var c := CityConfig.CURB
	for s in [-1.0, 1.0]:
		_box(b, o + Vector3(0, c * 0.5, s * (h + lip * 0.5)), Vector3(B + lip * 2.0, c, lip),
			CityConfig.C_GRASS_D if rural else CityConfig.C_SIDEWALK_D)
		_box(b, o + Vector3(s * (h + lip * 0.5), c * 0.5, 0), Vector3(lip, c, B),
			CityConfig.C_GRASS_D if rural else CityConfig.C_SIDEWALK_D)
	# inner surface
	var g := B - CityConfig.SIDEWALK * 2.0
	var surf := CityConfig.C_GRASS
	if type == COMMERCIAL or type == PLAZA or type == LOT or type == POLICE or type == HOSPITAL:
		surf = CityConfig.C_CONCRETE
	elif type == CLUB:
		surf = Color("453c50")
	elif type == FACTORY or type == WAREHOUSE:
		surf = Color("7a7c78")
	elif type == CLOCKTOWER:
		surf = CityConfig.C_STONE_D
	elif type == STADIUM:
		surf = Color("9a9c98")
	elif type == GRAVEYARD:
		surf = CityConfig.C_DEAD_GRASS
	elif type == PEAK:
		surf = CityConfig.C_GRASS
	elif type == HANGAR or type == SHIPYARD:
		surf = Color("7a7c78")
	elif type == MILL:
		surf = Color("8a7458")
	elif type == OBSERVATORY or type == POCHINOK or type == RIVERSIDE or type == COUNTRYSIDE:
		surf = CityConfig.C_GRASS
	elif type == CAPETOWN or type == BULLSEYE:
		surf = Color("d8c89a")
	elif type == SENTOSA:
		surf = Color("e0d2a8")
	elif type == MARSELECTRIC:
		surf = Color("8a5a42")
	elif type == RIMNAM:
		surf = Color("2f7fa8")
	elif type == KATULISTIWA:
		surf = Color("c8c4b8")
	elif type == BIMASAKTI:
		surf = Color("2b2f36")
	elif type == PLANTATION:
		surf = Color("6b5a3f")
	b.plate(SOLID, o, Vector2(g, g), surf, 0.15)
	# paving joints on the sidewalk
	for s in [-1.0, 1.0]:
		if rural:
			break
		b.plate(SOLID, o + Vector3(0, 0, s * (h - CityConfig.SIDEWALK * 0.5)),
			Vector2(B, CityConfig.SIDEWALK), CityConfig.C_SIDEWALK_D.lightened(0.12), 0.14)
		b.plate(SOLID, o + Vector3(s * (h - CityConfig.SIDEWALK * 0.5), 0, 0),
			Vector2(CityConfig.SIDEWALK, B), CityConfig.C_SIDEWALK_D.lightened(0.12), 0.14)
	# street trees planted in the sidewalk
	for side in 4:
		if rural:
			break
		var along_x := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		for i in 2:
			var t := (-0.30 + 0.60 * float(i)) * h + rng.randf_range(-4.0, 4.0)
			var tp := o + (Vector3(t, 0, sgn * (h - CityConfig.SIDEWALK * 0.55)) if along_x
				else Vector3(sgn * (h - CityConfig.SIDEWALK * 0.55), 0, t))
			if rng.randf() < 0.78:
				tree(b, tp, rng.randf_range(0.8, 1.15), rng)
			else:
				streetlight(b, tp, -Vector3(0, 0, sgn) if along_x else -Vector3(sgn, 0, 0))
	# street furniture
	for i in rng.randi_range(2, 5) if not rural else 0:
		var side := rng.randi_range(0, 3)
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var t := rng.randf_range(-h * 0.78, h * 0.78)
		var pp := o + (Vector3(t, 0, sgn * (h - 1.7)) if side < 2 else Vector3(sgn * (h - 1.7), 0, t))
		match rng.randi_range(0, 2):
			0:
				_box(b, pp + Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.5), Color("3d6b46"))
				_box(b, pp + Vector3(0, 0.95, 0), Vector3(0.56, 0.1, 0.56), Color("2b4b33"))
			1:
				b.cylinder(SOLID, pp, 0.16, 0.16, 0.78, 6, Color("c8402f"))
				_box(b, pp + Vector3(0, 0.78, 0), Vector3(0.36, 0.14, 0.36), Color("c8402f"))
			_:
				_box(b, pp + Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2), Color("9c9a90"))
				_bush(b, pp + Vector3(0, 0.55, 0), 0.62, rng)

# ============================================================== RESIDENTIAL

static func _residential(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var lot := g * 0.5
	var skip := rng.randi_range(0, 3)
	var n := 0
	for ix in 2:
		for iz in 2:
			var lc := Vector3(o.x - lot * 0.5 + float(ix) * lot, o.y, o.z - lot * 0.5 + float(iz) * lot)
			if n == skip:
				# one lot of the block becomes a small garden / playground
				_garden(b, rng, lc, lot)
			else:
				_house_lot(b, rng, lc, lot, (1.0 if iz == 1 else -1.0), cols)
			n += 1

static func _garden(b: MeshBatch, rng: RandomNumberGenerator, c: Vector3, s: float) -> void:
	var half := s * 0.5 - 1.0
	b.plate(SOLID, c, Vector2(half * 2.0, half * 2.0), CityConfig.C_GRASS_D, 0.17)
	# path cross
	_box(b, c + Vector3(0, 0.03, 0), Vector3(half * 2.0, 0.05, 2.2), CityConfig.C_SIDEWALK)
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		tree(b, c + Vector3(cos(a) * half * 0.55, 0, sin(a) * half * 0.55), rng.randf_range(0.8, 1.3), rng)
	_bench(b, c + Vector3(3.5, 0, -3.5), Vector3(-1, 0, 0))
	_bench(b, c + Vector3(-3.5, 0, 3.5), Vector3(1, 0, 0))

static func _house_lot(b: MeshBatch, rng: RandomNumberGenerator, lc: Vector3, lot: float,
		facing: float, cols: Array) -> void:
	var w := rng.randf_range(9.0, 12.5)
	var d := rng.randf_range(8.0, 10.0)
	var floors := 1 if rng.randf() < 0.55 else 2
	var back := -facing * (lot * 0.5 - d * 0.5 - 2.5)
	var hc := lc + Vector3(0, 0, back)
	var wall: Color = _pick(rng, [CityConfig.C_WALL_A, CityConfig.C_WALL_B, CityConfig.C_WALL_C,
		CityConfig.C_WALL_D, CityConfig.C_WALL_E, CityConfig.C_BRICK])
	var roof: Color = _pick(rng, [CityConfig.C_ROOF_A, CityConfig.C_ROOF_B, CityConfig.C_ROOF_C, CityConfig.C_ROOF_D])
	# Three out of four houses are walk-in: two floors, furniture, internal
	# stairs, a roof you can stand on.  The rest stay solid old-town houses.
	if true:
		w = clampf(w + 1.2, 10.5, 13.0)
		d = clampf(d + 1.0, 9.0, 11.0)
		hc = lc + Vector3(0, 0, back)
		var hcols := HouseBuilder.build(b, rng, hc + Vector3(0, 0.30, 0), w, d, wall, roof, facing)
		for a in hcols:
			cols.append(a)
	else:
		_house(b, rng, hc, w, d, floors, wall, roof, facing)
		_add_col(cols, hc + Vector3(0, (2.0 + floors * 3.0) * 0.5, 0), Vector3(w, 2.0 + floors * 3.0 + 2.0, d))

	# front yard: driveway, fence/hedge, trees, mailbox
	var front := facing * (lot * 0.5)
	_box(b, lc + Vector3(w * 0.3, 0.02, back + facing * (d * 0.5 + 3.0)),
		Vector3(3.4, 0.06, 6.0), CityConfig.C_ASPHALT.lightened(0.06))
	var fence_h := rng.randf_range(0.9, 1.25)
	var low := rng.randf() < 0.45
	if low:
		_hedge_ring(b, lc, lot - 1.0, facing, fence_h)
	else:
		_fence_ring(b, lc, lot - 1.0, facing)
	# trees
	var n_trees := rng.randi_range(1, 3)
	for i in n_trees:
		var tx := rng.randf_range(-lot * 0.5 + 2.5, lot * 0.5 - 2.5)
		var tz := rng.randf_range(-lot * 0.5 + 2.5, lot * 0.5 - 2.5)
		var tp := lc + Vector3(tx, 0, tz)
		if tp.distance_to(hc) > maxf(w, d) * 0.75 + 1.2:
			tree(b, tp, rng.randf_range(0.7, 1.15), rng)
	# mailbox + lamp by the gate
	_box(b, lc + Vector3(-w * 0.5 - 1.8, 0.55, back + facing * (d * 0.5 + 1.6)),
		Vector3(0.28, 1.1, 0.28), CityConfig.C_METAL_D)
	_box(b, lc + Vector3(-w * 0.5 - 1.8, 1.25, back + facing * (d * 0.5 + 1.6)),
		Vector3(0.5, 0.4, 0.75), CityConfig.C_METAL)
	# front path from sidewalk to door
	_box(b, lc + Vector3(0, 0.06, back + facing * (d * 0.5 + 2.2)),
		Vector3(1.6, 0.12, 4.4), CityConfig.C_CONCRETE_D)

static func _house(b: MeshBatch, rng: RandomNumberGenerator, c: Vector3, w: float, d: float,
		floors: int, wall: Color, roof: Color, facing: float) -> void:
	var fh := 3.0
	var trim := Color("f5f2e9")
	# plinth
	_box(b, c + Vector3(0, 0.15, 0), Vector3(w + 0.6, 0.3, d + 0.6), CityConfig.C_CONCRETE_D)
	for f in floors:
		var y0 := 0.3 + float(f) * fh
		_box(b, c + Vector3(0, y0 + fh * 0.5, 0), Vector3(w, fh, d), wall, wall)
		# floor trim band
		_box(b, c + Vector3(0, y0 + fh - 0.09, 0), Vector3(w + 0.22, 0.18, d + 0.22), trim)
		# windows on the two Z faces
		for sz in [-1.0, 1.0]:
			for sx in [-0.26, 0.26]:
				if rng.randf() < 0.9:
					_window(b, c + Vector3(w * sx, y0 + 1.75, sz * (d * 0.5)), Vector3(0, 0, sz),
						1.35, 1.5, trim, CityConfig.C_GLOW_WIN if rng.randf() < 0.85 else CityConfig.C_GLASS_D)
		# one window per X face
		for sx in [-1.0, 1.0]:
			_window(b, c + Vector3(sx * (w * 0.5), y0 + 1.75, 0.0), Vector3(sx, 0, 0),
				1.25, 1.4, trim, CityConfig.C_GLOW_WIN)
	# roof
	var ytop := 0.3 + float(floors) * fh
	var rh := rng.randf_range(2.0, 3.2)
	var over := 0.7
	if rng.randf() < 0.25 and floors >= 2:
		# flat roof with parapet
		_box(b, c + Vector3(0, ytop + 0.12, 0), Vector3(w + 0.5, 0.24, d + 0.5), roof)
		for s in [-1.0, 1.0]:
			_box(b, c + Vector3(0, ytop + 0.6, s * (d * 0.5 + 0.2)), Vector3(w + 0.6, 0.9, 0.24), wall)
			_box(b, c + Vector3(s * (w * 0.5 + 0.2), ytop + 0.6, 0), Vector3(0.24, 0.9, d + 0.6), wall)
	else:
		b.gable(SOLID, c + Vector3(0, ytop, 0), w + over * 2.0, d + over * 2.0, rh, roof, roof.darkened(0.1))
		# ridge cap
		_box(b, c + Vector3(0, ytop + rh - 0.06, 0), Vector3(w + over * 2.0 + 0.2, 0.14, 0.36), roof.darkened(0.25))
		# chimney
		if rng.randf() < 0.7:
			var ch := c + Vector3(w * 0.32, ytop + rh * 0.55, -d * 0.22)
			_box(b, ch + Vector3(0, 0.9, 0), Vector3(0.7, 1.9, 0.7), CityConfig.C_BRICK)
			_box(b, ch + Vector3(0, 1.9, 0), Vector3(0.9, 0.16, 0.9), CityConfig.C_CONCRETE_D)
	# door + porch
	var door_y := 0.3
	_box(b, c + Vector3(0, door_y + 1.05, facing * (d * 0.5 + 0.06)), Vector3(1.3, 2.1, 0.14), CityConfig.C_WOOD)
	_box(b, c + Vector3(0, door_y + 1.05, facing * (d * 0.5 + 0.14)), Vector3(0.1, 0.1, 0.1), CityConfig.C_GLOW_NEON_Y)
	_box(b, c + Vector3(0, door_y + 0.06, facing * (d * 0.5 + 0.5)), Vector3(2.0, 0.12, 1.1), CityConfig.C_CONCRETE)
	_box(b, c + Vector3(0, door_y + 2.85, facing * (d * 0.5 + 0.85)), Vector3(3.0, 0.22, 1.8), roof)
	for sx in [-1.0, 1.0]:
		_box(b, c + Vector3(sx * 1.3, door_y + 1.45, facing * (d * 0.5 + 1.55)), Vector3(0.18, 2.6, 0.18), trim)
	# balcony on upper floors
	if floors >= 2:
		_box(b, c + Vector3(0, 0.3 + fh + 0.05, facing * (d * 0.5 + 0.75)), Vector3(w * 0.7, 0.16, 1.5), trim)
		for i in 5:
			var bx := (float(i) / 4.0 - 0.5) * w * 0.66
			_box(b, c + Vector3(bx, 0.3 + fh + 0.55, facing * (d * 0.5 + 1.45)), Vector3(0.1, 0.95, 0.1), trim)
		_box(b, c + Vector3(0, 0.3 + fh + 1.05, facing * (d * 0.5 + 1.45)), Vector3(w * 0.7, 0.1, 0.14), trim)

static func _window(b: MeshBatch, c: Vector3, n: Vector3, w: float, h: float,
		frame: Color, glass: Color) -> void:
	# sizes in the plane of the wall, plus a thin depth along the normal
	var fsize: Vector3
	var gsize: Vector3
	if absf(n.x) > 0.5:
		fsize = Vector3(0.09, h + 0.26, w + 0.26)
		gsize = Vector3(0.09, h, w)
	else:
		fsize = Vector3(w + 0.26, h + 0.26, 0.09)
		gsize = Vector3(w, h, 0.09)
	# frame sits against the wall, glass sticks out through it
	_box(b, c + n * 0.03, fsize, frame)
	b.box(GLASS, c + n * 0.09, gsize, glass)
	# sill
	var ssize: Vector3
	if absf(n.x) > 0.5:
		ssize = Vector3(0.3, 0.1, w + 0.4)
	else:
		ssize = Vector3(w + 0.4, 0.1, 0.3)
	_box(b, c + n * 0.1 + Vector3(0, -h * 0.5 - 0.16, 0), ssize, frame.darkened(0.15))

static func _fence_ring(b: MeshBatch, c: Vector3, s: float, facing: float) -> void:
	var half := s * 0.5
	var col := Color("d8d2c4")
	var h := 1.15
	var step := 5.0
	for side in 4:
		var along_x := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var n := int(half * 2.0 / step)
		for i in n + 1:
			var t := -half + float(i) * (half * 2.0 / float(n))
			if facing > 0.0 and sgn > 0.0 and absf(t) < 2.2:
				continue  # gate gap
			var pp := c + (Vector3(t, 0, sgn * half) if along_x else Vector3(sgn * half, 0, t))
			_box(b, pp + Vector3(0, h * 0.5, 0), Vector3(0.14, h, 0.14), col)
		for y in [0.45, 0.95]:
			var cc := c + (Vector3(0, y, sgn * half) if along_x else Vector3(sgn * half, 0, 0))
			var sz := Vector3(half * 2.0, 0.08, 0.08) if along_x else Vector3(0.08, 0.08, half * 2.0)
			_box(b, cc, sz, col.darkened(0.1))

static func _hedge_ring(b: MeshBatch, c: Vector3, s: float, facing: float, h: float) -> void:
	var half := s * 0.5
	var col := CityConfig.C_LEAF2
	for side in 4:
		var along_x := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var sz := Vector3(half * 2.0, h, 0.8) if along_x else Vector3(0.8, h, half * 2.0)
		var cc := c + (Vector3(0, h * 0.5, sgn * half) if along_x else Vector3(sgn * half, 0, 0))
		_box(b, cc, sz, col, col.lightened(0.08))

# ============================================================== COMMERCIAL

static func _commercial(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var lot := g * 0.5
	# plaza paving
	b.plate(SOLID, o, Vector2(g, g), CityConfig.C_CONCRETE_D, 0.16)
	for ix in 2:
		for iz in 2:
			var lc := Vector3(o.x - lot * 0.5 + float(ix) * lot, o.y, o.z - lot * 0.5 + float(iz) * lot)
			if rng.randf() < 0.16:
				_garden(b, rng, lc, lot)
				continue
			var w := rng.randf_range(17.0, 23.0)
			var d := rng.randf_range(15.0, 20.0)
			var floors := rng.randi_range(3, 9) if rng.randf() < 0.55 else rng.randi_range(2, 4)
			var wall: Color = _pick(rng, [CityConfig.C_WALL_C, CityConfig.C_WALL_D, Color("b8b2a8"),
				Color("7f9bb5"), Color("d3a072"), Color("9fb898"), Color("c98f86"), Color("b8a2c0"),
				Color("e2b96e"), Color("8fb5ae")])
			var glass: Color = _pick(rng, [Color("3c6b80"), Color("2f5069"), Color("5c8ea6"),
				Color("243b4a"), Color("4a7a6c"), Color("7a5f52")])
			var neon: Color = _pick(rng, [CityConfig.C_GLOW_NEON_P, CityConfig.C_GLOW_NEON_C,
				CityConfig.C_GLOW_NEON_V, CityConfig.C_GLOW_NEON_Y])
			_tower(b, rng, lc, w, d, floors, wall, glass, neon)
			var hh := 4.2 + float(floors) * 3.3 + 1.2
			# upper floors are solid; the shop floor has its own thin walls
			_add_col(cols, lc + Vector3(0, 4.2 + (hh - 4.2) * 0.5, 0), Vector3(w, hh - 4.2, d))
			# planters + trees around the plaza
			for k in 2:
				var tp := lc + Vector3(rng.randf_range(-lot * 0.5 + 2.0, lot * 0.5 - 2.0), 0,
					rng.randf_range(-lot * 0.5 + 2.0, lot * 0.5 - 2.0))
				if absf(tp.x - lc.x) > w * 0.5 + 2.5 or absf(tp.z - lc.z) > d * 0.5 + 2.5:
					tree(b, tp, rng.randf_range(0.75, 1.1), rng)
	# benches along the block edge
	_bench(b, Vector3(o.x - g * 0.42, o.y, o.z + g * 0.46), Vector3(0, 0, -1))
	_bench(b, Vector3(o.x + g * 0.42, o.y, o.z - g * 0.46), Vector3(0, 0, 1))

## Walls, doorway, glass front, furniture and lights for a walk-in shop floor.
static func _shop(b: MeshBatch, c: Vector3, w: float, d: float, gh: float,
		wall: Color, glass: Color, neon: Color) -> void:
	var t := 0.34
	var dw := 2.6                       # doorway width
	var dh := 2.7                       # doorway height
	var y0 := 0.26
	var wc := wall.darkened(0.12)
	# --- side walls
	for s in [-1.0, 1.0]:
		var cx := c + Vector3(s * (w * 0.5 - t * 0.5), y0 + (gh - y0) * 0.5, 0)
		_box(b, cx, Vector3(t, gh - y0, d), wc)
		_solid_box(cx, Vector3(t, gh - y0, d))
	# --- front and back: glass either side of a central doorway
	for s in [-1.0, 1.0]:
		var z: float = s * (d * 0.5 - t * 0.5)
		var seg := (w - dw) * 0.5
		for sx in [-1.0, 1.0]:
			var cx := c + Vector3(sx * (dw * 0.5 + seg * 0.5), y0 + (gh - y0) * 0.5, z)
			_box(b, cx, Vector3(seg, gh - y0, t), wc)
			_solid_box(cx, Vector3(seg, gh - y0, t))
			# shop window in the middle of each segment
			b.box(GLASS, c + Vector3(sx * (dw * 0.5 + seg * 0.5), 2.05, s * (d * 0.5 + 0.02)),
				Vector3(seg * 0.82, 2.0, 0.08), glass)
			for i in 3:
				var mx: float = sx * (dw * 0.5 + seg * 0.5) + (float(i) - 1.0) * seg * 0.27
				_box(b, c + Vector3(mx, 2.05, s * (d * 0.5 + 0.10)), Vector3(0.11, 2.1, 0.12),
					CityConfig.C_METAL_D)
		# header over the doorway
		var hc := c + Vector3(0, dh + (gh - dh) * 0.5, z)
		_box(b, hc, Vector3(dw, gh - dh, t), wc)
		_solid_box(hc, Vector3(dw, gh - dh, t))
		# door frame + an open glass leaf
		for sx in [-1.0, 1.0]:
			_box(b, c + Vector3(sx * (dw * 0.5 + 0.09), y0 + dh * 0.5, z),
				Vector3(0.18, dh, t + 0.10), CityConfig.C_METAL_D)
		_box(b, c + Vector3(0, y0 + dh, z), Vector3(dw + 0.36, 0.18, t + 0.12), CityConfig.C_METAL_D)
		b.box(GLASS, c + Vector3(-dw * 0.5 + 0.06, y0 + dh * 0.5, z - s * 0.42), Vector3(0.06, dh * 0.9, 0.9), glass)
		# awning + neon sign band
		_box(b, c + Vector3(0, gh + 0.30, s * (d * 0.5 + 0.62)), Vector3(w * 0.92, 0.18, 1.25), neon.darkened(0.35))
		b.box(GLOW, c + Vector3(0, gh - 0.32, s * (d * 0.5 + 0.16)), Vector3(w * 0.5, 0.5, 0.1), neon)
	# --- inside: counter, shelves, crates, a ceiling light
	var ctr := c + Vector3(0.0, y0 + 0.55, -d * 0.22)
	_box(b, ctr, Vector3(minf(w * 0.5, 4.2), 1.1, 0.85), CityConfig.C_WOOD)
	_box(b, ctr + Vector3(0, 0.60, 0), Vector3(minf(w * 0.5, 4.2) + 0.2, 0.08, 1.0), Color("2b2f36"))
	_solid_box(ctr, Vector3(minf(w * 0.5, 4.2), 1.1, 0.85))
	for sx in [-1.0, 1.0]:
		var shel := c + Vector3(sx * (w * 0.5 - 0.9), y0 + 1.0, 0.0)
		_box(b, shel, Vector3(0.7, 2.0, minf(d * 0.55, 5.0)), Color("8a7150"))
		for r in 4:
			_box(b, shel + Vector3(0, -0.7 + float(r) * 0.5, 0),
				Vector3(0.78, 0.06, minf(d * 0.55, 5.0)), CityConfig.C_WOOD.darkened(0.2))
		_solid_box(shel, Vector3(0.7, 2.0, minf(d * 0.55, 5.0)))
	for i in 3:
		var cp := c + Vector3(randf_range(-w * 0.3, w * 0.3), y0 + 0.35, randf_range(-d * 0.1, d * 0.3))
		_box(b, cp, Vector3(0.7, 0.7, 0.7), Color("a8763c"))
	# loot goes on the shop floor, clear of the counter and the shelves
	_loot_spots.append(c + Vector3(-w * 0.18, y0 + 0.06, d * 0.18))
	_loot_spots.append(c + Vector3(w * 0.20, y0 + 0.06, -d * 0.02))
	# ceiling + light so the room is not pitch black
	_box(b, c + Vector3(0, gh - 0.10, 0), Vector3(w - 0.1, 0.20, d - 0.1), wall.darkened(0.30))
	b.box(GLOW, c + Vector3(0, gh - 0.22, 0), Vector3(1.6, 0.06, 1.6), CityConfig.C_GLOW_WIN)
	# the plinth is a step, not a wall — the doorway stays clear
	_solid_box(c + Vector3(0, 0.13, 0), Vector3(w + 1.2, 0.26, d + 1.2))

static func _tower(b: MeshBatch, rng: RandomNumberGenerator, c: Vector3, w: float, d: float,
		floors: int, wall: Color, glass: Color, neon: Color) -> void:
	var gh := 4.2
	var fh := 3.3
	# --- ground floor: a real shop you can walk into.
	# low plinth (a step, not a wall) + a tiled shop floor
	_box(b, c + Vector3(0, 0.13, 0), Vector3(w + 1.2, 0.26, d + 1.2), CityConfig.C_CONCRETE_D)
	_box(b, c + Vector3(0, 0.30, 0), Vector3(w - 0.20, 0.06, d - 0.20), Color("6f6455"))
	_shop(b, c, w, d, gh, wall, glass, neon)
	# upper floors
	var y0 := gh + 0.5
	for f in floors:
		var y := y0 + float(f) * fh
		_box(b, c + Vector3(0, y + fh * 0.5, 0), Vector3(w, fh, d), wall, wall)
		# window bands
		for s in [-1.0, 1.0]:
			_box(b, c + Vector3(0, y + fh * 0.58, s * (d * 0.5 + 0.02)), Vector3(w * 0.96, fh * 0.56, 0.06), wall.darkened(0.22))
			b.box(GLASS, c + Vector3(0, y + fh * 0.58, s * (d * 0.5 + 0.07)), Vector3(w * 0.88, fh * 0.46, 0.08), glass)
			for i in 3:
				var mx := (float(i) / 2.0 - 0.5) * w * 0.8
				_box(b, c + Vector3(mx, y + fh * 0.58, s * (d * 0.5 + 0.13)), Vector3(0.14, fh * 0.46, 0.14), wall.darkened(0.3))
		for s in [-1.0, 1.0]:
			b.box(GLASS, c + Vector3(s * (w * 0.5 + 0.07), y + fh * 0.58, 0), Vector3(0.08, fh * 0.46, d * 0.86), glass)
		# floor slab line
		_box(b, c + Vector3(0, y + fh, 0), Vector3(w + 0.3, 0.22, d + 0.3), wall.darkened(0.18))
	var top := y0 + float(floors) * fh
	# roof
	_box(b, c + Vector3(0, top + 0.2, 0), Vector3(w + 0.5, 0.4, d + 0.5), CityConfig.C_CONCRETE_D)
	_solid_box(c + Vector3(0, top + 0.2, 0), Vector3(w + 0.5, 0.4, d + 0.5))
	for s in [-1.0, 1.0]:
		_box(b, c + Vector3(0, top + 0.85, s * (d * 0.5)), Vector3(w + 0.5, 0.9, 0.28), wall)
		_box(b, c + Vector3(s * (w * 0.5), top + 0.85, 0), Vector3(0.28, 0.9, d + 0.5), wall)
	# roof clutter
	for i in rng.randi_range(1, 3):
		var ap := c + Vector3(rng.randf_range(-w * 0.3, w * 0.3), top + 1.1, rng.randf_range(-d * 0.3, d * 0.3))
		_box(b, ap, Vector3(rng.randf_range(1.2, 2.4), 0.9, rng.randf_range(1.2, 2.4)), CityConfig.C_METAL)
	# rooftop sign
	if rng.randf() < 0.55:
		var sh := rng.randf_range(2.2, 3.4)
		b.box(GLOW, c + Vector3(0, top + 1.2 + sh * 0.5, -d * 0.18), Vector3(w * 0.55, sh, 0.25), neon)
		for s in [-1.0, 1.0]:
			_box(b, c + Vector3(s * w * 0.22, top + 1.0, -d * 0.18), Vector3(0.2, 1.4, 0.2), CityConfig.C_METAL_D)
	# antenna
	if rng.randf() < 0.4:
		b.cylinder(SOLID, c + Vector3(w * 0.3, top, d * 0.3), 0.1, 0.05, rng.randf_range(3.0, 6.0), 5, CityConfig.C_METAL)
		b.box(GLOW, c + Vector3(w * 0.3, top + 5.6, d * 0.3), Vector3(0.35, 0.35, 0.35), CityConfig.C_GLOW_RED)

# ============================================================== PARK

static func _park(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	b.plate(SOLID, o, Vector2(g, g), CityConfig.C_GRASS, 0.16)
	# crossing paths
	_box(b, o + Vector3(0, 0.05, 0), Vector3(g, 0.12, 4.0), CityConfig.C_CONCRETE)
	_box(b, o + Vector3(0, 0.05, 0), Vector3(4.0, 0.12, g), CityConfig.C_CONCRETE)
	# fountain in the middle
	var fc := o + Vector3(0, 0.1, 0)
	b.cylinder(SOLID, fc, 6.0, 6.0, 0.8, 12, CityConfig.C_CONCRETE)
	b.cylinder(SOLID, fc + Vector3(0, 0.8, 0), 5.5, 5.5, 0.06, 12, Color("5fb4d0"))
	b.cylinder(SOLID, fc + Vector3(0, 0.8, 0), 0.7, 0.5, 2.2, 8, CityConfig.C_CONCRETE)
	b.cylinder(SOLID, fc + Vector3(0, 3.0, 0), 1.6, 0.2, 0.5, 8, CityConfig.C_CONCRETE)
	b.box(GLOW, fc + Vector3(0, 3.4, 0), Vector3(0.3, 0.5, 0.3), CityConfig.C_GLOW_GLASS)
	# pond
	var pc := o + Vector3(-half * 0.55, 0.06, half * 0.5)
	b.cylinder(SOLID, pc, 7.6, 7.4, 0.3, 14, CityConfig.C_CONCRETE_D)
	b.cylinder(SOLID, pc + Vector3(0, 0.31, 0), 7.1, 7.1, 0.04, 14, Color("3f8fb0"))
	# trees
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(9.0, half - 2.0)
		var tp := o + Vector3(cos(a) * r, 0, sin(a) * r)
		if tp.distance_to(pc) < 9.5 or tp.distance_to(fc) < 8.0:
			continue
		if absf(tp.x - o.x) < 3.5 or absf(tp.z - o.z) < 3.5:
			continue
		tree(b, tp, rng.randf_range(0.75, 1.35), rng)
	# benches + lamps
	for i in 6:
		var a := TAU * float(i) / 6.0
		_bench(b, o + Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), Vector3(-cos(a), 0, -sin(a)))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		streetlight(b, o + Vector3(cos(a) * (half - 2.0), 0, sin(a) * (half - 2.0)), Vector3(-cos(a), 0, -sin(a)))
	# shrubs
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(11.0, half - 3.0)
		_bush(b, o + Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.8, 1.4), rng)

static func _bush(b: MeshBatch, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var col: Color = _pick(rng, [CityConfig.C_LEAF1, CityConfig.C_LEAF2, CityConfig.C_LEAF3])
	b.pyramid(SOLID, p, Vector2(1.8, 1.8) * s, 1.1 * s, col)
	b.pyramid(SOLID, p + Vector3(0.5 * s, 0, 0.3 * s), Vector2(1.2, 1.2) * s, 0.9 * s, col.lightened(0.06))

# ============================================================== SCHOOL

static func _school(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# asphalt playground on the front half
	_box(b, o + Vector3(0, 0.04, half * 0.42), Vector3(g - 2.0, 0.1, half * 1.0), Color("8a5a4a"))
	_box(b, o + Vector3(0, 0.09, half * 0.42), Vector3(g - 6.0, 0.02, half * 0.8), Color("b0705c"))
	for i in 4:
		_box(b, o + Vector3(-half * 0.5 + float(i) * half * 0.33, 0.11, half * 0.42),
			Vector3(0.2, 0.02, half * 0.8), CityConfig.C_LINE)
	# main building (3 floors) at the back
	var c := o + Vector3(0, 0, -half * 0.45)
	var w := g - 6.0
	var d := 15.0
	var floors := 3
	var fh := 3.6
	var wall := Color("c9a98c")
	var trim := Color("f0e9dc")
	_box(b, c + Vector3(0, 0.3, 0), Vector3(w + 1.0, 0.6, d + 1.0), CityConfig.C_CONCRETE_D)
	for f in floors:
		var y := 0.6 + float(f) * fh
		_box(b, c + Vector3(0, y + fh * 0.5, 0), Vector3(w, fh, d), wall, wall)
		_box(b, c + Vector3(0, y + fh - 0.12, 0), Vector3(w + 0.3, 0.24, d + 0.3), trim)
		for s in [-1.0, 1.0]:
			for i in 7:
				var wx := (float(i) / 6.0 - 0.5) * w * 0.9
				_window(b, c + Vector3(wx, y + fh * 0.55, s * (d * 0.5)), Vector3(0, 0, s),
					1.7, 1.9, trim, CityConfig.C_GLOW_GLASS)
	var top := 0.6 + float(floors) * fh
	_box(b, c + Vector3(0, top + 0.2, 0), Vector3(w + 0.8, 0.4, d + 0.8), CityConfig.C_ROOF_C)
	for s in [-1.0, 1.0]:
		_box(b, c + Vector3(0, top + 0.8, s * (d * 0.5 + 0.2)), Vector3(w + 0.8, 0.9, 0.3), trim)
	# central entrance block + clock + flag
	var e := c + Vector3(0, 0, d * 0.5)
	_box(b, e + Vector3(0, 3.4, 1.2), Vector3(14.0, 6.8, 3.2), trim)
	_box(b, e + Vector3(0, 6.9, 1.2), Vector3(15.0, 0.5, 4.0), CityConfig.C_ROOF_C)
	b.box(GLASS, e + Vector3(0, 2.0, 2.9), Vector3(9.0, 3.2, 0.2), Color("9fd3e4"))
	for i in 4:
		_box(b, e + Vector3(-6.0 + float(i) * 4.0, 2.3, 3.4), Vector3(0.45, 5.0, 0.45), trim)
	b.cylinder(SOLID, e + Vector3(0, 7.15, 1.2), 1.5, 1.5, 0.35, 12, trim, Vector3(0, 0, 1))
	b.cylinder(SOLID, e + Vector3(0, 7.15, 1.4), 1.25, 1.25, 0.12, 12, CityConfig.C_DARK, Vector3(0, 0, 1))
	# flag pole with tricolour
	var fp := o + Vector3(-half * 0.72, 0, -half * 0.30)
	b.cylinder(SOLID, fp, 0.12, 0.1, 11.0, 6, CityConfig.C_METAL)
	for i in 3:
		var fc: Color = [Color("ff9933"), Color("ffffff"), Color("138808")][i]
		_box(b, fp + Vector3(1.6, 9.6 - float(i) * 0.55, 0), Vector3(3.0, 0.55, 0.08), fc)
	# gate + fence around the plot
	_fence_ring(b, o + Vector3(0, 0, half * 0.5), g - 1.0, -1.0)
	_add_col(cols, c + Vector3(0, top * 0.5 + 0.3, 0), Vector3(w, top, d))
	_add_col(cols, e + Vector3(0, 3.4, 1.2), Vector3(14.0, 6.8, 3.2))
	# hoops
	for s in [-1.0, 1.0]:
		var hp := o + Vector3(s * half * 0.62, 0, half * 0.5)
		b.cylinder(SOLID, hp, 0.14, 0.14, 3.4, 6, CityConfig.C_METAL_D)
		b.cylinder(SOLID, hp + Vector3(0, 3.4, 0), 0.14, 0.14, 1.4, 6, CityConfig.C_METAL_D, Vector3(-s, 0, 0))
		_box(b, hp + Vector3(-s * 1.4, 3.6, 0), Vector3(0.1, 1.0, 1.8), trim)
		b.cylinder(SOLID, hp + Vector3(-s * 1.4, 3.5, 0.5), 0.35, 0.35, 0.06, 10, Color("e2622a"), Vector3(0, 0, 1))
	# school bus
	_bus(b, o + Vector3(half * 0.45, 0, half * 0.78), Vector3(-1, 0, 0), Color("f0b21c"), rng)

# ============================================================== POLICE

static func _police(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var c := o + Vector3(0, 0, -half * 0.36)
	var w := g - 8.0
	var d := 18.0
	var fh := 3.8
	var floors := 2
	var wall := Color("dfe4e8")
	var trim := Color("f4f6f7")
	_box(b, c + Vector3(0, 0.3, 0), Vector3(w + 1.0, 0.6, d + 1.0), CityConfig.C_CONCRETE_D)
	for f in floors:
		var y := 0.6 + float(f) * fh
		_box(b, c + Vector3(0, y + fh * 0.5, 0), Vector3(w, fh, d), wall, wall)
		_box(b, c + Vector3(0, y + fh - 0.1, 0), Vector3(w + 0.3, 0.2, d + 0.3), CityConfig.C_POLICE)
		for s in [-1.0, 1.0]:
			for i in 6:
				var wx := (float(i) / 5.0 - 0.5) * w * 0.86
				_window(b, c + Vector3(wx, y + fh * 0.55, s * (d * 0.5)), Vector3(0, 0, s),
					1.7, 1.8, trim, CityConfig.C_GLOW_GLASS)
	var top := 0.6 + float(floors) * fh
	_box(b, c + Vector3(0, top + 0.22, 0), Vector3(w + 0.8, 0.44, d + 0.8), CityConfig.C_ROOF_C)
	for s in [-1.0, 1.0]:
		_box(b, c + Vector3(0, top + 0.8, s * (d * 0.5 + 0.2)), Vector3(w + 0.8, 0.8, 0.3), trim)
	# entrance canopy with blue glow
	var e := c + Vector3(0, 0, d * 0.5)
	b.box(GLASS, e + Vector3(0, 1.9, 0.05), Vector3(10.0, 3.0, 0.14), Color("9fd3e4"))
	_box(b, e + Vector3(0, 3.8, 1.1), Vector3(12.0, 0.4, 2.6), trim)
	for s in [-1.0, 1.0]:
		_box(b, e + Vector3(s * 5.2, 1.9, 2.0), Vector3(0.35, 3.8, 0.35), trim)
	# sign board
	b.box(GLOW, e + Vector3(0, top - 0.6, 0.2), Vector3(w * 0.45, 1.4, 0.2), CityConfig.C_POLICE)
	b.box(GLOW, e + Vector3(0, top - 0.6, 0.32), Vector3(w * 0.42, 0.5, 0.1), Color("ffffff"))
	# roof mast with beacon
	b.cylinder(SOLID, c + Vector3(w * 0.3, top, -d * 0.2), 0.12, 0.08, 6.0, 5, CityConfig.C_METAL)
	b.box(GLOW, c + Vector3(w * 0.3, top + 6.1, -d * 0.2), Vector3(0.5, 0.5, 0.5), CityConfig.C_GLOW_RED)
	# parking area with markings + police cruisers
	var lot := o + Vector3(0, 0.02, half * 0.45)
	_box(b, lot, Vector3(g - 4.0, 0.1, half * 0.9), CityConfig.C_ASPHALT.lightened(0.05))
	for i in 5:
		_box(b, lot + Vector3(-g * 0.4 + float(i) * 5.0, 0.08, 0), Vector3(0.18, 0.02, half * 0.7), CityConfig.C_LINE)
	for i in 2:
		_car(b, lot + Vector3(-6.0 + float(i) * 5.0, 0.12, 3.0), Vector3(0, 0, 1), Color("f2f4f7"), true)
	# barrier + fence
	for i in 3:
		_box(b, o + Vector3(-half * 0.5 + float(i) * 2.6, 0.5, half - 2.0), Vector3(0.2, 1.0, 0.2), Color("d94f4f"))
		_box(b, o + Vector3(-half * 0.5 + float(i) * 2.6, 0.9, half - 2.0), Vector3(2.4, 0.16, 0.12), Color("ffffff"))
	_fence_ring(b, o + Vector3(0, 0, half * 0.4), g - 1.0, 1.0)
	for i in 4:
		tree(b, o + Vector3(-half + 4.0 + float(i) * 3.0, 0, -half + 4.0), rng.randf_range(0.8, 1.1), rng)
	_add_col(cols, c + Vector3(0, top * 0.5, 0), Vector3(w, top, d))

# ============================================================== HOSPITAL

static func _hospital(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var c := o + Vector3(0, 0, -half * 0.3)
	var w := g - 4.0
	var d := 22.0
	var fh := 3.5
	var floors := 5
	var wall := CityConfig.C_HOSPITAL
	var trim := Color("dfe7ec")
	_box(b, c + Vector3(0, 0.3, 0), Vector3(w + 1.6, 0.6, d + 1.6), CityConfig.C_CONCRETE_D)
	for f in floors:
		var y := 0.6 + float(f) * fh
		_box(b, c + Vector3(0, y + fh * 0.5, 0), Vector3(w, fh, d), wall, wall)
		for s in [-1.0, 1.0]:
			b.box(GLASS, c + Vector3(0, y + fh * 0.55, s * (d * 0.5 + 0.04)), Vector3(w * 0.92, fh * 0.44, 0.1), Color("8fc4d8"))
			_box(b, c + Vector3(0, y + fh, 0), Vector3(w + 0.4, 0.22, d + 0.4), trim)
		for s in [-1.0, 1.0]:
			b.box(GLASS, c + Vector3(s * (w * 0.5 + 0.04), y + fh * 0.55, 0), Vector3(0.1, fh * 0.44, d * 0.9), Color("8fc4d8"))
	var top := 0.6 + float(floors) * fh
	_box(b, c + Vector3(0, top + 0.24, 0), Vector3(w + 1.0, 0.48, d + 1.0), CityConfig.C_ROOF_C)
	# helipad on the roof
	var hp := c + Vector3(0, top + 0.55, 0)
	b.cylinder(SOLID, hp, 7.0, 7.0, 0.12, 16, Color("3a3f45"))
	b.cylinder(SOLID, hp + Vector3(0, 0.13, 0), 6.2, 6.2, 0.04, 16, Color("4a5057"))
	for s in [-1.0, 1.0]:
		_box(b, hp + Vector3(s * 1.3, 0.2, 0), Vector3(1.0, 0.05, 4.4), Color("ffffff"))
	_box(b, hp + Vector3(0, 0.2, 0), Vector3(3.4, 0.05, 1.0), Color("ffffff"))
	# red cross on the facade + tower
	b.box(GLOW, c + Vector3(0, top - 2.6, d * 0.5 + 0.3), Vector3(4.2, 1.2, 0.3), CityConfig.C_GLOW_RED)
	b.box(GLOW, c + Vector3(0, top - 2.6, d * 0.5 + 0.3), Vector3(1.2, 4.2, 0.3), CityConfig.C_GLOW_RED)
	# entrance with ambulance canopy
	var e := c + Vector3(0, 0, d * 0.5)
	b.box(GLASS, e + Vector3(0, 1.9, 0.06), Vector3(12.0, 3.2, 0.14), Color("a8dbea"))
	_box(b, e + Vector3(0, 4.2, 2.4), Vector3(16.0, 0.4, 5.0), trim)
	for s in [-1.0, 1.0]:
		_box(b, e + Vector3(s * 7.0, 2.1, 4.4), Vector3(0.4, 4.2, 0.4), trim)
	b.box(GLOW, e + Vector3(0, 4.7, 4.8), Vector3(10.0, 0.6, 0.2), CityConfig.C_GLOW_RED)
	# parking + ambulances
	var lot := o + Vector3(0, 0.02, half * 0.62)
	_box(b, lot, Vector3(g - 4.0, 0.1, half * 0.62), CityConfig.C_ASPHALT.lightened(0.05))
	for i in 5:
		_box(b, lot + Vector3(-g * 0.38 + float(i) * 5.0, 0.08, 0), Vector3(0.18, 0.02, half * 0.5), CityConfig.C_LINE)
	for i in 2:
		_bus(b, lot + Vector3(-8.0 + float(i) * 8.0, 0.12, 2.0), Vector3(1, 0, 0), Color("f7f9fa"), rng, true)
	for i in 6:
		tree(b, o + Vector3(-half + 4.0 + float(i) * 5.5, 0, half - 3.0), rng.randf_range(0.8, 1.2), rng)
	_add_col(cols, c + Vector3(0, top * 0.5, 0), Vector3(w, top, d))

# ============================================================== CLUB

static func _club(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var c := o + Vector3(0, 0, -half * 0.30)
	var w := g - 12.0
	var d := 20.0
	var fh := 4.0
	var top := 0.5 + fh * 2.0
	var neon_a := CityConfig.C_GLOW_NEON_P
	var neon_b := CityConfig.C_GLOW_NEON_C
	_box(b, c + Vector3(0, 0.25, 0), Vector3(w + 1.4, 0.5, d + 1.4), CityConfig.C_CONCRETE_D)
	_box(b, c + Vector3(0, 0.5 + fh, 0), Vector3(w, fh * 2.0, d), Color("2a2233"), Color("241d2c"))
	# dark glass facade with neon frame
	b.box(GLASS, c + Vector3(0, 2.4, d * 0.5 + 0.05), Vector3(w * 0.8, 3.2, 0.12), Color("5b3f78"))
	b.box(GLOW, c + Vector3(0, 6.0, d * 0.5 + 0.05), Vector3(w * 0.92, 0.35, 0.14), neon_a)
	b.box(GLOW, c + Vector3(0, top - 0.3, d * 0.5 + 0.05), Vector3(w * 0.92, 0.35, 0.14), neon_b)
	for s in [-1.0, 1.0]:
		b.box(GLOW, c + Vector3(s * (w * 0.5 + 0.04), 4.2, 0), Vector3(0.14, 6.0, d * 0.9), neon_b if s > 0.0 else neon_a)
		b.box(GLOW, c + Vector3(s * (w * 0.5 + 0.04), 8.4, 0), Vector3(0.14, 0.4, d), Color("ffffff"))
	# rooftop sign
	var sh := 4.2
	b.box(GLOW, c + Vector3(-w * 0.18, top + 0.4 + sh * 0.5, 0), Vector3(w * 0.22, sh, 0.4), neon_a)
	b.box(GLOW, c + Vector3(w * 0.18, top + 0.4 + sh * 0.5, 0), Vector3(w * 0.22, sh, 0.4), neon_b)
	for s in [-1.0, 1.0]:
		_box(b, c + Vector3(s * w * 0.3, top + 0.8, 0), Vector3(0.2, 1.6, 0.2), CityConfig.C_METAL_D)
	# roof terrace with rail
	_box(b, c + Vector3(0, top + 0.2, 0), Vector3(w + 0.6, 0.4, d + 0.6), Color("3a3040"))
	for s in [-1.0, 1.0]:
		_box(b, c + Vector3(0, top + 0.75, s * (d * 0.5 + 0.2)), Vector3(w + 0.6, 0.6, 0.18), Color("5c5266"))
	# entrance: red carpet, ropes, columns
	var e := c + Vector3(0, 0, d * 0.5)
	_box(b, e + Vector3(0, 0.06, 3.2), Vector3(4.0, 0.14, 7.0), Color("9c1b2f"))
	_box(b, e + Vector3(0, 0.24, 6.9), Vector3(6.0, 0.3, 1.0), Color("9c1b2f"))
	for s in [-1.0, 1.0]:
		for i in 3:
			_box(b, e + Vector3(s * 3.2, 0.55, 1.0 + float(i) * 2.4), Vector3(0.2, 1.1, 0.2), Color("c9a227"))
		_box(b, e + Vector3(s * 3.2, 0.95, 3.4), Vector3(0.1, 0.1, 5.0), Color("8a1b2a"))
	# speakers + lights on the pavement
	for s in [-1.0, 1.0]:
		_box(b, e + Vector3(s * 6.5, 0.8, 3.0), Vector3(1.0, 1.6, 1.0), CityConfig.C_DARK)
		b.box(GLOW, e + Vector3(s * 6.5, 1.35, 3.55), Vector3(0.7, 0.25, 0.1), neon_a)
	# neon palm-ish decorations
	for s in [-1.0, 1.0]:
		var dp := o + Vector3(s * (half - 3.0), 0, half - 4.0)
		b.cylinder(SOLID, dp, 0.22, 0.18, 5.5, 6, CityConfig.C_METAL_D)
		for i in 5:
			var a := TAU * float(i) / 5.0
			b.box(GLOW, dp + Vector3(cos(a) * 1.2, 5.5, sin(a) * 1.2), Vector3(0.14, 0.14, 2.1), neon_b)
		b.box(GLOW, dp + Vector3(0, 5.8, 0), Vector3(0.42, 0.42, 0.42), neon_a)
	# queue barrier + parked sports car
	_car(b, o + Vector3(half * 0.55, 0.06, half * 0.62), Vector3(-1, 0, 0), Color("d91e4a"), false)
	tree(b, o + Vector3(-half + 5.0, 0, -half + 5.0), 1.0, rng)
	_add_col(cols, c + Vector3(0, top * 0.5, 0), Vector3(w, top, d))

# ============================================================== LOT / PLAZA

static func _parking_lot(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	_box(b, o + Vector3(0, 0.03, 0), Vector3(g, 0.08, g), CityConfig.C_ASPHALT.lightened(0.04))
	var rows := 2
	for r in rows:
		var z := o.z - g * 0.5 + 9.0 + float(r) * (g / float(rows) - 2.0)
		for i in 8:
			var x := o.x - g * 0.5 + 4.0 + float(i) * 6.5
			_box(b, Vector3(x, o.y + 0.07, z), Vector3(0.16, 0.02, 5.4), CityConfig.C_LINE)
			if rng.randf() < 0.42:
				var col: Color = _pick(rng, [Color("d6d9dc"), Color("2b4b8f"), Color("b8332f"),
					Color("2f7a4a"), Color("e8c33a"), Color("1f2126"), Color("8f4ac0")])
				_car(b, Vector3(x + 3.2, o.y + 0.1, z), Vector3(0, 0, 1), col, false)
	for i in 4:
		streetlight(b, o + Vector3(-g * 0.45 + float(i) * g * 0.3, 0, -g * 0.5 + 1.5), Vector3(0, 0, 1))
	tree(b, o + Vector3(g * 0.5 - 2.0, 0, g * 0.5 - 2.0), 1.0, rng)

static func _plaza(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	b.plate(SOLID, o, Vector2(g, g), CityConfig.C_CONCRETE, 0.16)
	b.cylinder(SOLID, o + Vector3(0, 0.06, 0), 13.0, 13.0, 0.06, 20, CityConfig.C_CONCRETE_D)
	# statue on a plinth
	var sp := o + Vector3(0, 0.12, 0)
	b.cylinder(SOLID, sp, 3.4, 3.0, 1.4, 10, CityConfig.C_CONCRETE)
	_box(b, sp + Vector3(0, 1.4, 0), Vector3(3.0, 1.6, 3.0), CityConfig.C_CONCRETE_D)
	var fg := sp + Vector3(0, 3.0, 0)
	_box(b, fg + Vector3(0, 1.4, 0), Vector3(1.5, 2.8, 1.0), Color("5f6b73"))
	_box(b, fg + Vector3(0, 3.2, 0), Vector3(1.0, 1.0, 0.9), Color("6f7b83"))
	_box(b, fg + Vector3(0.8, 3.6, 0), Vector3(0.3, 2.2, 0.3), Color("6f7b83"))
	_add_col(cols, sp + Vector3(0, 2.5, 0), Vector3(3.4, 5.0, 3.4))
	# fountain ring + benches + trees
	for i in 8:
		var a := TAU * float(i) / 8.0
		_bench(b, o + Vector3(cos(a) * 15.0, 0, sin(a) * 15.0), Vector3(-cos(a), 0, -sin(a)))
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI * 0.25
		tree(b, o + Vector3(cos(a) * 22.0, 0, sin(a) * 22.0), rng.randf_range(0.9, 1.3), rng)
	for i in 4:
		streetlight(b, o + Vector3(-22.0 + float(i) * 14.5, 0, -25.0), Vector3(0, 0, 1))

# ============================================================== INDUSTRIAL

static func _up_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		n = -n
	if n.length_squared() < 1e-9:
		return Vector3.UP
	return n.normalized()

static func _factory(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	b.plate(SOLID, o, Vector2(g, g), Color("7a7c78"), 0.16)
	for i in 3:
		_box(b, o + Vector3(-18.0 + float(i) * 18.0, 0.19, half * 0.66),
			Vector3(0.34, 0.05, half * 0.62), CityConfig.C_IND_YEL)
	# ---- main shed ----
	var c := o + Vector3(0, 0, -7.0)
	var w := 44.0
	var d := 20.0
	var h := 11.0
	var wall: Color = CityConfig.C_IND_WALL
	_box(b, c + Vector3(0, 0.3, 0), Vector3(w + 1.4, 0.6, d + 1.4), CityConfig.C_CONCRETE_D)
	_box(b, c + Vector3(0, h * 0.5 + 0.6, 0), Vector3(w, h, d), wall, wall.darkened(0.08))
	var ribs := 16
	for i in ribs:
		var rx := -w * 0.5 + float(i) * (w / float(ribs - 1))
		_box(b, c + Vector3(rx, h * 0.5 + 0.6, d * 0.5 + 0.07), Vector3(0.14, h, 0.14), wall.darkened(0.2))
		_box(b, c + Vector3(rx, h * 0.5 + 0.6, -d * 0.5 - 0.07), Vector3(0.14, h, 0.14), wall.darkened(0.2))
	_box(b, c + Vector3(0, h + 0.85, 0), Vector3(w + 0.6, 0.5, d + 0.6), wall.darkened(0.25))
	for i in 4:
		var sx := -w * 0.33 + float(i) * (w * 0.66 / 3.0)
		_box(b, c + Vector3(sx, h + 1.5, 0), Vector3(1.9, 0.5, d * 0.92), wall.darkened(0.15))
		b.box(GLASS, c + Vector3(sx - 1.0, h + 1.8, 0), Vector3(0.1, 0.9, d * 0.88), Color("a8ccd8"))
		b.box(GLASS, c + Vector3(sx + 1.0, h + 1.8, 0), Vector3(0.1, 0.9, d * 0.88), Color("a8ccd8"))
	for i in 3:
		var dx := -13.0 + float(i) * 13.0
		_box(b, c + Vector3(dx, 3.6, d * 0.5 + 0.12), Vector3(7.4, 6.6, 0.32), Color("c2b84e"))
		_box(b, c + Vector3(dx, 3.6, d * 0.5 + 0.2), Vector3(6.8, 6.0, 0.3), Color("8f8838"))
		for k in 5:
			_box(b, c + Vector3(dx, 1.0 + float(k) * 1.3, d * 0.5 + 0.28), Vector3(6.8, 0.12, 0.06), Color("6f6a2a"))
	for i in 8:
		var wx := -w * 0.42 + float(i) * (w * 0.84 / 7.0)
		b.box(GLASS, c + Vector3(wx, h - 1.9, d * 0.5 + 0.1), Vector3(2.2, 1.5, 0.12), Color("7fa8bc"))
	_add_col(cols, c + Vector3(0, (h + 2.0) * 0.5 + 0.4, 0), Vector3(w + 1.4, h + 2.0, d + 1.4))
	# ---- chimneys ----
	for i in 2:
		var cb := c + Vector3(-15.0 + float(i) * 8.0, 0.0, -d * 0.5 - 4.0)
		b.cylinder(SOLID, cb, 2.6, 1.7, 26.0, 10, Color("b8b2a6"))
		for k in 3:
			b.cylinder(SOLID, cb + Vector3(0, 16.0 + float(k) * 2.8, 0),
				2.0 - float(k) * 0.1, 1.95 - float(k) * 0.1, 1.2, 10, CityConfig.C_RUST)
		b.box(GLOW, cb + Vector3(0, 26.5, 0), Vector3(1.4, 0.7, 1.4), CityConfig.C_GLOW_RED)
		_add_col(cols, cb + Vector3(0, 13.0, 0), Vector3(5.2, 26.0, 5.2))
	# ---- silos ----
	for i in 3:
		var sp := o + Vector3(half - 13.0 + float(i) * 6.6, 0, -half + 9.0)
		b.cylinder(SOLID, sp, 3.0, 3.0, 12.0, 12, Color("c8ccc8"))
		for k in 3:
			b.cylinder(SOLID, sp + Vector3(0, 2.5 + float(k) * 4.0, 0), 3.06, 3.06, 0.34, 12, Color("9aa0a0"))
		b.cylinder(SOLID, sp + Vector3(0, 12.0, 0), 3.0, 0.45, 3.2, 12, Color("b0b6b2"))
		_add_col(cols, sp + Vector3(0, 7.0, 0), Vector3(6.0, 15.2, 6.0))
		if i > 0:
			b.cylinder(SOLID, sp - Vector3(3.3, -8.5, 0), 0.45, 0.45, 7.0, 6,
				CityConfig.C_METAL_D, Vector3(1, 0, 0))
	# ---- cooling tower ----
	var ct := o + Vector3(-half + 12.0, 0, -half + 10.0)
	b.cylinder(SOLID, ct, 7.0, 5.0, 9.0, 14, Color("b4b8b2"))
	b.cylinder(SOLID, ct + Vector3(0, 9.0, 0), 5.0, 4.6, 5.5, 14, Color("a8aca6"))
	b.cylinder(SOLID, ct + Vector3(0, 14.5, 0), 4.6, 4.0, 0.6, 14, Color("9aa09a"))
	_add_col(cols, ct + Vector3(0, 7.5, 0), Vector3(14.0, 15.0, 14.0))
	# ---- containers ----
	for i in 5:
		var cp := o + Vector3(-half + 6.0 + float(i) * 8.5, 0, half * 0.42)
		var cc: Color = CityConfig.C_CONTAINER[rng.randi_range(0, 4)]
		_box(b, cp + Vector3(0, 1.4, 0), Vector3(7.0, 2.8, 3.0), cc)
		_box(b, cp + Vector3(0, 1.4, 0), Vector3(7.06, 0.4, 3.06), cc.darkened(0.25))
		if rng.randf() < 0.5:
			var cc2: Color = CityConfig.C_CONTAINER[rng.randi_range(0, 4)]
			_box(b, cp + Vector3(0, 4.2, 0), Vector3(7.0, 2.8, 3.0), cc2)
			_add_col(cols, cp + Vector3(0, 2.8, 0), Vector3(7.0, 5.6, 3.0))
		else:
			_add_col(cols, cp + Vector3(0, 1.4, 0), Vector3(7.0, 2.8, 3.0))
	# ---- floodlights + truck + fence ----
	for i in 2:
		var fl := o + Vector3(-half + 4.0 + float(i) * (g - 8.0), 0, half * 0.86)
		b.cylinder(SOLID, fl, 0.22, 0.16, 12.0, 6, CityConfig.C_METAL_D)
		_box(b, fl + Vector3(0, 12.2, -1.0), Vector3(2.6, 1.4, 0.4), CityConfig.C_METAL_D)
		b.box(GLOW, fl + Vector3(0, 12.2, -1.25), Vector3(2.4, 1.2, 0.1), Color("fff2c8"))
	_car(b, o + Vector3(-6.0, 0.18, half * 0.72), Vector3(1, 0, 0), Color("c8562f"), false)
	_bus(b, o + Vector3(8.0, 0.18, half * 0.74), Vector3(-1, 0, 0), Color("4a6f8a"), rng)
	for i in 4:
		tree(b, o + Vector3(-half + 3.0, 0, -half + 4.0 + float(i) * 3.0), rng.randf_range(0.8, 1.05), rng)

static func _warehouse(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	b.plate(SOLID, o, Vector2(g, g), Color("6f7170"), 0.16)
	var c := o + Vector3(0, 0, -6.0)
	var w := 46.0
	var d := 24.0
	var h := 9.5
	var wall: Color = CityConfig.C_SHED_BLUE
	_box(b, c + Vector3(0, 0.3, 0), Vector3(w + 1.2, 0.6, d + 1.2), CityConfig.C_CONCRETE_D)
	_box(b, c + Vector3(0, h * 0.5 + 0.6, 0), Vector3(w, h, d), wall, wall.darkened(0.12))
	var ribs := 12
	for i in ribs:
		var rx := -w * 0.5 + float(i) * (w / float(ribs - 1))
		_box(b, c + Vector3(rx, h * 0.5 + 0.6, d * 0.5 + 0.08), Vector3(0.16, h, 0.14), wall.darkened(0.25))
	_box(b, c + Vector3(0, h + 0.8, 0), Vector3(w + 1.0, 0.4, d + 1.0), Color("8b9298"))
	for i in 3:
		var dx := -14.0 + float(i) * 14.0
		_box(b, c + Vector3(dx, 4.2, d * 0.5 + 0.12), Vector3(8.0, 7.0, 0.3), Color("9aa0a4"))
		for k in 6:
			_box(b, c + Vector3(dx, 1.2 + float(k) * 1.15, d * 0.5 + 0.24), Vector3(7.4, 0.1, 0.06), Color("7b8185"))
		# dock platform
		_box(b, c + Vector3(dx, 0.6, d * 0.5 + 1.8), Vector3(9.0, 1.2, 3.2), CityConfig.C_CONCRETE)
		b.box(GLOW, c + Vector3(dx, 8.2, d * 0.5 + 0.3), Vector3(7.6, 0.5, 0.12), Color("ffd98a"))
	# office block on the side
	var oc := c + Vector3(w * 0.5 + 3.0, 0, d * 0.3)
	_box(b, oc + Vector3(0, 3.6, 0), Vector3(6.0, 7.2, 8.0), Color("d8d4c8"))
	for i in 2:
		b.box(GLASS, oc + Vector3(3.05, 2.0 + float(i) * 3.0, 0), Vector3(0.1, 1.6, 6.0), Color("7fa8bc"))
	_add_col(cols, c + Vector3(0, (h + 1.4) * 0.5 + 0.4, 0), Vector3(w + 1.2, h + 1.4, d + 1.2))
	_add_col(cols, oc + Vector3(0, 3.6, 0), Vector3(6.0, 7.2, 8.0))
	# containers + truck + pallets
	for i in 3:
		var cp := o + Vector3(-half + 5.0 + float(i) * 4.0, 0, half * 0.62)
		var cc: Color = CityConfig.C_CONTAINER[rng.randi_range(0, 4)]
		_box(b, cp + Vector3(0, 1.4, 0), Vector3(6.4, 2.8, 2.9), cc)
		_box(b, cp + Vector3(0, 4.2, 0), Vector3(6.4, 2.8, 2.9), cc.darkened(0.18))
		_add_col(cols, cp + Vector3(0, 2.8, 0), Vector3(6.4, 5.6, 2.9))
	_bus(b, o + Vector3(-4.0, 0.18, half * 0.8), Vector3(1, 0, 0), Color("d8dde2"), rng)
	for i in 4:
		var pp := o + Vector3(half - 8.0 + float(i) * 2.2, 0, half * 0.34)
		_box(b, pp + Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.6), CityConfig.C_WOOD)
	for i in 2:
		var fl := o + Vector3(-half + 6.0 + float(i) * (g - 12.0), 0, -half + 2.0)
		b.cylinder(SOLID, fl, 0.2, 0.14, 10.0, 6, CityConfig.C_METAL_D)
		_box(b, fl + Vector3(0, 10.2, 1.0), Vector3(2.4, 1.2, 0.4), CityConfig.C_METAL_D)
		b.box(GLOW, fl + Vector3(0, 10.2, 1.25), Vector3(2.2, 1.0, 0.1), Color("fff2c8"))

# ============================================================== CLOCK TOWER

static func _clocktower(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# old town square: stone paving with a circular pattern
	b.plate(SOLID, o, Vector2(g, g), CityConfig.C_STONE_D, 0.16)
	b.cylinder(SOLID, o + Vector3(0, 0.17, 0), 21.0, 21.0, 0.05, 28, CityConfig.C_STONE)
	b.cylinder(SOLID, o + Vector3(0, 0.19, 0), 18.0, 18.0, 0.04, 28, CityConfig.C_STONE_L)
	b.cylinder(SOLID, o + Vector3(0, 0.22, 0), 10.0, 10.0, 0.3, 4, CityConfig.C_STONE_D)
	# ---- tower ----
	var tb := o + Vector3(0, 0.5, 0)
	_box(b, tb + Vector3(0, 1.0, 0), Vector3(11.0, 2.0, 11.0), CityConfig.C_STONE_D)
	_box(b, tb + Vector3(0, 14.0, 0), Vector3(8.0, 24.0, 8.0), CityConfig.C_STONE, CityConfig.C_STONE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(b, tb + Vector3(sx * 4.1, 14.5, sz * 4.1), Vector3(1.5, 25.0, 1.5), CityConfig.C_STONE_D)
	for k in 4:
		_box(b, tb + Vector3(0, 4.0 + float(k) * 6.0, 0), Vector3(8.6, 0.5, 8.6), CityConfig.C_STONE_L)
	# arched windows low down
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		for k in 2:
			var wp := tb + d * 4.06 + Vector3(0, 5.0 + float(k) * 6.0, 0)
			b.box(GLASS, wp, Vector3(1.6 if absf(d.z) > 0.5 else 0.12, 2.4,
				0.12 if absf(d.z) > 0.5 else 1.6), Color("4a6b7a"))
	# ---- clock faces on all four sides ----
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var fc := tb + Vector3(0, 20.0, 0) + d * 4.1
		b.cylinder(SOLID, fc - d * 0.2, 3.3, 3.3, 0.4, 16, CityConfig.C_STONE_D, d)
		b.cylinder(SOLID, fc + d * 0.22, 2.9, 2.9, 0.16, 16, Color("f4f1e6"), d)
		# hands (glow so they read from a distance)
		var hand_v := Vector3(0.22, 2.2, 0.12) if absf(d.z) > 0.5 else Vector3(0.12, 2.2, 0.22)
		var hand_h := Vector3(1.6, 0.22, 0.12) if absf(d.z) > 0.5 else Vector3(0.12, 0.22, 1.6)
		b.box(GLOW, fc + d * 0.36 + Vector3(0, 0.9, 0), hand_v, Color("2b2b30"))
		b.box(GLOW, fc + d * 0.36 + Vector3(0 if absf(d.z) > 0.5 else 0.7, 0, 0.7 if absf(d.z) > 0.5 else 0), hand_h, Color("2b2b30"))
		b.box(GLOW, fc + d * 0.38, Vector3(0.3, 0.3, 0.3), CityConfig.C_GLOW_NEON_Y)
	# ---- belfry + spire ----
	_box(b, tb + Vector3(0, 26.6, 0), Vector3(9.2, 1.2, 9.2), CityConfig.C_STONE_L)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(b, tb + Vector3(sx * 3.8, 29.4, sz * 3.8), Vector3(1.1, 4.4, 1.1), CityConfig.C_STONE)
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		b.box(GLOW, tb + Vector3(0, 29.4, 0) + d * 3.5, Vector3(1.4, 2.6, 0.2) if absf(d.z) > 0.5 else Vector3(0.2, 2.6, 1.4), CityConfig.C_GLOW_WIN)
	_box(b, tb + Vector3(0, 32.0, 0), Vector3(9.4, 1.0, 9.4), CityConfig.C_STONE_L)
	b.cylinder(SOLID, tb + Vector3(0, 32.5, 0), 4.4, 0.2, 5.2, 12, Color("5f9a86"))
	b.cylinder(SOLID, tb + Vector3(0, 37.6, 0), 0.16, 0.1, 2.4, 6, CityConfig.C_METAL_D)
	b.box(GLOW, tb + Vector3(0, 40.1, 0), Vector3(0.5, 0.5, 0.5), CityConfig.C_GLOW_RED)
	_add_col(cols, tb + Vector3(0, 15.0, 0), Vector3(8.6, 30.0, 8.6))
	# ---- square dressing: old buildings around the edge ----
	for side in 4:
		for k in 2:
			var along := (-0.30 + 0.6 * float(k)) * g
			var off := 0.0
			var bp: Vector3
			if side < 2:
				bp = o + Vector3(along, 0, (half - 8.0) * (-1.0 if side == 0 else 1.0))
			else:
				bp = o + Vector3((half - 8.0) * (-1.0 if side == 2 else 1.0), 0, along)
			if rng.randf() < 0.45:
				continue
			var bw := 14.0
			var bd := 12.0
			var floors := rng.randi_range(2, 3)
			_oldhouse(b, rng, bp, bw, bd, floors, side)
			_add_col(cols, bp + Vector3(0, float(floors) * 3.4 * 0.5, 0), Vector3(bw, float(floors) * 3.4 + 2.0, bd))
	# fountain + benches + trees + lamps
	var fc2 := o + Vector3(0, 0, 0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		_bench(b, o + Vector3(cos(a) * 13.5, 0, sin(a) * 13.5), Vector3(-cos(a), 0, -sin(a)))
	for i in 8:
		var a2 := TAU * float(i) / 8.0 + PI * 0.25
		tree(b, o + Vector3(cos(a2) * 17.5, 0, sin(a2) * 17.5), rng.randf_range(0.9, 1.2), rng)
	for i in 4:
		var a3 := TAU * float(i) / 4.0
		streetlight(b, o + Vector3(cos(a3) * 21.0, 0, sin(a3) * 21.0), Vector3(-cos(a3), 0, -sin(a3)))

static func _oldhouse(b: MeshBatch, rng: RandomNumberGenerator, p: Vector3, w: float, d: float,
		floors: int, side: int) -> void:
	var wall: Color = [CityConfig.C_BRICK, Color("c8a878"), Color("b09070"), Color("d0c0a0")][rng.randi_range(0, 3)]
	var fh := 3.4
	for f in floors:
		var y := float(f) * fh
		_box(b, p + Vector3(0, y + fh * 0.5, 0), Vector3(w, fh, d), wall, wall)
		_box(b, p + Vector3(0, y + fh - 0.12, 0), Vector3(w + 0.3, 0.24, d + 0.3), CityConfig.C_STONE_L)
		for k in 3:
			var wx := (-0.30 + 0.3 * float(k)) * w
			_window(b, p + Vector3(wx, y + 1.8, d * 0.5), Vector3(0, 0, 1), 1.5, 1.8, CityConfig.C_STONE_L, Color("3c6b80"))
			_window(b, p + Vector3(wx, y + 1.8, -d * 0.5), Vector3(0, 0, -1), 1.5, 1.8, CityConfig.C_STONE_L, Color("3c6b80"))
	var top := float(floors) * fh
	b.gable(SOLID, p + Vector3(0, top, 0), w + 0.8, d + 0.8, 2.8, CityConfig.C_ROOF_A, CityConfig.C_ROOF_A.darkened(0.1))
	_box(b, p + Vector3(0, 0.3, 0), Vector3(w + 0.6, 0.6, d + 0.6), CityConfig.C_STONE_D)

# ============================================================== STADIUM

static func _stadium(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	b.plate(SOLID, o, Vector2(g, g), Color("9a9c98"), 0.16)
	# running track + pitch
	_box(b, o + Vector3(0, 0.2, 0), Vector3(48.0, 0.1, 30.0), Color("a0503c"))
	_box(b, o + Vector3(0, 0.230, 0), Vector3(40.0, 0.1, 23.0), CityConfig.C_FIELD)
	for i in 4:
		_box(b, o + Vector3(0, 0.24, -11.0 + float(i) * 7.3), Vector3(46.0, 0.03, 0.18), CityConfig.C_LINE)
	_box(b, o + Vector3(0, 0.24, 0), Vector3(46.0, 0.03, 0.18), CityConfig.C_LINE)
	_box(b, o + Vector3(0, 0.24, 0), Vector3(0.18, 0.03, 23.0), CityConfig.C_LINE)
	b.cylinder(SOLID, o + Vector3(0, 0.235, 0), 5.0, 5.0, 0.03, 20, Color("e8e6de"))
	b.cylinder(SOLID, o + Vector3(0, 0.238, 0), 4.6, 4.6, 0.03, 20, CityConfig.C_FIELD)
	# goals
	for s in [-1.0, 1.0]:
		_box(b, o + Vector3(s * 20.0, 1.4, 0), Vector3(0.3, 2.8, 7.3), Color("f0f0ee"))
	# stands: 4 sides x 4 tiers
	var tiers := 4
	for side in 4:
		for k in tiers:
			var depth := 2.9
			var hgt := 1.0 + float(k) * 1.35
			var off := 15.6 + float(k) * depth
			var size: Vector3
			var cpos: Vector3
			var colr: Color = Color("c8c4b8") if k % 2 == 0 else Color("8f9aa8")
			if side < 2:
				size = Vector3(50.0, hgt, depth)
				cpos = o + Vector3(0, hgt * 0.5 + 0.2, off * (-1.0 if side == 0 else 1.0))
			else:
				size = Vector3(depth, hgt, 34.0)
				cpos = o + Vector3(off * (-1.0 if side == 2 else 1.0), hgt * 0.5 + 0.2, 0)
			_box(b, cpos, size, colr, colr.lightened(0.05))
	# corner blocks
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(b, o + Vector3(sx * 22.0, 2.2, sz * 18.0), Vector3(12.0, 4.4, 12.0), Color("a8b0b8"))
	# roofs over the stands
	for side in 4:
		if side < 2:
			_box(b, o + Vector3(0, 12.0, 24.5 * (-1.0 if side == 0 else 1.0)), Vector3(52.0, 0.5, 9.0), Color("d8dde2"))
			for i in 5:
				var px := -20.0 + float(i) * 10.0
				_box(b, o + Vector3(px, 6.0, 27.5 * (-1.0 if side == 0 else 1.0)), Vector3(0.6, 12.0, 0.6), Color("b0b6bc"))
		else:
			_box(b, o + Vector3(27.0 * (-1.0 if side == 2 else 1.0), 12.0, 0), Vector3(9.0, 0.5, 36.0), Color("d8dde2"))
			for i in 4:
				var pz := -15.0 + float(i) * 10.0
				_box(b, o + Vector3(27.0 * (-1.0 if side == 2 else 1.0), 6.0, pz), Vector3(0.6, 12.0, 0.6), Color("b0b6bc"))
	_add_col(cols, o + Vector3(0, 6.0, 24.0), Vector3(52.0, 12.0, 12.0))
	_add_col(cols, o + Vector3(0, 6.0, -24.0), Vector3(52.0, 12.0, 12.0))
	_add_col(cols, o + Vector3(24.0, 6.0, 0), Vector3(12.0, 12.0, 36.0))
	_add_col(cols, o + Vector3(-24.0, 6.0, 0), Vector3(12.0, 12.0, 36.0))
	# floodlight pylons
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var fp := o + Vector3(sx * 25.0, 0, sz * 24.0)
			b.cylinder(SOLID, fp, 0.4, 0.25, 22.0, 8, CityConfig.C_METAL_D)
			_box(b, fp + Vector3(0, 22.6, 0), Vector3(3.2, 1.8, 0.5), CityConfig.C_METAL_D)
			b.box(GLOW, fp + Vector3(0, 22.6, 0) + Vector3(0, 0, -0.3), Vector3(3.0, 1.6, 0.1), Color("fff8dc"))

# ============================================================== PEAK / HILL

const PEAK_AMP := 27.0
const PEAK_R := 31.0

static func peak_height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var t := clampf(r / PEAK_R, 0.0, 1.0)
	var h := PEAK_AMP * (1.0 - smoothstep(0.22, 1.0, t))
	h += 1.7 * sin(x * 0.26) * cos(z * 0.23) * (1.0 - t)
	return maxf(h, 0.0)

static func _peak(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var n := 28
	var step := g / float(n)
	# ---- heightfield mesh ----
	for i in n:
		for j in n:
			var x0 := -half + float(i) * step
			var z0 := -half + float(j) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var h00 := peak_height(x0, z0)
			var h10 := peak_height(x1, z0)
			var h11 := peak_height(x1, z1)
			var h01 := peak_height(x0, z1)
			var p00 := o + Vector3(x0, h00, z0)
			var p10 := o + Vector3(x1, h10, z0)
			var p11 := o + Vector3(x1, h11, z1)
			var p01 := o + Vector3(x0, h01, z1)
			var hh := (h00 + h10 + h11 + h01) * 0.25
			var col := _peak_color(hh)
			b.quad(SOLID, p00, p10, p11, p01, col, _up_normal(p00, p10, p11))
	# ---- heightfield collider ----
	var n2 := 57
	var data := PackedFloat32Array()
	data.resize(n2 * n2)
	for i in n2:
		for j in n2:
			var x := -half + float(i)
			var z := -half + float(j)
			data[j * n2 + i] = peak_height(x, z)
	cols.append({"hm": data, "n": n2, "pos": o})
	# ---- summit lookout tower ----
	var top_y := peak_height(0, 0)
	var s := o + Vector3(0, top_y, 0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(b, s + Vector3(sx * 1.9, 3.0, sz * 1.9), Vector3(0.35, 6.0, 0.35), CityConfig.C_WOOD)
	_box(b, s + Vector3(0, 6.2, 0), Vector3(5.0, 0.4, 5.0), CityConfig.C_WOOD)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(b, s + Vector3(sx * 2.3, 7.6, sz * 2.3), Vector3(0.22, 2.6, 0.22), CityConfig.C_WOOD.darkened(0.1))
	# railing
	for k in 4:
		var a := TAU * float(k) / 4.0
		_box(b, s + Vector3(cos(a) * 2.3, 7.1, sin(a) * 2.3),
			Vector3(4.8 if k % 2 == 0 else 0.12, 0.12, 0.12 if k % 2 == 0 else 4.8), CityConfig.C_WOOD)
	b.pyramid(SOLID, s + Vector3(0, 8.8, 0), Vector2(5.6, 5.6), 2.2, CityConfig.C_ROOF_A)
	# ladder + flag
	for k in 5:
		_box(b, s + Vector3(0, 1.0 + float(k) * 1.1, 2.3), Vector3(1.0, 0.1, 0.1), CityConfig.C_WOOD.darkened(0.2))
	b.cylinder(SOLID, s + Vector3(2.6, 8.6, -2.6), 0.08, 0.06, 4.0, 5, CityConfig.C_METAL)
	_box(b, s + Vector3(3.9, 11.9, -2.6), Vector3(2.4, 1.2, 0.06), Color("e8562f"))
	_add_col(cols, s + Vector3(0, 4.4, 0), Vector3(5.4, 10.8, 5.4))
	# ---- pines on the slopes, rocks near the top ----
	for i in 26:
		var a2 := rng.randf() * TAU
		var r2 := rng.randf_range(14.0, half - 2.0)
		var px := cos(a2) * r2
		var pz := sin(a2) * r2
		tree(b, o + Vector3(px, peak_height(px, pz), pz), rng.randf_range(0.85, 1.3), rng)
	for i in 9:
		var a3 := rng.randf() * TAU
		var r3 := rng.randf_range(2.0, 11.0)
		var px2 := cos(a3) * r3
		var pz2 := sin(a3) * r3
		var rs := rng.randf_range(1.0, 2.6)
		var rp := o + Vector3(px2, peak_height(px2, pz2), pz2)
		b.pyramid(SOLID, rp + Vector3(0, -0.4, 0), Vector2(rs * 2.0, rs * 2.0), rs * 1.6, CityConfig.C_ROCK)
	_bush(b, o + Vector3(6.0, peak_height(6.0, 4.0), 4.0), 0.9, rng)

static func _peak_color(h: float) -> Color:
	# grass at the foot, scrub, bare rock, pale peak
	if h < 2.0:
		return CityConfig.C_GRASS
	if h < 9.0:
		return CityConfig.C_GRASS.lerp(Color("5f7a41"), (h - 2.0) / 7.0)
	if h < 16.0:
		return Color("5f7a41").lerp(Color("6d7a55"), (h - 9.0) / 7.0)
	if h < 22.0:
		return Color("6d7a55").lerp(CityConfig.C_ROCK, (h - 16.0) / 6.0)
	return CityConfig.C_ROCK.lerp(Color("c3ccd2"), (h - 22.0) / 6.0)

# ============================================================== GRAVEYARD

static func _graveyard(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	b.plate(SOLID, o, Vector2(g, g), CityConfig.C_DEAD_GRASS, 0.16)
	# gravel paths
	_box(b, o + Vector3(0, 0.18, 0), Vector3(g * 0.94, 0.05, 3.2), Color("6a6455"))
	_box(b, o + Vector3(0, 0.18, 0), Vector3(3.2, 0.05, g * 0.94), Color("6a6455"))
	# iron fence
	var fh := 1.6
	for side in 4:
		var along_x := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var cnt := 20
		for i in cnt + 1:
			var t := -half + float(i) * (half * 2.0 / float(cnt))
			var pp := o + (Vector3(t, 0, sgn * half) if along_x else Vector3(sgn * half, 0, t))
			_box(b, pp + Vector3(0, fh * 0.5, 0), Vector3(0.12, fh, 0.12), Color("2b2f33"))
		_box(b, o + (Vector3(0, fh - 0.1, sgn * half) if along_x else Vector3(sgn * half, 0, 0)),
			Vector3(half * 2.0, 0.1, 0.1) if along_x else Vector3(0.1, 0.1, half * 2.0), Color("2b2f33"))
	# tombstones in rows
	for r in 5:
		for c in 7:
			if rng.randf() < 0.22:
				continue
			var tp := o + Vector3(-20.0 + float(c) * 6.2, 0, -20.0 + float(r) * 8.0)
			if absf(tp.x - o.x) < 3.0 or absf(tp.z - o.z) < 3.0:
				continue
			var kind := rng.randi_range(0, 2)
			if kind == 0:
				_box(b, tp + Vector3(0, 0.7, 0), Vector3(1.0, 1.4, 0.24), CityConfig.C_GRAVE)
				b.pyramid(SOLID, tp + Vector3(0, 1.4, 0), Vector2(1.0, 0.24), 0.45, CityConfig.C_GRAVE)
			elif kind == 1:
				_box(b, tp + Vector3(0, 0.8, 0), Vector3(0.26, 1.6, 0.26), CityConfig.C_GRAVE)
				_box(b, tp + Vector3(0, 1.1, 0), Vector3(1.1, 0.26, 0.26), CityConfig.C_GRAVE)
			else:
				b.cylinder(SOLID, tp, 0.5, 0.5, 1.3, 8, CityConfig.C_GRAVE)
				_box(b, tp + Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.3), Color("6f746f"))
	# chapel
	var ch := o + Vector3(-half + 12.0, 0, -half + 12.0)
	_box(b, ch + Vector3(0, 0.3, 0), Vector3(11.0, 0.6, 14.0), CityConfig.C_STONE_D)
	_box(b, ch + Vector3(0, 3.4, 0), Vector3(10.0, 6.2, 13.0), Color("8a8b86"), Color("8a8b86"))
	b.gable(SOLID, ch + Vector3(0, 6.5, 0), 11.5, 14.5, 3.4, Color("3f4a52"), Color("3f4a52"))
	_box(b, ch + Vector3(0, 8.2, -6.4), Vector3(3.0, 3.4, 3.0), Color("8a8b86"))
	b.pyramid(SOLID, ch + Vector3(0, 9.9, -6.4), Vector2(3.4, 3.4), 3.6, Color("3f4a52"))
	b.box(GLOW, ch + Vector3(0, 4.4, 6.55), Vector3(2.0, 3.0, 0.12), Color("e8c86a"))
	# cross on the roof
	_box(b, ch + Vector3(0, 11.0, 6.0), Vector3(0.2, 2.4, 0.2), Color("e8e0c8"))
	_box(b, ch + Vector3(0, 11.6, 6.0), Vector3(1.4, 0.2, 0.2), Color("e8e0c8"))
	_add_col(cols, ch + Vector3(0, 4.0, 0), Vector3(10.0, 8.0, 13.0))
	# dead trees + cypress
	for i in 10:
		var pp2 := o + Vector3(rng.randf_range(-half + 4.0, half - 4.0), 0, rng.randf_range(-half + 4.0, half - 4.0))
		if pp2.distance_to(ch) < 10.0:
			continue
		if rng.randf() < 0.5:
			_dead_tree(b, pp2, rng.randf_range(0.8, 1.2))
		else:
			b.cylinder(SOLID, pp2, 1.1, 0.0, 6.5, 7, Color("2f4a33"))
			b.cylinder(SOLID, pp2, 0.22, 0.18, 2.0, 6, CityConfig.C_TRUNK)

static func _dead_tree(b: MeshBatch, p: Vector3, s: float) -> void:
	var h := 4.2 * s
	b.cylinder(SOLID, p, 0.3 * s, 0.16 * s, h, 6, Color("4a4038"))
	_solid(p, 0.34 * s, h)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.6
		var dir := Vector3(cos(a), 0.9, sin(a)).normalized()
		b.cylinder(SOLID, p + Vector3(0, h * (0.55 + 0.1 * float(i)), 0), 0.13 * s, 0.06 * s, 1.9 * s, 5,
			Color("4a4038"), dir)

# ============================================================== props

static func tree(b: MeshBatch, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var th := 2.6 * s
	b.cylinder(SOLID, p, 0.24 * s, 0.17 * s, th, 6, CityConfig.C_TRUNK)
	_solid(p, 0.30 * s, th + 1.2 * s)
	var col: Color = _pick(rng, [CityConfig.C_LEAF1, CityConfig.C_LEAF2, CityConfig.C_LEAF3, CityConfig.C_LEAF4])
	if rng.randf() < 0.62:
		# conifer: stacked cones
		b.cylinder(SOLID, p + Vector3(0, th * 0.55, 0), 1.9 * s, 0.0, 2.6 * s, 7, col, Vector3.UP, false)
		b.cylinder(SOLID, p + Vector3(0, th * 0.55 + 1.35 * s, 0), 1.45 * s, 0.0, 2.2 * s, 7, col.lightened(0.06), Vector3.UP, false)
		b.cylinder(SOLID, p + Vector3(0, th * 0.55 + 2.6 * s, 0), 1.0 * s, 0.0, 1.9 * s, 7, col.lightened(0.12), Vector3.UP, false)
	else:
		# broadleaf: two chunky pyramids
		b.pyramid(SOLID, p + Vector3(0, th * 0.85, 0), Vector2(4.4, 4.4) * s, 3.0 * s, col)
		b.pyramid(SOLID, p + Vector3(0, th * 0.85 + 1.9 * s, 0), Vector2(3.0, 3.0) * s, 2.4 * s, col.lightened(0.1))

static func _bench(b: MeshBatch, p: Vector3, dir: Vector3) -> void:
	var ax := dir.normalized()
	var along := 2.0
	_solid_box(p + Vector3(0, 0.45, 0), Vector3(along, 1.0, 0.9) if absf(ax.x) > 0.5 else Vector3(0.9, 1.0, along))
	_obox(b, p + Vector3(0, 0.45, 0), ax, along, 0.6, 0.12, CityConfig.C_WOOD)
	for s in [-1.0, 1.0]:
		_obox(b, p + ax * (s * along * 0.42) + Vector3(0, 0.22, 0), ax, 0.16, 0.5, 0.45, CityConfig.C_METAL_D)
	if absf(ax.x) > 0.5:
		_box(b, p + Vector3(0, 0.78, -0.28), Vector3(along, 0.55, 0.12), CityConfig.C_WOOD.darkened(0.1))
	else:
		_box(b, p + Vector3(-0.28, 0.78, 0), Vector3(0.12, 0.55, along), CityConfig.C_WOOD.darkened(0.1))

static func streetlight(b: MeshBatch, p: Vector3, dir: Vector3) -> void:
	var d := dir.normalized()
	b.cylinder(SOLID, p, 0.15, 0.1, 6.2, 6, CityConfig.C_METAL_D)
	_solid(p, 0.22, 6.2)
	b.cylinder(SOLID, p + Vector3(0, 6.0, 0), 0.08, 0.08, 1.9, 4, CityConfig.C_METAL_D, d)
	var head := p + Vector3(0, 6.05, 0) + d * 1.9
	_box(b, head, Vector3(0.62, 0.2, 0.62), CityConfig.C_METAL_D)
	b.box(GLOW, head + Vector3(0, -0.16, 0), Vector3(0.5, 0.12, 0.5), CityConfig.C_GLOW_WIN)

# ============================================================ EXTRA HELPERS

static func _palm(b: MeshBatch, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var h := 7.4 * s
	b.cylinder(SOLID, p, 0.34 * s, 0.2 * s, h, 6, Color("8a6b45"))
	_solid(p, 0.38 * s, h)
	var leaf := Color("3f8a44")
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf() * 0.5
		var dir := Vector3(cos(a), 0.42, sin(a)).normalized()
		b.cylinder(SOLID, p + Vector3(0, h - 0.15, 0), 0.5 * s, 0.02, 3.6 * s, 4,
			leaf.lerp(Color("5aa84e"), rng.randf()), dir)
	_bush(b, p + Vector3(0, h - 0.1, 0), 0.55 * s, rng)

static func _water(b: MeshBatch, c: Vector3, size: Vector2, rng: RandomNumberGenerator,
		y: float = 0.17) -> void:
	b.plate(SOLID, c, size, Color("2f7fa8"), y)
	for i in 7:
		var px := rng.randf_range(-size.x * 0.42, size.x * 0.42)
		var pz := rng.randf_range(-size.y * 0.44, size.y * 0.44)
		b.plate(SOLID, c + Vector3(px, 0, pz),
			Vector2(rng.randf_range(1.4, 4.2), 0.28), Color("6fb4cd"), y + 0.012)

static func _rock(b: MeshBatch, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var rh := s * rng.randf_range(0.5, 0.8)
	b.pyramid(SOLID, p, Vector2(s, s * 0.86), rh, CityConfig.C_ROCK)
	_solid(p, s * 0.42, rh)

static func _boat(b: MeshBatch, p: Vector3, yaw: float, s: float, col: Color) -> void:
	var ax := Vector3(cos(yaw), 0, sin(yaw))
	_obox(b, p + Vector3(0, 0.42 * s, 0), ax, 4.0 * s, 1.5 * s, 0.55 * s, col)
	_obox(b, p + Vector3(0, 0.78 * s, 0), ax, 1.6 * s, 1.2 * s, 0.7 * s, Color("e8e4dd"))
	b.cylinder(SOLID, p + ax * (0.6 * s) + Vector3(0, 0.8 * s, 0), 0.06, 0.06, 1.6 * s, 4, CityConfig.C_METAL_D)

static func _thatch(b: MeshBatch, base: Vector3, w: float, d: float, h: float) -> void:
	b.pyramid(SOLID, base, Vector2(w, d), h, Color("b39158"))

# ============================================================== HANGAR

static func _hangar(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# runway markings on the apron
	for i in 6:
		b.plate(SOLID, o + Vector3(-half + 3.0 + float(i) * 9.0, 0, half - 4.5),
			Vector2(4.4, 0.5), CityConfig.C_LINE, 0.17)
	# ---- hangar shell
	var c := o + Vector3(-1.0, 0, -5.0)
	var w := 40.0
	var d := 22.0
	var h := 12.0
	_box(b, c + Vector3(0, 0.3, 0), Vector3(w + 1.4, 0.6, d + 1.4), CityConfig.C_CONCRETE_D)
	_box(b, c + Vector3(0, h * 0.5 + 0.6, 0), Vector3(w, h, d), CityConfig.C_IND_WALL, CityConfig.C_IND_WALL_D)
	for i in 11:
		var rx := -w * 0.5 + float(i) * (w / 10.0)
		_box(b, c + Vector3(rx, h * 0.5 + 0.6, d * 0.5 + 0.07), Vector3(0.2, h, 0.14),
			CityConfig.C_IND_WALL_D)
	# arched roof line
	for i in 11:
		var t := float(i) / 10.0
		var a := PI * t
		_box(b, c + Vector3(cos(a) * w * 0.5, h + 0.6 + sin(a) * 4.4, d * 0.5),
			Vector3(3.0, 1.2, 0.7), Color("9aa3a8"))
		_box(b, c + Vector3(cos(a) * w * 0.5, h + 0.6 + sin(a) * 4.4, -d * 0.5),
			Vector3(3.0, 1.2, 0.7), Color("9aa3a8"))
	_box(b, c + Vector3(0, h + 0.9, 0), Vector3(w + 1.4, 0.6, d + 1.0), Color("8b9298"))
	# sliding door
	_box(b, c + Vector3(0, 4.0, d * 0.5 + 0.22), Vector3(w * 0.66, 8.0, 0.3), Color("a4a9ad"))
	for k in 7:
		_box(b, c + Vector3(0, 1.0 + float(k) * 1.1, d * 0.5 + 0.42), Vector3(w * 0.62, 0.08, 0.06),
			Color("8a8f93"))
	b.box(GLOW, c + Vector3(0, 8.4, d * 0.5 + 0.5), Vector3(w * 0.5, 0.5, 0.12), Color("ffe9b0"))
	_add_col(cols, c + Vector3(0, (h + 5.0) * 0.5 + 0.6, 0), Vector3(w + 1.4, h + 5.0, d + 1.4))
	# ---- control tower
	var tc := o + Vector3(half - 6.0, 0, -half + 6.0)
	b.cylinder(SOLID, tc, 2.6, 2.3, 17.0, 8, Color("bcc2c6"))
	b.cylinder(GLASS, tc + Vector3(0, 17.0, 0), 3.6, 3.3, 3.4, 8, Color("8fc2d6"))
	_box(b, tc + Vector3(0, 20.7, 0), Vector3(8.0, 0.6, 8.0), CityConfig.C_METAL_D)
	b.cylinder(SOLID, tc + Vector3(0, 21.0, 0), 0.12, 0.06, 5.2, 4, CityConfig.C_METAL)
	b.box(GLOW, tc + Vector3(0, 26.4, 0), Vector3(0.5, 0.5, 0.5), CityConfig.C_GLOW_RED)
	_add_col(cols, tc + Vector3(0, 9.0, 0), Vector3(5.4, 18.0, 5.4))
	# ---- a plane parked on the apron
	var pp := o + Vector3(0.0, 0, half - 9.0)
	b.cylinder(SOLID, pp + Vector3(-8.0, 2.4, 0), 1.55, 1.25, 16.0, 8,
		Color("eef2f5"), Vector3(1, 0, 0))
	b.pyramid(SOLID, pp + Vector3(8.0, 2.4, 0), Vector2(2.6, 2.6), 1.6, Color("eef2f5"))
	_box(b, pp + Vector3(0.5, 2.35, 0), Vector3(4.2, 0.34, 18.0), Color("dfe6ea"))
	_box(b, pp + Vector3(-6.2, 3.7, 0), Vector3(2.0, 3.4, 0.34), Color("f2c14a"))
	_box(b, pp + Vector3(-7.6, 3.0, 0), Vector3(1.4, 0.3, 6.2), Color("f2c14a"))
	b.box(GLASS, pp + Vector3(6.2, 2.9, 0), Vector3(1.6, 0.6, 1.4), Color("3d7f9c"))
	for sx: float in [-3.4, 3.4]:
		b.cylinder(SOLID, pp + Vector3(1.6, 0.34, sx), 0.72, 0.72, 0.34, 10,
			CityConfig.C_DARK, Vector3(0, 0, 1))
		b.cylinder(SOLID, pp + Vector3(1.6, 0.34, sx), 0.34, 0.34, 0.4, 8, Color("c8ccd0"),
			Vector3(0, 0, 1))
	_add_col(cols, pp + Vector3(0, 2.4, 0), Vector3(18.0, 4.6, 18.0))
	# fuel drums + cones
	for i in 5:
		var dp := o + Vector3(-half + 4.0 + float(i) * 2.2, 0, -half + 5.0)
		b.cylinder(SOLID, dp, 0.7, 0.7, 1.3, 8, Color("c8a03a"))
	for i in 4:
		var cp := o + Vector3(half - 4.0, 0, -8.0 + float(i) * 4.0)
		b.cylinder(SOLID, cp, 0.42, 0.1, 0.8, 6, Color("e2601f"))
	tree(b, o + Vector3(-half + 3.0, 0, half - 3.0), 1.0, rng)

# ============================================================== MILL

static func _mill(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var wood: Color = CityConfig.C_WOOD
	# ---- sawmill shed
	var c := o + Vector3(-7.0, 0, -6.0)
	var w := 26.0
	var d := 17.0
	var h := 7.4
	_box(b, c + Vector3(0, 0.25, 0), Vector3(w + 1.0, 0.5, d + 1.0), CityConfig.C_CONCRETE_D)
	_box(b, c + Vector3(0, h * 0.5 + 0.5, 0), Vector3(w, h, d), wood)
	for i in 15:
		var rx := -w * 0.5 + float(i) * (w / 14.0)
		_box(b, c + Vector3(rx, h * 0.5 + 0.5, d * 0.5 + 0.08), Vector3(0.16, h, 0.12), wood.darkened(0.3))
	_box(b, c + Vector3(0, h * 0.5 + 0.5, -d * 0.5 - 0.08), Vector3(w, h, 0.16), wood.darkened(0.18))
	b.gable(SOLID, c + Vector3(0, h + 0.5, 0), w + 1.6, d + 1.6, 4.2,
		Color("5c4630"), Color("493620"))
	var door := c + Vector3(0, 2.6, d * 0.5 + 0.3)
	_box(b, door, Vector3(9.0, 5.2, 0.2), Color("3a2b1c"))
	b.box(GLOW, c + Vector3(0, 6.6, d * 0.5 + 0.5), Vector3(7.0, 0.4, 0.12), CityConfig.C_GLOW_WIN)
	_add_col(cols, c + Vector3(0, (h + 4.6) * 0.5 + 0.5, 0), Vector3(w + 1.6, h + 4.6, d + 1.6))
	# ---- circular saw
	var sp := o + Vector3(6.0, 0, -2.0)
	_box(b, sp + Vector3(0, 0.7, 0), Vector3(6.0, 1.4, 3.0), CityConfig.C_METAL_D)
	b.cylinder(SOLID, sp + Vector3(0, 1.0, -1.6), 2.2, 2.2, 0.12, 18, Color("b9bec2"),
		Vector3(1, 0, 0))
	b.cylinder(SOLID, sp + Vector3(0, 1.0, -1.5), 1.6, 1.6, 0.14, 18, Color("8f9599"),
		Vector3(1, 0, 0))
	_box(b, sp + Vector3(0, 3.4, -1.0), Vector3(5.2, 0.4, 2.2), CityConfig.C_METAL)
	_add_col(cols, sp + Vector3(0, 1.2, 0), Vector3(6.0, 2.4, 3.0))
	# ---- log piles
	for row in 3:
		for i in 5 - row:
			var lp := o + Vector3(half - 13.0 + float(i) * 3.2 + float(row) * 1.6,
				0.75 + float(row) * 1.3, half - 8.0)
			b.cylinder(SOLID, lp + Vector3(-3.0, 0, 0), 0.72, 0.72, 6.4, 8, Color("8a6b45"),
				Vector3(1, 0, 0))
			b.cylinder(SOLID, lp + Vector3(2.9, 0, 0), 0.62, 0.62, 0.12, 8, Color("c8a878"),
				Vector3(1, 0, 0))
	_add_col(cols, o + Vector3(half - 6.0, 1.6, half - 8.0), Vector3(16.0, 3.2, 8.0))
	# ---- plank stacks
	for i in 4:
		var pp := o + Vector3(-half + 6.0, 0, half - 6.0 - float(i) * 5.0)
		for k in 5:
			_box(b, pp + Vector3(0, 0.3 + float(k) * 0.42, 0), Vector3(7.0, 0.38, 2.4),
				Color("c8a878").darkened(float(k) * 0.03))
	# ---- sawdust heap, wood stove, truck
	b.pyramid(SOLID, o + Vector3(half - 5.0, 0, -half + 9.0), Vector2(9.0, 9.0), 2.6,
		Color("d8c89a"))
	b.cylinder(SOLID, o + Vector3(-half + 4.0, 0, -half + 5.0), 1.0, 0.9, 6.0, 8,
		CityConfig.C_METAL_D)
	_bus(b, o + Vector3(half - 14.0, 0.18, -half + 4.0), Vector3(1, 0, 0), Color("c8922f"), rng)
	for i in 5:
		tree(b, o + Vector3(-half + 3.0 + float(i) * 2.0, 0, half - 3.0), 1.05, rng)

# ============================================================== SHIPYARD

static func _shipyard(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- water along the south half
	var wc := o + Vector3(0, 0, half * 0.42)
	_water(b, wc, Vector2(g, half * 1.16), rng)
	_box(b, o + Vector3(0, 0.9, -1.0), Vector3(g, 1.8, 3.2), CityConfig.C_CONCRETE_D)
	b.plate(SOLID, o + Vector3(0, 0, -3.6), Vector2(g, 4.0), Color("7a7c78"), 0.16)
	# bollards
	for i in 6:
		var bp := o + Vector3(-half + 3.0 + float(i) * 9.0, 1.8, -2.2)
		b.cylinder(SOLID, bp, 0.34, 0.3, 1.0, 8, CityConfig.C_METAL_D)
	# ---- ship under construction
	var sp := o + Vector3(-2.0, 0.2, half * 0.5)
	var hull: Color = Color("8c2f28")
	_box(b, sp + Vector3(0, 1.4, 0), Vector3(30.0, 2.8, 9.0), hull)
	_box(b, sp + Vector3(0, 3.4, 0), Vector3(26.0, 1.4, 7.6), hull.lightened(0.1))
	_box(b, sp + Vector3(0, 4.4, 0), Vector3(24.0, 0.8, 6.8), Color("d8d4c8"))
	_box(b, sp + Vector3(4.0, 6.6, 0), Vector3(9.0, 4.0, 5.2), Color("e8e4dd"))
	b.box(GLASS, sp + Vector3(4.0, 7.4, 2.65), Vector3(7.4, 1.2, 0.14), Color("3d7f9c"))
	b.cylinder(SOLID, sp + Vector3(-6.0, 4.8, 0), 1.2, 1.0, 5.0, 10, Color("c8402f"))
	b.cylinder(SOLID, sp + Vector3(-6.0, 4.4, 0), 1.35, 1.35, 0.5, 10, Color("2b2b30"))
	for i in 4:
		b.cylinder(SOLID, sp + Vector3(-9.0 + float(i) * 1.6, 5.0, 0), 0.08, 0.08, 6.0, 4,
			CityConfig.C_METAL)
	_add_col(cols, sp + Vector3(0, 4.0, 0), Vector3(30.0, 8.0, 9.0))
	# ---- gantry crane over the quay
	var gc := o + Vector3(-half + 12.0, 0, -6.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(b, gc + Vector3(sx * 6.0, 9.0, sz * 2.6), Vector3(0.9, 18.0, 0.9),
				Color("d8a52f"))
	_box(b, gc + Vector3(0, 18.6, 0), Vector3(14.0, 1.4, 1.4), Color("d8a52f"))
	_box(b, gc + Vector3(0, 18.0, 0), Vector3(14.0, 0.5, 6.4), Color("c8961f"))
	_box(b, gc + Vector3(3.0, 16.4, 0), Vector3(3.0, 2.6, 2.6), Color("9aa0a4"))
	b.cylinder(SOLID, gc + Vector3(3.0, 8.0, 0), 0.1, 0.1, 8.4, 4, CityConfig.C_METAL_D)
	_box(b, gc + Vector3(3.0, 6.6, 0), Vector3(2.6, 2.8, 2.6), CityConfig.C_CONTAINER[1])
	_add_col(cols, gc + Vector3(0, 9.0, 0), Vector3(14.0, 18.0, 7.0))
	# ---- containers, crates, boat
	for i in 4:
		var cp := o + Vector3(half - 8.0, 0, -half + 6.0 + float(i) * 6.0)
		var cc: Color = CityConfig.C_CONTAINER[rng.randi_range(0, 4)]
		_box(b, cp + Vector3(0, 1.4, 0), Vector3(7.0, 2.8, 3.0), cc)
		if rng.randf() < 0.5:
			_box(b, cp + Vector3(0, 4.2, 0), Vector3(7.0, 2.8, 3.0), cc.darkened(0.15))
		_add_col(cols, cp + Vector3(0, 2.8, 0), Vector3(7.0, 5.6, 3.0))
	_boat(b, o + Vector3(half - 12.0, 0.17, half - 3.0), 0.2, 1.2, Color("d8dde2"))
	_boat(b, o + Vector3(-half + 16.0, 0.17, half - 2.0), -0.3, 1.0, Color("2f6f8f"))
	# harbour office
	var oc := o + Vector3(half - 6.0, 0, -half + 25.0)
	_box(b, oc + Vector3(0, 3.0, 0), Vector3(8.0, 6.0, 8.0), Color("dfe6ea"))
	_box(b, oc + Vector3(0, 6.4, 0), Vector3(9.0, 0.8, 9.0), Color("b84a3a"))
	_add_col(cols, oc + Vector3(0, 3.0, 0), Vector3(8.0, 6.0, 8.0))

# ============================================================== OBSERVATORY

static func _observatory(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var white: Color = Color("eef2f5")
	# ---- circular plinth
	b.cylinder(SOLID, o + Vector3(0, 0.16, 0), 13.5, 13.5, 0.5, 18, Color("c8c4b8"))
	# ---- main drum + dome
	var c := o
	b.cylinder(SOLID, c, 6.2, 5.9, 5.4, 16, white)
	for i in 8:
		var a := TAU * float(i) / 8.0
		b.cylinder(SOLID, c + Vector3(cos(a) * 5.95, 0.1, sin(a) * 5.95), 0.34, 0.3, 5.4, 6,
			Color("c8ccd0"))
	# dome in three tapering rings
	b.cylinder(SOLID, c + Vector3(0, 5.4, 0), 6.2, 5.2, 2.2, 16, white)
	b.cylinder(SOLID, c + Vector3(0, 7.6, 0), 5.2, 3.4, 1.8, 16, white.lightened(0.03))
	b.cylinder(SOLID, c + Vector3(0, 9.4, 0), 3.4, 1.0, 1.4, 16, white)
	b.cylinder(SOLID, c + Vector3(0, 10.8, 0), 1.0, 0.2, 0.9, 10, Color("c8ccd0"))
	# opening slit
	b.box(SOLID, c + Vector3(0, 6.6, 3.0), Vector3(1.6, 3.6, 5.4), Color("3a4046"))
	# telescope tube poking out
	var tb := c + Vector3(0, 8.2, 2.6)
	b.cylinder(SOLID, tb, 1.15, 1.0, 7.0, 10, Color("b9bec2"), Vector3(0, 0.42, 1))
	b.cylinder(SOLID, tb + Vector3(0, 3.0, 6.6), 1.25, 1.25, 0.4, 10, Color("2b2b30"),
		Vector3(0, 0.42, 1))
	_add_col(cols, c + Vector3(0, 5.6, 0), Vector3(12.4, 11.2, 12.4))
	# ---- annex + stairs
	var ac := o + Vector3(11.0, 0, -6.0)
	_box(b, ac + Vector3(0, 2.6, 0), Vector3(10.0, 5.2, 9.0), Color("dcd8cc"))
	_box(b, ac + Vector3(0, 5.4, 0), Vector3(11.0, 0.6, 10.0), Color("9aa3a8"))
	b.box(GLASS, ac + Vector3(0, 2.8, 4.55), Vector3(7.0, 1.8, 0.12), Color("3d7f9c"))
	b.box(GLOW, ac + Vector3(0, 4.6, 4.6), Vector3(7.6, 0.4, 0.12), Color("bfe8ff"))
	_add_col(cols, ac + Vector3(0, 2.6, 0), Vector3(10.0, 5.2, 9.0))
	for i in 6:
		_box(b, o + Vector3(0, 0.2 + float(i) * 0.2, 7.6 + float(i) * 0.7),
			Vector3(7.0, 0.4, 0.7), CityConfig.C_STONE_L)
	# parking + mast + trees
	for i in 3:
		_car(b, o + Vector3(-half + 8.0 + float(i) * 6.0, 0.18, -half + 7.0),
			Vector3(0, 0, 1), _pick(rng, [Color("c8402f"), Color("2f5fa8"), Color("d8d4c8")]), false)
	b.cylinder(SOLID, o + Vector3(-half + 5.0, 0, half - 6.0), 0.16, 0.1, 12.0, 6,
		CityConfig.C_METAL_D)
	b.box(GLOW, o + Vector3(-half + 5.0, 12.1, half - 6.0), Vector3(0.5, 0.5, 0.5),
		CityConfig.C_GLOW_RED)
	for i in 7:
		var a2 := TAU * float(i) / 7.0
		tree(b, o + Vector3(cos(a2) * 22.5, 0, sin(a2) * 22.5), rng.randf_range(0.9, 1.2), rng)

# ============================================================== CAPE TOWN

static func _capetown(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var pastel := [Color("f2c1b6"), Color("a8d8c8"), Color("f7e3a1"), Color("b9c9ee"),
		Color("e8b8d8"), Color("f5f0e6")]
	# ---- Table Mountain: flat topped mesa on the north side
	var mc := o + Vector3(-4.0, 0, -half + 13.0)
	_box(b, mc + Vector3(0, 3.5, 0), Vector3(38.0, 7.0, 15.0), Color("8d8574"))
	_box(b, mc + Vector3(0, 7.6, 0), Vector3(33.0, 2.4, 12.0), Color("9a9384"))
	_box(b, mc + Vector3(0, 9.2, 0), Vector3(30.0, 1.4, 10.0), Color("6d7a55"))
	for i in 5:
		_box(b, mc + Vector3(-17.0 + float(i) * 8.5, 2.0, 8.4), Vector3(7.0, 4.0, 3.0),
			Color("7d7666"))
	_add_col(cols, mc + Vector3(0, 5.0, 0), Vector3(38.0, 10.0, 15.0))
	# ---- lighthouse on the water side
	var lc := o + Vector3(half - 8.0, 0, half - 8.0)
	b.cylinder(SOLID, lc, 4.6, 4.4, 0.8, 12, Color("c8c4b8"))
	b.cylinder(SOLID, lc + Vector3(0, 0.8, 0), 2.7, 2.1, 6.0, 12, Color("f2f4f5"))
	b.cylinder(SOLID, lc + Vector3(0, 6.8, 0), 2.0, 1.9, 3.0, 12, Color("c8402f"))
	b.cylinder(SOLID, lc + Vector3(0, 9.8, 0), 1.8, 1.7, 3.0, 12, Color("f2f4f5"))
	b.cylinder(SOLID, lc + Vector3(0, 12.8, 0), 1.7, 1.7, 2.0, 10, Color("c8402f"))
	b.cylinder(GLASS, lc + Vector3(0, 14.8, 0), 1.9, 1.7, 2.2, 10, Color("ffe9b0"))
	b.pyramid(SOLID, lc + Vector3(0, 17.0, 0), Vector2(4.2, 4.2), 2.0, Color("c8402f"))
	b.box(GLOW, lc + Vector3(0, 15.6, 0), Vector3(2.4, 1.6, 2.4), Color("fff2c8"))
	_add_col(cols, lc + Vector3(0, 9.0, 0), Vector3(6.0, 18.0, 6.0))
	# ---- colourful houses in a row along the street
	for i in 5:
		var hp := o + Vector3(-half + 7.0 + float(i) * 11.0, 0, half - 9.0)
		var cc: Color = pastel[i % pastel.size()]
		_box(b, hp + Vector3(0, 1.9, 0), Vector3(9.0, 3.8, 8.0), cc)
		for k in 2:
			_window(b, hp + Vector3(-2.4 + float(k) * 4.8, 2.2, 4.05), Vector3(0, 0, 1),
				1.7, 2.0, cc.lightened(0.25), Color("37505c"))
			_box(b, hp + Vector3(-2.9 + float(k) * 4.8, 2.2, 4.3), Vector3(0.4, 2.0, 0.14),
				Color("f2f4f5"))
		_box(b, hp + Vector3(0, 3.9, 0), Vector3(10.0, 0.5, 9.0), cc.darkened(0.12))
		if i % 2 == 0:
			b.gable(SOLID, hp + Vector3(0, 4.1, 0), 10.0, 9.0, 2.6, Color("b8544a"),
				Color("a0453d"))
		_add_col(cols, hp + Vector3(0, 2.0, 0), Vector3(9.0, 4.0, 8.0))
	# palms + benches along the promenade
	for i in 5:
		_palm(b, o + Vector3(-half + 4.0 + float(i) * 12.0, 0, half - 2.5),
			rng.randf_range(0.85, 1.15), rng)
	for i in 3:
		_bench(b, o + Vector3(-10.0 + float(i) * 10.0, 0, half - 13.0), Vector3(1, 0, 0))
	# surf shack
	var sc := o + Vector3(-half + 6.0, 0, -half + 6.0)
	_box(b, sc + Vector3(0, 1.6, 0), Vector3(7.0, 3.2, 6.0), Color("3f8a8f"))
	_thatch(b, sc + Vector3(0, 3.2, 0), 9.0, 8.0, 2.2)
	_add_col(cols, sc + Vector3(0, 1.7, 0), Vector3(7.0, 3.4, 6.0))

# ============================================================== SENTOSA

static func _sentosa(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- sea on the south side
	_water(b, o + Vector3(0, 0, half * 0.62), Vector2(g, half * 0.76), rng)
	b.plate(SOLID, o + Vector3(0, 0, half * 0.2), Vector2(g, 3.2), Color("e0d2a8"), 0.17)
	# ---- resort hotel
	var hc := o + Vector3(-6.0, 0, -half + 12.0)
	_box(b, hc + Vector3(0, 0.4, 0), Vector3(30.0, 0.8, 15.0), Color("d8d4c8"))
	_box(b, hc + Vector3(0, 9.0, 0), Vector3(26.0, 17.0, 12.0), Color("f2efe6"))
	for f in 5:
		for i in 4:
			b.box(GLASS, hc + Vector3(-9.0 + float(i) * 6.0, 3.4 + float(f) * 3.2, 6.05),
				Vector3(3.6, 1.9, 0.12), Color("5f9fb8"))
		_box(b, hc + Vector3(0, 2.0 + float(f) * 3.2, 6.7), Vector3(24.0, 0.3, 1.6),
			Color("e6e2d6"))
		for i in 4:
			_box(b, hc + Vector3(-9.0 + float(i) * 6.0, 2.6 + float(f) * 3.2, 7.3),
				Vector3(3.6, 0.9, 0.12), Color("cfd8dc"))
	b.box(GLOW, hc + Vector3(0, 18.0, 0), Vector3(26.0, 0.6, 12.0), Color("ff3ba7"))
	_box(b, hc + Vector3(0, 18.6, 0), Vector3(20.0, 2.2, 9.0), Color("f2efe6"))
	_add_col(cols, hc + Vector3(0, 9.0, 0), Vector3(26.0, 18.0, 12.0))
	# ---- pool + deck
	var pc := o + Vector3(8.0, 0, half - 12.0)
	b.plate(SOLID, pc, Vector2(18.0, 11.0), Color("e0d2a8"), 0.17)
	_water(b, pc, Vector2(14.0, 8.0), rng, 0.2)
	for i in 4:
		for k in 2:
			var sp := pc + Vector3(-5.5 + float(i) * 3.7, 0, -5.6 + float(k) * 11.2)
			b.cylinder(SOLID, sp, 0.1, 0.1, 2.4, 4, CityConfig.C_METAL)
			b.cylinder(SOLID, sp + Vector3(0, 2.4, 0), 1.9, 0.15, 0.9, 8,
				Color("f2c1b6") if (i + k) % 2 == 0 else Color("a8d8c8"))
			_box(b, sp + Vector3(1.4, 0.35, 0), Vector3(2.0, 0.25, 0.8), Color("f2efe6"))
	# ---- beach boardwalk + palms
	for i in 9:
		b.plate(SOLID, o + Vector3(-half + 3.0 + float(i) * 6.2, 0, half * 0.34),
			Vector2(5.6, 2.6), Color("b39158"), 0.19)
	for i in 6:
		_palm(b, o + Vector3(-half + 4.0 + float(i) * 9.5, 0, half * 0.1),
			rng.randf_range(0.9, 1.25), rng)
	_boat(b, o + Vector3(-2.0, 0.17, half - 3.0), 0.4, 1.1, Color("f2efe6"))
	# beach bar
	var bc := o + Vector3(half - 8.0, 0, half - 6.0)
	_box(b, bc + Vector3(0, 1.5, 0), Vector3(6.0, 3.0, 5.0), CityConfig.C_WOOD)
	_thatch(b, bc + Vector3(0, 3.0, 0), 8.0, 7.0, 2.0)
	b.box(GLOW, bc + Vector3(0, 3.4, 2.6), Vector3(4.4, 0.5, 0.12), CityConfig.C_GLOW_NEON_P)
	_add_col(cols, bc + Vector3(0, 1.6, 0), Vector3(6.0, 3.2, 5.0))

# ============================================================== POCHINOK

static func _pochinok(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var logc: Color = Color("8a6b45")
	# ---- little wooden church
	var cc := o + Vector3(half - 12.0, 0, -half + 12.0)
	_box(b, cc + Vector3(0, 0.3, 0), Vector3(11.0, 0.6, 11.0), CityConfig.C_STONE_D)
	_box(b, cc + Vector3(0, 3.0, 0), Vector3(9.0, 5.4, 9.0), logc)
	for i in 5:
		_box(b, cc + Vector3(0, 0.9 + float(i) * 1.0, 4.56), Vector3(9.2, 0.12, 0.1),
			logc.darkened(0.22))
	b.gable(SOLID, cc + Vector3(0, 5.7, 0), 10.4, 10.4, 3.4, Color("5f7d6a"), Color("4e6a58"))
	b.cylinder(SOLID, cc + Vector3(0, 8.6, 0), 1.7, 2.3, 1.4, 10, Color("d8b23a"))
	b.cylinder(SOLID, cc + Vector3(0, 10.0, 0), 2.3, 0.9, 2.2, 10, Color("d8b23a"))
	b.cylinder(SOLID, cc + Vector3(0, 12.2, 0), 0.9, 0.16, 2.0, 8, Color("c8922f"))
	_box(b, cc + Vector3(0, 14.6, 0), Vector3(0.16, 1.6, 0.16), Color("f2c14a"))
	_box(b, cc + Vector3(0, 15.1, 0), Vector3(0.9, 0.16, 0.16), Color("f2c14a"))
	_add_col(cols, cc + Vector3(0, 6.0, 0), Vector3(10.4, 12.0, 10.4))
	# ---- log cottages
	for i in 6:
		var hp := o + Vector3(-half + 7.0 + float(i % 3) * 12.5, 0,
			-half + 5.0 + float(i / 3) * 13.0)
		if hp.distance_to(cc) < 12.0:
			continue
		_box(b, hp + Vector3(0, 1.9, 0), Vector3(8.0, 3.8, 7.0), logc)
		for k in 3:
			_box(b, hp + Vector3(0, 0.8 + float(k) * 1.2, 3.56), Vector3(8.2, 0.14, 0.1),
				logc.darkened(0.24))
		b.gable(SOLID, hp + Vector3(0, 3.8, 0), 9.2, 8.2, 3.0, Color("b8544a"), Color("a0453d"))
		_box(b, hp + Vector3(1.4, 4.8, 3.6), Vector3(0.6, 1.4, 0.12), Color("3a4046"))
		b.box(GLOW, hp + Vector3(-1.6, 2.2, 3.62), Vector3(1.4, 1.2, 0.1), CityConfig.C_GLOW_WIN)
		_box(b, hp + Vector3(-2.6, 6.6, 0), Vector3(0.6, 4.0, 0.6), CityConfig.C_BRICK)
		_add_col(cols, hp + Vector3(0, 2.0, 0), Vector3(8.0, 4.0, 7.0))
	# picket fences + garden beds
	for i in 14:
		var fp := o + Vector3(-half + 2.0 + float(i) * 4.0, 0, half - 3.0)
		_box(b, fp + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.12), CityConfig.C_WOOD)
		_box(b, fp + Vector3(2.0, 0.9, 0), Vector3(4.0, 0.12, 0.08), CityConfig.C_WOOD)
	# well
	var wp := o + Vector3(-half + 6.0, 0, half - 12.0)
	b.cylinder(SOLID, wp, 1.5, 1.4, 1.2, 10, CityConfig.C_STONE_D)
	b.cylinder(SOLID, wp + Vector3(0, 1.2, 0), 1.2, 1.2, 0.16, 10, Color("2b3a44"))
	for sx: float in [-1.0, 1.0]:
		_box(b, wp + Vector3(sx * 1.3, 1.9, 0), Vector3(0.16, 2.6, 0.16), CityConfig.C_WOOD)
	b.gable(SOLID, wp + Vector3(0, 3.2, 0), 3.4, 2.6, 1.2, Color("8a4a30"), Color("7a3b2e"))
	# birches
	for i in 9:
		var tp := o + Vector3(rng.randf_range(-half + 3.0, half - 3.0), 0,
			rng.randf_range(-half + 3.0, half - 3.0))
		b.cylinder(SOLID, tp, 0.26, 0.16, 5.0, 6, Color("e6e2d6"))
		b.pyramid(SOLID, tp + Vector3(0, 4.2, 0), Vector2(4.2, 4.2), 3.6, CityConfig.C_LEAF3)

# ============================================================== MARS ELECTRIC

static func _marselectric(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	var steel: Color = Color("b6bcc2")
	# ---- cooling towers (hyperboloid)
	for i in 2:
		var tc := o + Vector3(-14.0 + float(i) * 26.0, 0, -half + 14.0)
		b.cylinder(SOLID, tc, 9.5, 6.0, 15.0, 14, Color("cfd3d6"))
		b.cylinder(SOLID, tc + Vector3(0, 15.0, 0), 6.0, 8.0, 7.0, 14, Color("b6bcc2"))
		b.cylinder(SOLID, tc + Vector3(0, 21.8, 0), 8.0, 8.0, 0.8, 14, Color("9aa3a8"))
		_add_col(cols, tc + Vector3(0, 11.0, 0), Vector3(19.0, 22.0, 19.0))
		for k in 3:
			b.plate(SOLID, tc + Vector3(0, 0, 0), Vector2(20.0 - float(k) * 6.0, 20.0 - float(k) * 6.0),
				Color("a8adaf"), 0.18 + float(k) * 0.02)
	# ---- turbine hall
	var hc := o + Vector3(0, 0, -half + 26.0)
	_box(b, hc + Vector3(0, 5.0, 0), Vector3(34.0, 10.0, 14.0), Color("9aa0a4"))
	for i in 9:
		b.box(GLOW, hc + Vector3(-15.0 + float(i) * 3.6, 8.0, 7.05), Vector3(1.8, 1.2, 0.1),
			Color("ffd98a"))
	_box(b, hc + Vector3(0, 10.6, 0), Vector3(35.0, 0.8, 15.0), Color("7d858a"))
	_add_col(cols, hc + Vector3(0, 5.0, 0), Vector3(34.0, 10.0, 14.0))
	# ---- transformer yard + pylons with cables
	var yc := o + Vector3(half - 12.0, 0, -half + 10.0)
	for i in 3:
		_box(b, yc + Vector3(0, 1.6, float(i) * 5.0), Vector3(7.0, 3.2, 3.6), Color("8d918d"))
		b.cylinder(SOLID, yc + Vector3(0, 3.2, float(i) * 5.0), 0.3, 0.3, 1.4, 6, Color("c8c4b8"))
		b.box(GLOW, yc + Vector3(2.6, 3.9, float(i) * 5.0), Vector3(0.4, 0.4, 0.4),
			CityConfig.C_GLOW_NEON_C)
	_add_col(cols, yc + Vector3(0, 1.7, 5.0), Vector3(7.0, 3.4, 14.0))
	var pylons: Array = []
	for i in 2:
		var pc := o + Vector3(-half + 10.0 + float(i) * 30.0, 0, half - 12.0)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.cylinder(SOLID, pc + Vector3(sx * 1.9, 0, sz * 1.9), 0.16, 0.1, 16.0, 4, steel)
		for k in 3:
			_box(b, pc + Vector3(0, 6.0 + float(k) * 4.0, 0), Vector3(4.4, 0.22, 0.22), steel)
			_box(b, pc + Vector3(0, 6.0 + float(k) * 4.0, 0), Vector3(0.22, 0.22, 4.4), steel)
		_box(b, pc + Vector3(0, 16.2, 0), Vector3(9.0, 0.3, 0.3), steel)
		_box(b, pc + Vector3(0, 16.2, 0), Vector3(0.3, 0.3, 9.0), steel)
		_add_col(cols, pc + Vector3(0, 8.0, 0), Vector3(4.0, 16.0, 4.0))
		pylons.append(pc)
	if pylons.size() == 2:
		var pa: Vector3 = pylons[0]
		var pb: Vector3 = pylons[1]
		var span := pb - pa
		for sz2: float in [-3.6, 0.0, 3.6]:
			var a := pa + Vector3(0, 16.4, sz2)
			var bp: Vector3 = pb + Vector3(0, 16.4, sz2)
			var mid := (a + bp) * 0.5 + Vector3(0, -1.6, 0)
			b.cylinder(SOLID, a, 0.07, 0.07, a.distance_to(mid), 3, CityConfig.C_DARK,
				(mid - a).normalized(), false)
			b.cylinder(SOLID, mid, 0.07, 0.07, mid.distance_to(bp), 3, CityConfig.C_DARK,
				(bp - mid).normalized(), false)
	# ---- warning beacon
	b.box(GLOW, o + Vector3(0, 24.0, -half + 14.0), Vector3(1.0, 1.0, 1.0), CityConfig.C_GLOW_RED)
	# red dust rocks + dead trees
	for i in 6:
		_rock(b, o + Vector3(rng.randf_range(-half + 3.0, half - 3.0), 0,
			rng.randf_range(-half + 3.0, half - 3.0)), rng.randf_range(1.0, 2.4), rng)
	for i in 3:
		_dead_tree(b, o + Vector3(-half + 5.0 + float(i) * 16.0, 0, half - 4.0), 1.1)

# ============================================================== RIM NAM VILLAGE

static func _rimnam(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	_water(b, o, Vector2(g, g), rng)
	var wood: Color = CityConfig.C_WOOD
	# ---- stilt houses over the water
	for i in 5:
		var hp := o + Vector3(-half + 9.0 + float(i % 3) * 17.0, 0,
			-half + 11.0 + float(i / 3) * 20.0)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.cylinder(SOLID, hp + Vector3(sx * 3.6, -1.2, sz * 3.0), 0.24, 0.2, 5.0, 5,
					wood.darkened(0.25))
		_box(b, hp + Vector3(0, 3.0, 0), Vector3(9.0, 0.4, 7.6), wood.darkened(0.1))
		_box(b, hp + Vector3(0, 4.7, 0), Vector3(8.0, 3.0, 6.6), Color("c8a878"))
		for k in 3:
			_box(b, hp + Vector3(0, 3.6 + float(k) * 1.0, 3.4), Vector3(8.2, 0.1, 0.08),
				wood.darkened(0.2))
		_thatch(b, hp + Vector3(0, 6.2, 0), 9.6, 8.2, 3.0)
		b.box(GLOW, hp + Vector3(-2.0, 4.6, 3.35), Vector3(1.3, 1.1, 0.1), CityConfig.C_GLOW_WIN)
		_box(b, hp + Vector3(2.4, 3.1, 4.6), Vector3(1.6, 0.16, 4.0), wood)
		if i < 4:
			_add_col(cols, hp + Vector3(0, 4.0, 0), Vector3(8.0, 8.0, 6.6))
	# ---- wooden walkways
	for i in 7:
		b.plate(SOLID, o + Vector3(-half + 3.0 + float(i) * 8.4, 0, 0), Vector2(7.6, 1.6), wood,
			0.34)
	for i in 2:
		b.plate(SOLID, o + Vector3(0, 0, -half + 6.0 + float(i) * 22.0),
			Vector2(g - 6.0, 1.6), wood.darkened(0.08), 0.34)
	# ---- boats + nets + palms on a small island
	for i in 4:
		_boat(b, o + Vector3(-half + 6.0 + float(i) * 13.0, 0.17, half - 4.0),
			rng.randf_range(-0.4, 0.4), rng.randf_range(0.85, 1.15),
			_pick(rng, [Color("2f6f8f"), Color("c8402f"), Color("e8e4dd")]))
	var ic := o + Vector3(half - 9.0, 0, half - 9.0)
	b.plate(SOLID, ic, Vector2(13.0, 13.0), CityConfig.C_SAND, 0.2)
	for i in 3:
		_palm(b, ic + Vector3(rng.randf_range(-4.0, 4.0), 0, rng.randf_range(-4.0, 4.0)),
			rng.randf_range(0.9, 1.2), rng)
	_boat(b, o + Vector3(-half + 8.0, 0.17, -half + 5.0), 1.2, 1.0, Color("8a6b45"))
	# floating market awning
	var mc := o + Vector3(0, 0, -half + 12.0)
	for i in 4:
		_box(b, mc + Vector3(-half + 6.0 + float(i) * 14.0, 0.5, 0),
			Vector3(11.0, 0.5, 6.0), wood)
		_thatch(b, mc + Vector3(-half + 6.0 + float(i) * 14.0, 0.5, 0), 12.4, 7.4, 1.6)
		b.box(GLOW, mc + Vector3(-half + 6.0 + float(i) * 14.0, 0.9, 3.0),
			Vector3(10.0, 0.4, 0.12), CityConfig.C_GLOW_NEON_Y)

# ============================================================== KATULISTIWA

static func _katulistiwa(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- equator monument in the middle
	var mc := o + Vector3(0, 0, -2.0)
	b.cylinder(SOLID, mc, 12.0, 12.0, 0.5, 20, Color("d8d4c8"))
	b.cylinder(SOLID, mc + Vector3(0, 0.5, 0), 9.0, 9.0, 0.3, 20, Color("c8c4b8"))
	b.cylinder(SOLID, mc + Vector3(0, 0.8, 0), 2.4, 1.3, 11.0, 4, Color("eef2f5"))
	b.cylinder(SOLID, mc + Vector3(0, 11.8, 0), 2.2, 2.2, 0.5, 12, Color("d8b23a"))
	b.cylinder(SOLID, mc + Vector3(0, 12.3, 0), 2.6, 2.9, 1.6, 12, CityConfig.C_GLOW_NEON_C)
	b.cylinder(SOLID, mc + Vector3(0, 13.9, 0), 2.9, 2.2, 1.5, 12, CityConfig.C_GLOW_NEON_C)
	b.cylinder(SOLID, mc + Vector3(0, 15.4, 0), 2.2, 0.8, 1.2, 12, CityConfig.C_GLOW_NEON_C)
	_add_col(cols, mc + Vector3(0, 6.0, 0), Vector3(5.0, 12.0, 5.0))
	# flag ring around the plinth
	for i in 10:
		var a := TAU * float(i) / 10.0
		b.cylinder(SOLID, mc + Vector3(cos(a) * 11.0, 0.8, sin(a) * 11.0), 0.09, 0.07, 3.4, 4,
			CityConfig.C_METAL)
		b.box(GLOW, mc + Vector3(cos(a) * 11.0, 3.6, sin(a) * 11.0), Vector3(0.7, 0.5, 0.7),
			Color("ff3ba7") if i % 2 == 0 else Color("2ff2ff"))
	# ---- colourful low houses on two sides
	var pastel := [Color("f2c1b6"), Color("f7e3a1"), Color("a8d8c8"), Color("b9c9ee")]
	for i in 4:
		var hp := o + Vector3(-half + 8.0 + float(i) * 13.0, 0, half - 8.0)
		var cc: Color = pastel[i % pastel.size()]
		_box(b, hp + Vector3(0, 1.7, 0), Vector3(11.0, 3.4, 7.0), cc)
		b.gable(SOLID, hp + Vector3(0, 3.4, 0), 12.0, 8.0, 2.6, Color("8a4a30"), Color("7a3b2e"))
		for k in 3:
			_window(b, hp + Vector3(-3.4 + float(k) * 3.4, 1.9, 3.55), Vector3(0, 0, 1), 1.4,
				1.6, cc.lightened(0.2), Color("37505c"))
		_add_col(cols, hp + Vector3(0, 1.8, 0), Vector3(11.0, 3.6, 7.0))
	# market stalls with striped canopies
	for i in 3:
		var sp := o + Vector3(-half + 10.0 + float(i) * 12.0, 0, -half + 8.0)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.cylinder(SOLID, sp + Vector3(sx * 2.2, 0, sz * 2.2), 0.1, 0.1, 2.6, 4,
					CityConfig.C_WOOD)
		b.pyramid(SOLID, sp + Vector3(0, 2.6, 0), Vector2(6.0, 6.0), 1.4,
			Color("c8402f") if i % 2 == 0 else Color("2f7fa8"))
		_box(b, sp + Vector3(0, 1.0, 1.4), Vector3(4.0, 0.9, 1.4), CityConfig.C_WOOD)
		_add_col(cols, sp + Vector3(0, 1.2, 0), Vector3(5.0, 2.4, 5.0))
	# big tropical trees
	for i in 5:
		var a2 := TAU * float(i) / 5.0 + 0.4
		tree(b, o + Vector3(cos(a2) * 19.0, 0, sin(a2) * 19.0), rng.randf_range(1.1, 1.5), rng)
		_palm(b, o + Vector3(cos(a2 + 0.5) * 23.0, 0, sin(a2 + 0.5) * 23.0),
			rng.randf_range(0.85, 1.1), rng)

# ============================================================== BIMASAKTI STRIP

static func _bimasakti(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- neon hotel strip along the street
	for i in 4:
		var hp := o + Vector3(-half + 7.0 + float(i) * 13.5, 0, -half + 11.0)
		var h := rng.randf_range(14.0, 26.0)
		var tc: Color = _pick(rng, [Color("2a2438"), Color("241e30"), Color("1f2430")])
		_box(b, hp + Vector3(0, h * 0.5, 0), Vector3(10.0, h, 12.0), tc)
		for f in int(h / 3.2):
			b.box(GLASS, hp + Vector3(0, 2.0 + float(f) * 3.2, 6.06), Vector3(8.0, 1.5, 0.12),
				Color("3d5f78"))
		var neon: Color = [CityConfig.C_GLOW_NEON_P, CityConfig.C_GLOW_NEON_C,
			CityConfig.C_GLOW_NEON_V, CityConfig.C_GLOW_NEON_Y][i % 4]
		b.box(GLOW, hp + Vector3(0, h - 0.6, 6.2), Vector3(10.4, 0.7, 0.2), neon)
		b.box(GLOW, hp + Vector3(-5.06, h * 0.5, 0), Vector3(0.16, h * 0.9, 0.4), neon)
		b.box(GLOW, hp + Vector3(5.06, h * 0.5, 0), Vector3(0.16, h * 0.9, 0.4), neon)
		# ground floor shop front
		b.box(GLOW, hp + Vector3(0, 1.4, 6.1), Vector3(8.4, 2.2, 0.16), neon.darkened(0.15))
		_add_col(cols, hp + Vector3(0, h * 0.5, 0), Vector3(10.0, h, 12.0))
		# sign vertical
		b.box(GLOW, hp + Vector3(6.0, h * 0.55, 6.3), Vector3(1.0, 6.0, 0.3), neon)
	# ---- giant billboards facing the strip
	for i in 3:
		var bp := o + Vector3(-half + 10.0 + float(i) * 17.0, 0, half - 12.0)
		for sx: float in [-3.6, 3.6]:
			b.cylinder(SOLID, bp + Vector3(sx, 0, 0), 0.22, 0.16, 9.0, 6, CityConfig.C_METAL_D)
		_box(b, bp + Vector3(0, 10.0, 0), Vector3(11.0, 6.0, 0.4), Color("1b1d22"))
		b.box(GLOW, bp + Vector3(0, 10.0, 0.28), Vector3(10.0, 5.0, 0.12),
			[CityConfig.C_GLOW_NEON_C, CityConfig.C_GLOW_NEON_P, CityConfig.C_GLOW_NEON_V][i % 3])
		for k in 4:
			b.box(SOLID, bp + Vector3(-3.4 + float(k) * 2.3, 10.0, 0.4), Vector3(0.3, 4.6, 0.06),
				Color("0e1013"))
		_add_col(cols, bp + Vector3(0, 6.0, 0), Vector3(11.0, 12.0, 1.0))
	# ---- glowing arch over the street
	var ac := o + Vector3(0, 0, half - 6.0)
	for sx: float in [-1.0, 1.0]:
		b.cylinder(SOLID, ac + Vector3(sx * 14.0, 0, 0), 0.5, 0.4, 11.0, 8, CityConfig.C_METAL_D)
		_add_col(cols, ac + Vector3(sx * 14.0, 5.5, 0), Vector3(1.2, 11.0, 1.2))
	_box(b, ac + Vector3(0, 11.4, 0), Vector3(30.0, 1.2, 1.2), CityConfig.C_METAL_D)
	b.box(GLOW, ac + Vector3(0, 11.4, 0.68), Vector3(28.0, 0.7, 0.16), CityConfig.C_GLOW_NEON_C)
	b.box(GLOW, ac + Vector3(0, 10.4, 0.7), Vector3(24.0, 0.4, 0.12), CityConfig.C_GLOW_NEON_P)
	# star posts along the kerb
	for i in 8:
		var sp := o + Vector3(-half + 4.0 + float(i) * 7.0, 0, half - 3.0)
		b.cylinder(SOLID, sp, 0.12, 0.08, 2.6, 5, CityConfig.C_METAL_D)
		b.box(GLOW, sp + Vector3(0, 2.7, 0), Vector3(0.5, 0.5, 0.5),
			CityConfig.C_GLOW_NEON_C)
	# parked cars
	for i in 2:
		_car(b, o + Vector3(-6.0 + float(i) * 8.0, 0.18, half - 9.0), Vector3(1, 0, 0),
			_pick(rng, [Color("ff3ba7"), Color("2ff2ff")]), false)

# ============================================================== BULLSEYE

static func _bullseye(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- sand berms behind the targets
	for i in 2:
		_box(b, o + Vector3(0, 1.4, -half + 5.0 + float(i) * 4.0),
			Vector3(g - 4.0, 2.8, 3.0), Color("c8b088"))
		_add_col(cols, o + Vector3(0, 1.4, -half + 5.0 + float(i) * 4.0),
			Vector3(g - 4.0, 2.8, 3.0))
	# ---- big target boards
	for i in 3:
		var tp := o + Vector3(-14.0 + float(i) * 14.0, 0, -half + 13.0)
		for sx: float in [-3.4, 3.4]:
			b.cylinder(SOLID, tp + Vector3(sx, 0, 0), 0.16, 0.12, 6.4, 5, CityConfig.C_METAL_D)
		var rings := [[5.2, Color("f2f4f5")], [4.0, Color("c8402f")], [2.8, Color("f2f4f5")],
			[1.7, Color("c8402f")], [0.7, Color("f2c14a")]]
		var k := 0
		for ring in rings:
			var rad: float = ring[0]
			var rc: Color = ring[1]
			b.cylinder(SOLID, tp + Vector3(0, 3.2 - rad, 0.06 + float(k) * 0.03), rad, rad,
				0.14, 16, rc, Vector3(0, 0, 1))
			k += 1
		_add_col(cols, tp + Vector3(0, 3.2, 0), Vector3(7.0, 6.4, 1.0))
	# ---- firing line shelter
	var fc := o + Vector3(0, 0, half - 12.0)
	for i in 6:
		var px := -22.0 + float(i) * 8.8
		for sz: float in [-1.0, 1.0]:
			b.cylinder(SOLID, fc + Vector3(px, 0, sz * 2.4), 0.14, 0.1, 4.2, 5,
				CityConfig.C_METAL_D)
		b.box(GLOW, fc + Vector3(px + 3.4, 3.6, 0), Vector3(1.6, 0.3, 0.3), Color("ffe9b0"))
	_box(b, fc + Vector3(0, 4.4, 0), Vector3(g - 2.0, 0.4, 6.4), Color("8b9298"))
	_box(b, fc + Vector3(0, 1.1, 1.6), Vector3(g - 6.0, 0.3, 1.4), CityConfig.C_WOOD)
	for i in 5:
		_box(b, fc + Vector3(-18.0 + float(i) * 9.0, 0.6, 1.6), Vector3(0.3, 1.2, 1.0),
			CityConfig.C_WOOD)
	# ---- sandbags, crates, ammo boxes
	for i in 8:
		var bp := o + Vector3(-half + 4.0 + float(i) * 3.0, 0, -half + 1.0)
		_box(b, bp + Vector3(0, 0.3, 0), Vector3(2.8, 0.6, 1.2), Color("c8b088"))
		_box(b, bp + Vector3(0, 0.9, 0), Vector3(2.4, 0.6, 1.0), Color("bda275"))
	for i in 4:
		var cp := o + Vector3(half - 8.0, 0, -half + 8.0 + float(i) * 4.0)
		_box(b, cp + Vector3(0, 0.7, 0), Vector3(2.6, 1.4, 2.6), CityConfig.C_WOOD)
		b.box(GLOW, cp + Vector3(0, 1.5, 1.32), Vector3(1.8, 0.3, 0.08), Color("ffd23b"))
	# ---- watch tower
	var wc := o + Vector3(half - 9.0, 0, half - 9.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.cylinder(SOLID, wc + Vector3(sx * 2.2, 0, sz * 2.2), 0.18, 0.14, 7.0, 5,
				CityConfig.C_WOOD)
	_box(b, wc + Vector3(0, 7.2, 0), Vector3(6.0, 0.4, 6.0), CityConfig.C_WOOD)
	for sx2: float in [-1.0, 1.0]:
		_box(b, wc + Vector3(sx2 * 2.8, 8.4, 0), Vector3(0.16, 2.0, 5.4), CityConfig.C_WOOD)
		_box(b, wc + Vector3(0, 8.4, sx2 * 2.8), Vector3(5.4, 2.0, 0.16), CityConfig.C_WOOD)
	_thatch(b, wc + Vector3(0, 9.4, 0), 7.4, 7.4, 2.0)
	_add_col(cols, wc + Vector3(0, 4.0, 0), Vector3(6.0, 8.0, 6.0))
	# sand + dry grass tufts
	for i in 6:
		_rock(b, o + Vector3(rng.randf_range(-half + 3.0, half - 3.0), 0,
			rng.randf_range(-half + 3.0, half - 3.0)), rng.randf_range(0.8, 1.8), rng)

# ============================================================== PLANTATION

static func _plantation(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- crop rows
	var rows := 9
	for r in rows:
		var z := -half + 4.0 + float(r) * 5.6
		var crop: Color = CityConfig.C_FIELD.lerp(Color("6aa353"), float(r % 3) * 0.18)
		_box(b, o + Vector3(0, 0.55, z), Vector3(g - 6.0, 1.1, 3.6), crop, crop.lightened(0.1))
		for i in 8:
			var bx := -half + 6.0 + float(i) * 6.2
			_bush(b, o + Vector3(bx, 1.1, z), 0.85, rng)
	# ---- plantation house with veranda
	var hc := o + Vector3(-half + 11.0, 0, -half + 9.0)
	_box(b, hc + Vector3(0, 0.3, 0), Vector3(13.0, 0.6, 11.0), CityConfig.C_STONE_D)
	_box(b, hc + Vector3(0, 2.6, 0), Vector3(11.0, 4.6, 9.0), Color("e6dcc8"))
	for i in 3:
		_window(b, hc + Vector3(-3.0 + float(i) * 3.0, 2.6, 4.55), Vector3(0, 0, 1), 1.6, 1.8,
			Color("f2f4f5"), Color("37505c"))
	b.gable(SOLID, hc + Vector3(0, 4.9, 0), 12.4, 10.4, 3.0, Color("7a3b2e"), Color("682f24"))
	_box(b, hc + Vector3(0, 0.9, 6.4), Vector3(12.0, 0.2, 3.6), CityConfig.C_WOOD)
	for i in 5:
		b.cylinder(SOLID, hc + Vector3(-5.4 + float(i) * 2.7, 0, 8.0), 0.12, 0.1, 2.4, 5,
			Color("e6dcc8"))
	_box(b, hc + Vector3(0, 2.5, 8.0), Vector3(12.0, 0.24, 3.8), Color("b8544a"))
	_add_col(cols, hc + Vector3(0, 3.0, 0), Vector3(12.0, 6.0, 10.0))
	# ---- water tank on legs
	var tc := o + Vector3(half - 8.0, 0, -half + 8.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.cylinder(SOLID, tc + Vector3(sx * 1.6, 0, sz * 1.6), 0.16, 0.12, 5.0, 5,
				CityConfig.C_METAL_D)
	b.cylinder(SOLID, tc + Vector3(0, 5.0, 0), 2.4, 2.4, 3.0, 12, Color("9aa3a8"))
	b.cylinder(SOLID, tc + Vector3(0, 8.0, 0), 2.4, 1.6, 0.8, 12, Color("8b9298"))
	_add_col(cols, tc + Vector3(0, 4.0, 0), Vector3(3.6, 8.0, 3.6))
	# ---- tractor + fence + palms
	_tractor(b, o + Vector3(half - 14.0, 0, half - 12.0))
	for i in 10:
		var fp := o + Vector3(-half + 2.0 + float(i) * 5.4, 0, half - 2.0)
		_box(b, fp + Vector3(0, 0.7, 0), Vector3(0.14, 1.4, 0.14), CityConfig.C_WOOD)
		_box(b, fp + Vector3(2.7, 1.0, 0), Vector3(5.4, 0.12, 0.08), CityConfig.C_WOOD)
	for i in 4:
		_palm(b, o + Vector3(-half + 5.0 + float(i) * 15.0, 0, half - 7.0),
			rng.randf_range(0.9, 1.15), rng)

static func _tractor(b: MeshBatch, p: Vector3) -> void:
	_box(b, p + Vector3(0, 1.1, 0), Vector3(4.4, 1.4, 2.2), Color("c8402f"))
	_box(b, p + Vector3(-0.6, 2.4, 0), Vector3(2.4, 1.6, 2.0), Color("c8402f"))
	b.box(GLASS, p + Vector3(-0.6, 2.6, 1.02), Vector3(1.8, 1.0, 0.1), Color("3d7f9c"))
	for sx: float in [-1.35, 1.35]:
		b.cylinder(SOLID, p + Vector3(sx, 0.9, 1.25), 0.9, 0.9, 0.5, 12, CityConfig.C_DARK,
			Vector3(0, 0, 1))
	for sx2: float in [-1.35, 1.35]:
		b.cylinder(SOLID, p + Vector3(sx2, 0.45, 1.25), 0.45, 0.45, 0.5, 10, Color("2b2b30"),
			Vector3(0, 0, 1))
	_box(b, p + Vector3(1.6, 1.9, 0), Vector3(1.6, 0.4, 2.4), Color("8b9298"))

# ============================================================== RIVERSIDE

static func _riverside(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# ---- the river runs across the block (east - west)
	var rc := o + Vector3(0, 0, 2.0)
	_water(b, rc, Vector2(g, 17.0), rng)
	for s: float in [-1.0, 1.0]:
		b.plate(SOLID, o + Vector3(0, 0, 2.0 + s * 10.4), Vector2(g, 4.0), Color("8a7458"), 0.19)
	# reeds along the banks
	for i in 10:
		var rp := o + Vector3(-half + 3.0 + float(i) * 5.4, 0,
			2.0 + (10.8 if rng.randf() < 0.5 else -10.8) + rng.randf_range(-0.6, 0.6))
		for k in 3:
			b.cylinder(SOLID, rp + Vector3(rng.randf_range(-0.7, 0.7), 0,
				rng.randf_range(-0.7, 0.7)), 0.07, 0.02, rng.randf_range(1.1, 1.9), 4,
				Color("6d7a55"))
	# ---- wooden bridge over the river (north - south)
	var bc := o + Vector3(0, 0, 2.0)
	for i in 7:
		b.plate(SOLID, bc + Vector3(0, 0, -8.4 + float(i) * 2.8), Vector2(9.0, 2.4),
			CityConfig.C_WOOD, 0.42)
	for sx: float in [-1.0, 1.0]:
		_box(b, bc + Vector3(sx * 4.6, 0.95, 0), Vector3(0.3, 0.3, 19.0), CityConfig.C_WOOD)
		for i in 5:
			b.cylinder(SOLID, bc + Vector3(sx * 4.6, 0.4, -8.4 + float(i) * 4.2), 0.16, 0.14,
				1.1, 5, CityConfig.C_WOOD.darkened(0.15))
	for sz: float in [-1.0, 1.0]:
		_box(b, bc + Vector3(0, 0.6, sz * 6.0), Vector3(9.0, 1.2, 1.6), CityConfig.C_STONE_D)
		_box(b, bc + Vector3(0, 1.6, sz * 6.0), Vector3(9.4, 0.4, 2.0), CityConfig.C_STONE_L)
	# ---- riverside houses on the far bank
	for i in 4:
		var hp := o + Vector3(-half + 8.0 + float(i) * 14.0, 0, -half + 9.0)
		var wcol: Color = [Color("e6dcc8"), Color("c8a878"), Color("d8cfc0"), Color("b9c6b4")][i % 4]
		_box(b, hp + Vector3(0, 2.2, 0), Vector3(10.0, 4.4, 8.0), wcol)
		b.gable(SOLID, hp + Vector3(0, 4.4, 0), 11.0, 9.0, 3.0, Color("8f4a38"), Color("7a3b2e"))
		for k in 2:
			_window(b, hp + Vector3(-2.6 + float(k) * 5.2, 2.4, 4.05), Vector3(0, 0, 1), 1.5,
				1.8, Color("f2f4f5"), Color("37505c"))
		b.box(GLOW, hp + Vector3(0, 1.2, 4.1), Vector3(2.0, 1.9, 0.12), CityConfig.C_GLOW_WIN)
		_box(b, hp + Vector3(0, 0.5, 5.4), Vector3(3.0, 0.2, 2.4), CityConfig.C_WOOD)
		_add_col(cols, hp + Vector3(0, 2.4, 0), Vector3(11.0, 5.0, 9.0))
	# ---- jetty + rowing boats on the south bank
	var jc := o + Vector3(half - 10.0, 0, half - 9.0)
	for i in 5:
		b.plate(SOLID, jc + Vector3(0, 0, -float(i) * 2.6), Vector2(8.0, 2.4),
			CityConfig.C_WOOD, 0.42 - float(i) * 0.02)
	for sx: float in [-1.0, 1.0]:
		for i in 2:
			b.cylinder(SOLID, jc + Vector3(sx * 3.4, -1.0, -float(i) * 8.0), 0.18, 0.16, 3.2,
				5, CityConfig.C_WOOD.darkened(0.2))
	_boat(b, o + Vector3(half - 16.0, 0.17, 6.0), 1.4, 1.0, Color("d8dde2"))
	_boat(b, o + Vector3(-half + 9.0, 0.17, 8.0), 0.1, 0.9, Color("2f6f8f"))
	# willows + lamps
	for i in 4:
		tree(b, o + Vector3(-half + 5.0 + float(i) * 16.0, 0, half - 4.0),
			rng.randf_range(1.0, 1.3), rng)
	streetlight(b, o + Vector3(-6.0, 0, -half + 3.0), Vector3(0, 0, 1))
	streetlight(b, o + Vector3(6.0, 0, half - 3.0), Vector3(0, 0, -1))

# ============================================================== COUNTRYSIDE

static func _countryside(b: MeshBatch, rng: RandomNumberGenerator, o: Vector3, cols: Array) -> void:
	var g := CityConfig.BLOCK - CityConfig.SIDEWALK * 2.0
	var half := g * 0.5
	# a field patch, a dirt track and a scattering of trees between the cities
	var roll := rng.randf()
	if roll < 0.42:
		for i in 5:
			var fp := o + Vector3(-half + 9.0 + float(i) * 10.0, 0, rng.randf_range(-8.0, 8.0))
			_box(b, fp + Vector3(0, 0.5, 0), Vector3(8.0, 1.0, rng.randf_range(7.0, 13.0)),
				CityConfig.C_FIELD.lerp(Color("8aa348"), rng.randf()))
	elif roll < 0.62:
		# hay meadow
		for i in 4:
			var hp := o + Vector3(rng.randf_range(-half + 6.0, half - 6.0), 0,
				rng.randf_range(-half + 6.0, half - 6.0))
			b.cylinder(SOLID, hp + Vector3(0, 0.75, -1.4), 1.05, 1.05, 2.8, 10,
				Color("d8c07a"), Vector3(1, 0, 0))
	else:
		# a lonely barn or farmhouse
		var bp := o + Vector3(rng.randf_range(-10.0, 10.0), 0, rng.randf_range(-12.0, 4.0))
		if rng.randf() < 0.5:
			_box(b, bp + Vector3(0, 3.0, 0), Vector3(16.0, 6.0, 10.0), Color("a8452f"))
			b.gable(SOLID, bp + Vector3(0, 6.0, 0), 17.0, 11.0, 4.0, Color("6b4a2f"),
				Color("5a3d26"))
			_box(b, bp + Vector3(0, 2.0, 5.1), Vector3(5.0, 4.0, 0.2), Color("e6e2d6"))
			_add_col(cols, bp + Vector3(0, 3.0, 0), Vector3(17.0, 8.0, 11.0))
		else:
			_oldhouse(b, rng, bp, 10.0, 8.0, 2, 0)
			_add_col(cols, bp + Vector3(0, 4.0, 0), Vector3(11.0, 8.0, 9.0))
	# pond sometimes
	if rng.randf() < 0.3:
		var pc := o + Vector3(rng.randf_range(-12.0, 12.0), 0, rng.randf_range(-12.0, 12.0))
		_water(b, pc, Vector2(rng.randf_range(9.0, 15.0), rng.randf_range(9.0, 15.0)), rng)
	# trees, fences, rocks
	for i in rng.randi_range(5, 11):
		var tp := o + Vector3(rng.randf_range(-half + 2.0, half - 2.0), 0,
			rng.randf_range(-half + 2.0, half - 2.0))
		tree(b, tp, rng.randf_range(0.85, 1.4), rng)
	if rng.randf() < 0.5:
		var fz := half - 3.0
		for i in 7:
			var fp2 := o + Vector3(-half + 3.0 + float(i) * 7.6, 0, fz)
			_box(b, fp2 + Vector3(0, 0.7, 0), Vector3(0.16, 1.4, 0.16), CityConfig.C_WOOD)
			_box(b, fp2 + Vector3(3.8, 1.0, 0), Vector3(7.6, 0.12, 0.08), CityConfig.C_WOOD)
	for i in rng.randi_range(0, 3):
		_rock(b, o + Vector3(rng.randf_range(-half + 4.0, half - 4.0), 0,
			rng.randf_range(-half + 4.0, half - 4.0)), rng.randf_range(0.9, 2.2), rng)

## Low-poly car written straight into a batch (parked cars / props).
static func _car(b: MeshBatch, p: Vector3, facing: Vector3, col: Color, police: bool) -> void:
	var ax := facing.normalized()
	var body := col
	var side0 := ax.cross(Vector3.UP).normalized()
	_solid_box(p + Vector3(0, 0.78, 0), Vector3(
		absf(ax.x) * 4.3 + absf(side0.x) * 1.9, 1.55,
		absf(ax.z) * 4.3 + absf(side0.z) * 1.9))
	_obox(b, p + Vector3(0, 0.62, 0), ax, 4.3, 1.9, 0.62, body)
	_obox(b, p + Vector3(0, 1.12, 0), ax, 2.3, 1.72, 0.55, body.darkened(0.05))
	_obox(b, p + Vector3(0, 1.16, 0), ax, 2.2, 1.78, 0.4, Color("3c5866"), Color(-1, -1, -1, -1), GLASS)
	_obox(b, p + Vector3(0, 1.42, 0), ax, 1.9, 1.6, 0.1, col.lightened(0.06))
	# wheels
	var r := 0.34
	var side := ax.cross(Vector3.UP).normalized()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base: Vector3 = p + ax * (sz * 1.4) + side * (sx * 0.78) + Vector3(0, r, 0)
			b.cylinder(SOLID, base, r, r, 0.28, 8, CityConfig.C_DARK, side * signf(sx))
			b.cylinder(SOLID, base + side * (0.06 * signf(sx)), 0.16, 0.16, 0.2, 6,
				Color("c3c8ce"), side * signf(sx))
	# lights
	b.box(GLOW, p - ax * 2.16 + Vector3(0, 0.72, 0) + side * 0.55, Vector3(0.4, 0.2, 0.4), CityConfig.C_GLOW_WIN)
	b.box(GLOW, p - ax * 2.16 + Vector3(0, 0.72, 0) - side * 0.55, Vector3(0.4, 0.2, 0.4), CityConfig.C_GLOW_WIN)
	b.box(GLOW, p + ax * 2.16 + Vector3(0, 0.75, 0), Vector3(1.5, 0.18, 0.2), CityConfig.C_GLOW_RED)
	if police:
		_obox(b, p + Vector3(0, 1.45, 0), ax, 1.0, 1.0, 0.18, CityConfig.C_DARK)
		b.box(GLOW, p + Vector3(0, 1.58, 0) + side * 0.3, Vector3(0.4, 0.22, 0.4), CityConfig.C_GLOW_RED)
		b.box(GLOW, p + Vector3(0, 1.58, 0) - side * 0.3, Vector3(0.4, 0.22, 0.4), Color("2b6bff"))

## Small bus / ambulance.
static func _bus(b: MeshBatch, p: Vector3, facing: Vector3, col: Color, rng: RandomNumberGenerator,
		ambulance: bool = false) -> void:
	var ax := facing.normalized()
	var side := ax.cross(Vector3.UP).normalized()
	var L := 6.4 if not ambulance else 5.2
	_solid_box(p + Vector3(0, 1.5, 0), Vector3(
		absf(ax.x) * L + absf(side.x) * 2.3, 3.0,
		absf(ax.z) * L + absf(side.z) * 2.3))
	_obox(b, p + Vector3(0, 1.5, 0), ax, L, 2.2, 2.2, col)
	_obox(b, p + Vector3(0, 2.7, 0), ax, L * 0.9, 2.05, 0.3, col.darkened(0.08))
	for s in [-1.0, 1.0]:
		_obox(b, p + Vector3(0, 1.95, 0), ax, L * 0.82, 2.26, 0.9, Color("3c5866"), Color(-1, -1, -1, -1), GLASS)
		break
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base: Vector3 = p + ax * (sz * L * 0.32) + side * (sx * 0.98) + Vector3(0, 0.42, 0)
			b.cylinder(SOLID, base, 0.42, 0.42, 0.3, 10, CityConfig.C_DARK, side * signf(sx))
	b.box(GLOW, p - ax * (L * 0.5) + Vector3(0, 0.95, 0), Vector3(1.9, 0.3, 0.2), CityConfig.C_GLOW_WIN)
	b.box(GLOW, p + ax * (L * 0.5) + Vector3(0, 0.95, 0), Vector3(1.9, 0.3, 0.2), CityConfig.C_GLOW_RED)
	if ambulance:
		for s in [-1.0, 1.0]:
			b.box(GLOW, p + side * (s * 0.6) + Vector3(0, 2.4, 0), Vector3(0.5, 1.4, 0.25), CityConfig.C_GLOW_RED)
			b.box(GLOW, p + side * (s * 0.6) + Vector3(0, 2.4, 0), Vector3(0.25, 0.5, 0.25), CityConfig.C_GLOW_RED)
	else:
		b.box(GLOW, p + Vector3(0, 2.9, 0), Vector3(1.2, 0.3, 1.2), CityConfig.C_GLOW_NEON_Y)
