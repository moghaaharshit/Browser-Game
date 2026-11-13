class_name MeshBatch
extends RefCounted

## A tiny vertex buffer helper.  Everything in the city (buildings, trees,
## road markings, cars, mountains) is authored with these primitives and then
## baked into a single ArrayMesh with 2 surfaces (solid + glowing), so a whole
## city block costs just 2 draw calls instead of hundreds of nodes.
##
## Vertex colours drive the albedo, and winding order is fixed automatically
## from the outward normal you supply, so faces can never end up inside-out.

const SOLID := 0
const GLOW := 1
const GLASS := 2

var _v: Dictionary = {}   # surface -> Array[Vector3]
var _n: Dictionary = {}   # surface -> Array[Vector3]
var _c: Dictionary = {}   # surface -> Array[Color]

# ---------------------------------------------------------------- internals

func _slot(k: int) -> void:
	if not _v.has(k):
		_v[k] = []
		_n[k] = []
		_c[k] = []

func is_empty() -> bool:
	for k in _v:
		if not (_v[k] as Array).is_empty():
			return false
	return true

func vertex_count() -> int:
	var t := 0
	for k in _v:
		t += (_v[k] as Array).size()
	return t

func _put(k: int, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
	_v[k].append(a)
	_v[k].append(b)
	_v[k].append(c)
	_n[k].append(n)
	_n[k].append(n)
	_n[k].append(n)
	_c[k].append(col)
	_c[k].append(col)
	_c[k].append(col)

# ---------------------------------------------------------------- primitives

## Triangle with an explicit outward normal (winding is auto-corrected).
func tri(k: int, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3 = Vector3.ZERO) -> void:
	_slot(k)
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		n = n.normalized()
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(n) > 0.0:
		_put(k, a, c, b, col, n)
	else:
		_put(k, a, b, c, col, n)

## Convex quad a-b-c-d (in order) with an explicit outward normal.
func quad(k: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	_slot(k)
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-12:
		cr = (c - a).cross(d - a)
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(n) > 0.0:
		_put(k, a, c, b, col, n)
		_put(k, a, d, c, col, n)
	else:
		_put(k, a, b, c, col, n)
		_put(k, a, c, d, col, n)

## Axis aligned box.  `top` lets you paint the roof a different colour.
func box(k: int, c: Vector3, s: Vector3, col: Color, top: Color = Color(-1, -1, -1, -1)) -> void:
	var h := s * 0.5
	var p0 := c + Vector3(-h.x, -h.y, -h.z)
	var p1 := c + Vector3(h.x, -h.y, -h.z)
	var p2 := c + Vector3(h.x, -h.y, h.z)
	var p3 := c + Vector3(-h.x, -h.y, h.z)
	var p4 := c + Vector3(-h.x, h.y, -h.z)
	var p5 := c + Vector3(h.x, h.y, -h.z)
	var p6 := c + Vector3(h.x, h.y, h.z)
	var p7 := c + Vector3(-h.x, h.y, h.z)
	var tc := col if top.r < 0.0 else top
	quad(k, p4, p5, p6, p7, tc, Vector3.UP)
	quad(k, p3, p2, p1, p0, col.darkened(0.35), Vector3.DOWN)
	quad(k, p0, p1, p5, p4, col, Vector3(0, 0, -1))
	quad(k, p2, p3, p7, p6, col, Vector3(0, 0, 1))
	quad(k, p1, p2, p6, p5, col, Vector3(1, 0, 0))
	quad(k, p3, p0, p4, p7, col, Vector3(-1, 0, 0))

## Flat horizontal quad (single sided, facing up).
func plate(k: int, center: Vector3, size: Vector2, col: Color, y_off: float = 0.0) -> void:
	var h := size * 0.5
	var c := center + Vector3(0, y_off, 0)
	quad(k,
		c + Vector3(-h.x, 0, -h.y), c + Vector3(-h.x, 0, h.y),
		c + Vector3(h.x, 0, h.y), c + Vector3(h.x, 0, -h.y),
		col, Vector3.UP)

## Vertical cylinder / cone (radius_top lets you taper it).
func cylinder(k: int, base: Vector3, r_bottom: float, r_top: float, h: float, segs: int,
		col: Color, axis: Vector3 = Vector3.UP, cap: bool = true) -> void:
	var ax := axis.normalized()
	var ref := Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var t1 := ref.cross(ax).normalized()
	var t2 := ax.cross(t1).normalized()
	var top := base + ax * h
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := t1 * cos(a0) + t2 * sin(a0)
		var d1 := t1 * cos(a1) + t2 * sin(a1)
		var n := ((d0 + d1) * 0.5 + ax * ((r_bottom - r_top) / maxf(h, 0.001))).normalized()
		if absf(r_bottom - r_top) < 0.001:
			n = ((d0 + d1) * 0.5).normalized()
		quad(k, base + d0 * r_bottom, base + d1 * r_bottom,
			top + d1 * r_top, top + d0 * r_top, col, n)
	if cap and r_top > 0.001:
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := t1 * cos(a0) + t2 * sin(a0)
			var d1 := t1 * cos(a1) + t2 * sin(a1)
			tri(k, top, top + d0 * r_top, top + d1 * r_top, col, ax)

## Four sided pyramid (hip roof).  `base_center` is the centre of the base.
func pyramid(k: int, base_center: Vector3, base: Vector2, h: float, col: Color) -> void:
	var hx := base.x * 0.5
	var hz := base.y * 0.5
	var apex := base_center + Vector3(0, h, 0)
	var a := base_center + Vector3(-hx, 0, -hz)
	var b := base_center + Vector3(hx, 0, -hz)
	var c := base_center + Vector3(hx, 0, hz)
	var d := base_center + Vector3(-hx, 0, hz)
	tri(k, a, b, apex, col, (b - a).cross(apex - a).normalized())
	tri(k, b, c, apex, col, (c - b).cross(apex - b).normalized())
	tri(k, c, d, apex, col, (d - c).cross(apex - c).normalized())
	tri(k, d, a, apex, col, (a - d).cross(apex - d).normalized())

## Gabled (triangular prism) roof.  Ridge runs along the X axis.
func gable(k: int, base_center: Vector3, w: float, d: float, h: float, col: Color,
		gable_col: Color = Color(-1, -1, -1, -1)) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var e0 := base_center + Vector3(-hw, 0, -hd)
	var e1 := base_center + Vector3(hw, 0, -hd)
	var e2 := base_center + Vector3(hw, 0, hd)
	var e3 := base_center + Vector3(-hw, 0, hd)
	var r0 := base_center + Vector3(-hw, h, 0)
	var r1 := base_center + Vector3(hw, h, 0)
	var gc := col.darkened(0.12) if gable_col.r < 0.0 else gable_col
	var n_back := Vector3(0, hd, -h).normalized()
	var n_front := Vector3(0, hd, h).normalized()
	quad(k, e0, e1, r1, r0, col, n_back)
	quad(k, e2, e3, r0, r1, col, n_front)
	tri(k, e0, r0, e3, gc, Vector3(-1, 0, 0))
	tri(k, e1, e2, r1, gc, Vector3(1, 0, 0))

# ---------------------------------------------------------------- baking

func commit(target: ArrayMesh = null) -> ArrayMesh:
	var mesh := target
	if mesh == null:
		mesh = ArrayMesh.new()
	for k in _v.keys():
		var verts: Array = _v[k]
		if verts.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(_n[k])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(_c[k])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Mats.get_mat(k))
	return mesh
