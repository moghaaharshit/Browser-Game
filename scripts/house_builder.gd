class_name HouseBuilder
extends RefCounted

## A house you can actually walk into.  Ground floor with a real door opening,
## furniture (sofa, table, chairs, kitchen, fridge, TV), an internal staircase
## up to the second floor, a second flight up to the flat roof, and windows cut
## straight through the walls on every side.
##
## Collision is a handful of boxes per house: the walls (segmented around the
## door only), the two floor slabs, the roof and one tilted ramp collider under
## each flight of stairs, which is what lets a CharacterBody3D walk up.  Every
## stair tread you see is drawn, but only the ramp is physical.

## Every doorway that got built, so the game (and the tests) can find one.
static var doors: Array = []
## Bottom of every staircase (for the self tests).
static var stairs: Array = []
## Walkable floor spots inside every house built so far: the loot spawns here.
static var rooms: Array = []

const T := 0.30            ## wall thickness
const F2 := 3.15           ## second floor level (local y)
const ROOF := 6.05         ## roof slab bottom
const ROOF_TOP := 6.28
const STEP := 0.26         ## stair rise per step

const C_WALL_IN := Color("efe7d8")
const C_FLOOR_W := Color("a87b4e")
const C_FLOOR_T := Color("cbc4b4")
const C_TRIM := Color("f5f2e9")
const C_DOOR := Color("6b4a2f")
const C_GLASS := Color("9fd8e6")

# ------------------------------------------------------------------ helpers

static func _bx(b: MeshBatch, cols: Array, c: Vector3, s: Vector3, col: Color,
		collide: bool = true, surf: int = MeshBatch.SOLID) -> void:
	b.box(surf, c, s, col)
	if collide:
		cols.append(AABB(c - s * 0.5, s))

static func _segments(length: float, gaps: Array) -> Array:
	# returns [[from, to], ...] along the wall, gaps removed
	var out: Array = []
	var cursor := -length * 0.5
	gaps.sort_custom(func(a, bb): return float(a[0]) < float(bb[0]))
	for g in gaps:
		var g0: float = maxf(float(g[0]), -length * 0.5)
		var g1: float = minf(float(g[1]), length * 0.5)
		if g0 > cursor + 0.02:
			out.append([cursor, g0])
		cursor = maxf(cursor, g1)
	if cursor < length * 0.5 - 0.02:
		out.append([cursor, length * 0.5])
	return out

## Wall with a door gap and window gaps.  `base` is the middle of the wall at
## its bottom, `along` a unit vector along the wall (world axis).
static func _wall(b: MeshBatch, cols: Array, base: Vector3, along: Vector3, length: float,
		height: float, doors: Array, wins: Array, col: Color) -> void:
	var thick := T
	# three horizontal bands: below the windows, the window band, above
	var bands := [[0.0, 1.02], [1.02, 2.16], [2.16, height]]
	for band in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		if y1 <= y0 + 0.01:
			continue
		var gaps: Array = []
		for dr in doors:
			if y0 < float(dr[2]) - 0.01:
				gaps.append([float(dr[0]) - float(dr[1]) * 0.5, float(dr[0]) + float(dr[1]) * 0.5])
		for wv in wins:
			if float(wv[2]) < y1 - 0.03 and float(wv[3]) > y0 + 0.03:
				gaps.append([float(wv[0]) - float(wv[1]) * 0.5, float(wv[0]) + float(wv[1]) * 0.5])
		for s in _segments(length, gaps):
			var l: float = s[1] - s[0]
			if l < 0.04:
				continue
			var mid: float = (s[0] + s[1]) * 0.5
			var h := y1 - y0
			var size := Vector3(l, h, thick) if absf(along.x) > 0.5 else Vector3(thick, h, l)
			b.box(MeshBatch.SOLID, base + along * mid + Vector3(0, y0 + h * 0.5, 0), size, col)
	# collision: full height, split only around the doorways
	var door_gaps: Array = []
	for dr in doors:
		door_gaps.append([float(dr[0]) - float(dr[1]) * 0.5, float(dr[0]) + float(dr[1]) * 0.5])
	for s in _segments(length, door_gaps):
		var l: float = s[1] - s[0]
		if l < 0.04:
			continue
		var mid: float = (s[0] + s[1]) * 0.5
		var size := Vector3(l, height, thick) if absf(along.x) > 0.5 else Vector3(thick, height, l)
		var pc: Vector3 = base + along * mid + Vector3(0, height * 0.5, 0)
		cols.append(AABB(pc - size * 0.5, size))
	# window glass, sill and lintel
	for wv in wins:
		var u: float = float(wv[0])
		var wd: float = float(wv[1])
		var wy0: float = float(wv[2])
		var wy1: float = float(wv[3])
		var wc: Vector3 = base + along * u + Vector3(0, (wy0 + wy1) * 0.5, 0)
		var gm := (wy1 - wy0) * 0.94
		var gs := Vector3(wd * 0.94, gm, 0.05) if absf(along.x) > 0.5 else Vector3(0.05, gm, wd * 0.94)
		b.box(MeshBatch.GLASS, wc, gs, C_GLASS)
		var sill := Vector3(wd + 0.24, 0.10, thick + 0.14) if absf(along.x) > 0.5 else Vector3(thick + 0.14, 0.10, wd + 0.24)
		b.box(MeshBatch.SOLID, wc + Vector3(0, -(wy1 - wy0) * 0.5 - 0.05, 0), sill, C_TRIM)
		b.box(MeshBatch.SOLID, wc + Vector3(0, (wy1 - wy0) * 0.5 + 0.05, 0), sill, C_TRIM)
		var mull := Vector3(0.06, gm, 0.09) if absf(along.x) > 0.5 else Vector3(0.09, gm, 0.06)
		b.box(MeshBatch.SOLID, wc, mull, C_TRIM)

## Flight of stairs: drawn treads plus one tilted ramp collider.
static func _stairs(b: MeshBatch, cols: Array, start: Vector3, dir: Vector3, width: float,
		rise: float, run_len: float, col: Color) -> void:
	stairs.append({"start": start, "dir": dir, "rise": rise, "width": width})
	var n := maxi(4, int(ceil(rise / STEP)))
	var step_h := rise / float(n)
	var step_d := run_len / float(n)
	for i in n:
		var h := step_h * float(i + 1)
		var c: Vector3 = start + dir * (step_d * (float(i) + 0.5)) + Vector3(0, h * 0.5, 0)
		var size := Vector3(width, h, step_d + 0.02) if absf(dir.z) > 0.5 else Vector3(step_d + 0.02, h, width)
		b.box(MeshBatch.SOLID, c, size, col)
	# hand rail: a strip of short posts along the outer edge
	var side := Vector3(1, 0, 0) if absf(dir.z) > 0.5 else Vector3(0, 0, 1)
	for i in range(0, n, 3):
		var h2 := step_h * float(i + 1)
		var p: Vector3 = start + dir * (step_d * (float(i) + 0.5)) + side * (width * 0.5)
		b.box(MeshBatch.SOLID, p + Vector3(0, h2 + 0.45, 0), Vector3(0.07, 0.9, 0.07), C_TRIM)
	# one ramp collider under the whole run
	var angle := atan2(rise, run_len)
	var hyp := sqrt(rise * rise + run_len * run_len)
	var centre: Vector3 = start + dir * (run_len * 0.5) + Vector3(0, rise * 0.5, 0)
	var size2: Vector3
	var rot: Vector3
	if absf(dir.z) > 0.5:
		size2 = Vector3(width, 0.24, hyp)
		rot = Vector3(-angle * signf(dir.z), 0, 0)
	else:
		size2 = Vector3(hyp, 0.24, width)
		rot = Vector3(0, 0, angle * signf(dir.x))
	cols.append({"ramp": true, "pos": centre, "size": size2, "rot": rot})

# ------------------------------------------------------------------ main

static func build(b: MeshBatch, rng: RandomNumberGenerator, c: Vector3, w: float, d: float,
		wall: Color, roof: Color, facing: float) -> Array:
	var cols: Array = []
	var fz := 1.0 if facing >= 0.0 else -1.0
	var hw := w * 0.5
	var hd := d * 0.5
	var wall_in := wall.lerp(C_WALL_IN, 0.55)

	# ---- plinth + ground floor surface
	_bx(b, cols, c + Vector3(0, -0.16, 0), Vector3(w + 0.9, 0.32, d + 0.9), CityConfig.C_CONCRETE_D)
	b.plate(MeshBatch.SOLID, c + Vector3(0, 0.005, 0), Vector2(w - T, d - T), C_FLOOR_T, 0.0)
	b.plate(MeshBatch.SOLID, c + Vector3(0, 0.012, 0), Vector2(w * 0.42, d * 0.34), Color("8e5f3c"), 0.0)
	# a couple of clear floor spots for loot: the middle of the ground floor and
	# the open landing upstairs (the stairs run down the left wall)
	rooms.append({"pos": c + Vector3(0.55, 0.06, 0.35), "floor": 0})
	rooms.append({"pos": c + Vector3(-0.55, 0.06, 0.95), "floor": 0})
	rooms.append({"pos": c + Vector3(0.70, F2 + 0.06, 0.30), "floor": 1})
	rooms.append({"pos": c + Vector3(-0.35, F2 + 0.06, 1.05), "floor": 1})

	# ---- ground floor walls
	# front wall (door + two windows), back wall (two windows), sides (one each)
	var fz_off := hd * fz
	var bz_off := -hd * fz
	_wall(b, cols, c + Vector3(0, 0, fz_off), Vector3(1, 0, 0), w, F2,
		[[0.0, 1.5, 2.3]],
		[[-hw + 2.4, 1.5, 1.02, 2.16], [hw - 2.4, 1.5, 1.02, 2.16]], wall)
	_wall(b, cols, c + Vector3(0, 0, bz_off), Vector3(1, 0, 0), w, F2,
		[],
		[[-hw * 0.42, 1.6, 1.02, 2.16], [hw * 0.42, 1.6, 1.02, 2.16]], wall)
	_wall(b, cols, c + Vector3(-hw, 0, 0), Vector3(0, 0, 1), d, F2,
		[], [[0.0, 1.7, 1.02, 2.16]], wall)
	_wall(b, cols, c + Vector3(hw, 0, 0), Vector3(0, 0, 1), d, F2,
		[], [[0.0, 1.7, 1.02, 2.16]], wall)

	# ---- door frame, open leaf, porch
	var dz := fz_off
	_bx(b, cols, c + Vector3(0, 1.16, dz), Vector3(1.72, 0.12, T + 0.2), C_TRIM, false)
	_bx(b, cols, c + Vector3(0, 2.34, dz), Vector3(1.72, 0.14, T + 0.2), C_TRIM, false)
	_bx(b, cols, c + Vector3(0, 0.06, dz), Vector3(1.5, 0.06, 0.6), C_TRIM, false)
	doors.append({
		"pos": c + Vector3(0, 0.35, dz + fz * 1.5),
		"inside": c + Vector3(0, 0.35, dz - fz * 1.6),
		"yaw": 0.0 if fz > 0.0 else PI,
	})
	# door leaf swung open against the inside wall
	_bx(b, cols, c + Vector3(0.74, 1.14, dz - fz * 0.62), Vector3(1.42, 2.24, 0.08), C_DOOR, false)
	# porch + step
	_bx(b, cols, c + Vector3(0, 2.52, dz + fz * 0.85), Vector3(2.6, 0.16, 1.7), roof, false)
	_bx(b, cols, c + Vector3(0, -0.13, dz + fz * 1.3), Vector3(2.2, 0.34, 1.2), C_TRIM)
	_bx(b, cols, c + Vector3(0, -0.24, dz + fz * 2.1), Vector3(2.4, 0.16, 0.8), C_TRIM)
	for s in [-1.0, 1.0]:
		_bx(b, cols, c + Vector3(s * 1.15, 1.5, dz + fz * 1.6), Vector3(0.16, 2.1, 0.16), C_TRIM, false)
		_bx(b, cols, c + Vector3(s * 0.86, 1.55, dz + fz * 0.18), Vector3(0.28, 0.5, 0.22),
			CityConfig.C_GLOW_WIN, false, MeshBatch.GLOW)

	# ---- interior floor / ceiling (second floor slab with the stair hole)
	var sh_x := -hw + 1.05          # stair run centre
	var sh_w := 1.55
	var sh_z0 := -hd + 1.05         # run centre at the back wall
	var run1 := d - 3.4
	if run1 < 2.4:
		run1 = 2.4
	# first flight runs from the back wall towards the front along +Z
	var stair1_start := Vector3(c.x + sh_x, c.y, c.z + (sh_z0) * 1.0)
	var st1_end_z := sh_z0 + run1
	_stairs(b, cols, stair1_start, Vector3(0, 0, 1), sh_w, F2, run1, C_FLOOR_W)

	# second floor slab, minus the hole above the first flight
	var hole := Rect2(sh_x - sh_w * 0.5 - 0.1, sh_z0 - 0.2, sh_w + 0.2, run1 + 0.4)
	_floor_with_hole(b, cols, c, w, d, F2, hole, C_FLOOR_W)

	# ---- second floor walls (windows all round, no door)
	var f2y := F2
	_wall(b, cols, c + Vector3(0, f2y, fz_off), Vector3(1, 0, 0), w, ROOF - F2,
		[], [[-hw + 2.4, 1.5, 1.02, 2.16], [hw - 2.4, 1.5, 1.02, 2.16]], wall.lerp(C_WALL_IN, 0.2))
	_wall(b, cols, c + Vector3(0, f2y, bz_off), Vector3(1, 0, 0), w, ROOF - F2,
		[], [[-hw * 0.42, 1.6, 1.02, 2.16], [hw * 0.42, 1.6, 1.02, 2.16]], wall.lerp(C_WALL_IN, 0.2))
	_wall(b, cols, c + Vector3(-hw, f2y, 0), Vector3(0, 0, 1), d, ROOF - F2,
		[], [[0.0, 1.7, 1.02, 2.16]], wall.lerp(C_WALL_IN, 0.2))
	_wall(b, cols, c + Vector3(hw, f2y, 0), Vector3(0, 0, 1), d, ROOF - F2,
		[], [[0.0, 1.7, 1.02, 2.16]], wall.lerp(C_WALL_IN, 0.2))

	# ---- second flight up to the roof, on the other side of the house
	var st2_x := hw - 1.15
	var st2_start := Vector3(c.x + st2_x, c.y + F2, c.z + (hd - 1.05))
	var run2 := d - 3.6
	if run2 < 2.2:
		run2 = 2.2
	_stairs(b, cols, st2_start, Vector3(0, 0, -1), 1.45, ROOF_TOP - F2, run2, C_FLOOR_W)

	# ---- roof slab with its own hatch hole
	var rhole := Rect2(st2_x - 0.8, (hd - 1.05) - run2 - 0.2, 1.6, run2 + 0.4)
	_floor_with_hole(b, cols, c, w, d, ROOF, rhole, C_FLOOR_T, 0.23)
	# parapet
	for s in [-1.0, 1.0]:
		_bx(b, cols, c + Vector3(0, ROOF + 0.55, s * (hd + 0.09)), Vector3(w + 0.3, 1.0, 0.18), roof)
		_bx(b, cols, c + Vector3(s * (hw + 0.09), ROOF + 0.55, 0), Vector3(0.18, 1.0, d + 0.3), roof)

	# ---- roof props: water tank, AC units, a bench
	var tank := c + Vector3(-hw + 1.6, ROOF_TOP, -hd + 1.6)
	b.cylinder(MeshBatch.SOLID, tank + Vector3(0, 0.15, 0), 0.62, 0.62, 1.25, 10, Color("2f4a5a"))
	b.cylinder(MeshBatch.SOLID, tank + Vector3(0, 1.42, 0), 0.66, 0.62, 0.14, 10, Color("22343f"))
	_bx(b, cols, tank + Vector3(0, 0.08, 0), Vector3(1.5, 0.16, 1.5), CityConfig.C_CONCRETE_D)
	for i in 2:
		_bx(b, cols, c + Vector3(-2.4, ROOF_TOP + 0.4, -hd + 2.0 + float(i) * 1.6),
			Vector3(1.0, 0.8, 0.9), Color("b8bcb8"))
	_bx(b, cols, c + Vector3(0.2, ROOF_TOP + 0.42, hd - 1.5), Vector3(1.7, 0.12, 0.5), CityConfig.C_WOOD, false)

	# ---- ground floor furniture -------------------------------------------
	_furniture_living(b, cols, c, fz, w, d)
	_furniture_kitchen(b, cols, c, fz, w, d)
	# ---- first floor furniture --------------------------------------------
	_furniture_bedroom(b, cols, c, fz, w, d)
	# ---- lights on the ceiling of both floors
	for p in [Vector3(0.6, F2 - 0.22, 0.0), Vector3(-1.5, ROOF - 0.22, 0.3)]:
		b.box(MeshBatch.GLOW, c + p, Vector3(0.5, 0.08, 0.5), CityConfig.C_GLOW_WIN)
	return cols

## Floor slab with a rectangular hole in it (for the staircases).  All of the
## coordinates are house-local: x across the width, z across the depth.
static func _floor_with_hole(b: MeshBatch, cols: Array, c: Vector3, w: float, d: float, y: float,
		hole: Rect2, col: Color, thick: float = 0.20) -> void:
	var hw := w * 0.5 - T * 0.5
	var hd := d * 0.5 - T * 0.5
	var hx0: float = clampf(hole.position.x, -hw, hw)
	var hx1: float = clampf(hole.position.x + hole.size.x, -hw, hw)
	var hz0: float = clampf(hole.position.y, -hd, hd)
	var hz1: float = clampf(hole.position.y + hole.size.y, -hd, hd)
	# strip left of the hole (full depth)
	var lw := hx0 + hw
	if lw > 0.05:
		_bx(b, cols, c + Vector3(-hw + lw * 0.5, y, 0), Vector3(lw, thick, hd * 2.0), col)
	# strip right of the hole
	var rw := hw - hx1
	if rw > 0.05:
		_bx(b, cols, c + Vector3(hx1 + rw * 0.5, y, 0), Vector3(rw, thick, hd * 2.0), col)
	# strip behind the hole (between the two side strips)
	var bw := hz0 + hd
	if bw > 0.05:
		_bx(b, cols, c + Vector3((hx0 + hx1) * 0.5, y, -hd + bw * 0.5),
			Vector3(hx1 - hx0, thick, bw), col)
	# strip in front of the hole
	var fwd_l := hd - hz1
	if fwd_l > 0.05:
		_bx(b, cols, c + Vector3((hx0 + hx1) * 0.5, y, hz1 + fwd_l * 0.5),
			Vector3(hx1 - hx0, thick, fwd_l), col)

# ------------------------------------------------------------------ furniture

static func _sofa(b: MeshBatch, cols: Array, p: Vector3, yaw_x: bool, col: Color) -> void:
	var sx := 2.0
	var sz := 0.9
	if not yaw_x:
		var t := sx
		sx = sz
		sz = t
	_bx(b, cols, p + Vector3(0, 0.28, 0), Vector3(sx, 0.34, sz), col, true)
	_bx(b, cols, p + Vector3(0, 0.52, 0), Vector3(sx * 0.84, 0.16, sz * 0.84), col.lightened(0.16), false)
	_bx(b, cols, p + Vector3(0, 0.62, (-sz * 0.5 + 0.12) * 1.0), Vector3(sx, 0.55, 0.24), col.darkened(0.12), false)
	for s in [-1.0, 1.0]:
		_bx(b, cols, p + Vector3(s * (sx * 0.5 - 0.11), 0.5, 0), Vector3(0.22, 0.42, sz), col.darkened(0.08), false)

static func _table(b: MeshBatch, cols: Array, p: Vector3, sx: float, sz: float, h: float, col: Color) -> void:
	_bx(b, cols, p + Vector3(0, h, 0), Vector3(sx, 0.09, sz), col, true)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_bx(b, cols, p + Vector3(dx * (sx * 0.5 - 0.12), h * 0.5, dz * (sz * 0.5 - 0.12)),
				Vector3(0.09, h, 0.09), col.darkened(0.2), false)

static func _chair(b: MeshBatch, cols: Array, p: Vector3, yaw: float, col: Color) -> void:
	_bx(b, cols, p + Vector3(0, 0.46, 0), Vector3(0.46, 0.08, 0.46), col, false)
	_bx(b, cols, p + Vector3(0, 0.72, 0.2 * -cos(yaw)), Vector3(0.46, 0.46, 0.08), col.darkened(0.1), false)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_bx(b, cols, p + Vector3(dx * 0.18, 0.23, dz * 0.18), Vector3(0.06, 0.46, 0.06), col.darkened(0.25), false)

static func _bed(b: MeshBatch, cols: Array, p: Vector3, yaw_x: bool, col: Color) -> void:
	var sx := 1.5
	var sz := 2.05
	if yaw_x:
		var t := sx
		sx = sz
		sz = t
	_bx(b, cols, p + Vector3(0, 0.22, 0), Vector3(sx, 0.4, sz), Color("5c4029"))
	_bx(b, cols, p + Vector3(0, 0.5, 0), Vector3(sx * 0.94, 0.2, sz * 0.94), col)
	_bx(b, cols, p + Vector3(0, 0.58, -sz * 0.5 + 1.25), Vector3(sx * 0.9, 0.09, 1.1), col.lightened(0.3))
	_bx(b, cols, p + Vector3(-sx * 0.24, 0.66, -sz * 0.5 + 0.35), Vector3(0.66, 0.14, 0.36), Color("f2efe6"))
	_bx(b, cols, p + Vector3(sx * 0.24, 0.66, -sz * 0.5 + 0.35), Vector3(0.66, 0.14, 0.36), Color("f2efe6"))
	_bx(b, cols, p + Vector3(0, 0.62, -sz * 0.5 - 0.06), Vector3(sx + 0.1, 0.9, 0.12), Color("4a3320"))

static func _furniture_living(b: MeshBatch, cols: Array, c: Vector3, fz: float, w: float, d: float) -> void:
	# living room in the front right corner, clear of the staircase on the left
	var rug := c + Vector3(2.5, 0.02, fz * (d * 0.5 - 3.4))
	b.plate(MeshBatch.SOLID, rug, Vector2(3.4, 2.6), Color("8e3b34"), 0.02)
	_sofa(b, cols, c + Vector3(2.5, 0, fz * (d * 0.5 - 2.2)), true, Color("4a5a72"))
	_table(b, cols, rug, 1.3, 0.7, 0.38, CityConfig.C_WOOD)
	# TV on a stand, facing the sofa
	var tv := c + Vector3(2.5, 0, fz * (d * 0.5 - 4.7))
	_bx(b, cols, tv + Vector3(0, 0.28, 0), Vector3(2.0, 0.56, 0.5), Color("2a2620"))
	_bx(b, cols, tv + Vector3(0, 0.78, fz * 0.08), Vector3(1.6, 0.9, 0.09), Color("15181c"), false)
	b.box(MeshBatch.GLOW, tv + Vector3(0, 0.78, fz * 0.02), Vector3(1.45, 0.78, 0.02), Color("4fa8d8"))
	# bookshelf against the left wall, in front of the stairs
	var sh := c + Vector3(-w * 0.5 + 0.55, 0, fz * (d * 0.5 - 1.2))
	_bx(b, cols, sh + Vector3(0, 0.9, 0), Vector3(0.42, 1.8, 2.0), Color("6b4a2f"))
	for i in 3:
		b.box(MeshBatch.GLOW, sh + Vector3(0.24, 0.4 + float(i) * 0.5, 0), Vector3(0.03, 0.28, 1.7),
			Color("d8cba0").darkened(0.1 * float(i)))

static func _furniture_kitchen(b: MeshBatch, cols: Array, c: Vector3, fz: float, w: float, d: float) -> void:
	# kitchen run along the right wall at the back, dining set in the middle
	var kx := w * 0.5 - 0.75
	for i in 3:
		var p := c + Vector3(kx, 0, fz * (-d * 0.5 + 1.4 + float(i) * 1.5))
		_bx(b, cols, p + Vector3(0, 0.45, 0), Vector3(1.15, 0.9, 1.42), Color("cfc8b8"))
		_bx(b, cols, p + Vector3(0, 0.94, 0), Vector3(1.25, 0.10, 1.5), Color("3b4249"), false)
	var sp := c + Vector3(kx, 0, fz * (-d * 0.5 + 2.9))
	b.box(MeshBatch.GLOW, sp + Vector3(0, 0.98, 0), Vector3(0.7, 0.04, 0.6), Color("9fb0b8"))
	_bx(b, cols, sp + Vector3(-0.35, 1.25, 0), Vector3(0.08, 0.5, 0.08), Color("b8c0c4"), false)
	var fr := c + Vector3(kx, 0, fz * (-d * 0.5 + 5.2))
	_bx(b, cols, fr + Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 0.9), Color("d8dcdc"))
	_bx(b, cols, fr + Vector3(-0.52, 1.1, 0), Vector3(0.06, 1.2, 0.06), Color("9aa0a2"), false)
	# dining table in the open middle
	var dt := c + Vector3(-1.3, 0, fz * (d * 0.5 - 4.6))
	_table(b, cols, dt, 1.9, 1.1, 0.74, CityConfig.C_WOOD)
	_chair(b, cols, dt + Vector3(-0.6, 0, -0.95), 0.0, Color("4a5a72"))
	_chair(b, cols, dt + Vector3(0.6, 0, -0.95), 0.0, Color("4a5a72"))
	_chair(b, cols, dt + Vector3(-0.6, 0, 0.95), PI, Color("4a5a72"))
	_chair(b, cols, dt + Vector3(0.6, 0, 0.95), PI, Color("4a5a72"))

static func _furniture_bedroom(b: MeshBatch, cols: Array, c: Vector3, fz: float, w: float, d: float) -> void:
	# the second floor stays clear of both stair runs: the left/back hole and
	# the roof flight on the right, so everything sits in the middle band
	var y := F2 + 0.10
	_bed(b, cols, c + Vector3(-1.5, y, fz * 0.9), false, Color("c8b48e"))
	var ns := c + Vector3(-1.5 + 1.35, y, fz * (0.9 - 1.1))
	_bx(b, cols, ns + Vector3(0, 0.28, 0), Vector3(0.5, 0.56, 0.5), Color("6b4a2f"), false)
	b.cylinder(MeshBatch.SOLID, ns + Vector3(0, 0.56, 0), 0.06, 0.06, 0.3, 8, Color("333"))
	b.box(MeshBatch.GLOW, ns + Vector3(0, 0.92, 0), Vector3(0.34, 0.3, 0.34), CityConfig.C_GLOW_WIN)
	# desk by the front window
	var dsk := c + Vector3(2.6, y, fz * (d * 0.5 - 2.4))
	_table(b, cols, dsk, 1.6, 0.75, 0.74, Color("8a6a48"))
	_chair(b, cols, dsk + Vector3(-0.1, 0, -fz * 0.9), 0.0, Color("4a5a72"))
	b.box(MeshBatch.GLOW, dsk + Vector3(0, 0.86, 0), Vector3(0.5, 0.36, 0.06), Color("8fd9e8"))
	# wardrobe on the back wall between the two flights
	_bx(b, cols, c + Vector3(-1.0, y + 1.05, -fz * (d * 0.5 - 0.9)), Vector3(1.9, 2.1, 0.7), Color("6b4a2f"))
	b.plate(MeshBatch.SOLID, c + Vector3(0.6, y + 0.02, -fz * 1.2), Vector2(3.0, 2.2), Color("3f5a6a"), 0.0)
