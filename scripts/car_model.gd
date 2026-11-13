class_name CarModel
extends RefCounted

## Builds the playable vehicles out of boxes and cylinders.  Every type has its
## own proportions, ride height, wheel size and extras, so a jeep does not look
## like a van and a monster truck does not look like a sedan.
##
## Local space: forward is -Z (Godot convention), the car sits on y = 0.
##   sedan   – the everyday car
##   sports  – low, wide, big spoiler
##   suv     – tall 4x4 with roof rails
##   van     – long boxy panel van
##   pickup  – cab + open cargo bed
##   jeep    – short, boxy, roll cage, spare wheel, bull bar
##   monster – huge tyres, raised body, exhaust stacks
##   bike    – two wheels, frame, tank, seat, handlebars

const SOLID := MeshBatch.SOLID
const GLOW := MeshBatch.GLOW
const GLASS := MeshBatch.GLASS

const KINDS := ["sedan", "sports", "suv", "van", "pickup", "jeep", "monster", "bike"]

## Per-type numbers used by both the model and the physics.
const SPEC := {
	"sedan":   {"len": 4.30, "wid": 1.88, "wheel_r": 0.35, "wheel_w": 0.26, "base": 1.44,
		"track": 0.86, "ride": 0.12, "top": 50.0, "accel": 17.0, "steer": 1.85, "grip": 9.5,
		"brake": 34.0, "boost": 1.35, "mass_h": 1.0},
	"sports":  {"len": 4.45, "wid": 1.98, "wheel_r": 0.36, "wheel_w": 0.30, "base": 1.52,
		"track": 0.92, "ride": 0.08, "top": 62.0, "accel": 22.0, "steer": 1.95, "grip": 11.0,
		"brake": 40.0, "boost": 1.40, "mass_h": 0.86},
	"suv":     {"len": 4.60, "wid": 2.00, "wheel_r": 0.42, "wheel_w": 0.30, "base": 1.52,
		"track": 0.92, "ride": 0.22, "top": 46.0, "accel": 15.0, "steer": 1.72, "grip": 9.0,
		"brake": 32.0, "boost": 1.30, "mass_h": 1.22},
	"van":     {"len": 5.00, "wid": 2.02, "wheel_r": 0.37, "wheel_w": 0.28, "base": 1.70,
		"track": 0.94, "ride": 0.16, "top": 42.0, "accel": 13.5, "steer": 1.62, "grip": 8.6,
		"brake": 30.0, "boost": 1.26, "mass_h": 1.55},
	"pickup":  {"len": 4.95, "wid": 1.96, "wheel_r": 0.42, "wheel_w": 0.30, "base": 1.64,
		"track": 0.90, "ride": 0.22, "top": 44.0, "accel": 15.0, "steer": 1.70, "grip": 8.8,
		"brake": 31.0, "boost": 1.30, "mass_h": 1.20},
	"jeep":    {"len": 3.85, "wid": 1.90, "wheel_r": 0.47, "wheel_w": 0.34, "base": 1.34,
		"track": 0.92, "ride": 0.30, "top": 42.0, "accel": 16.5, "steer": 2.05, "grip": 10.5,
		"brake": 33.0, "boost": 1.32, "mass_h": 1.10},
	"monster": {"len": 5.10, "wid": 2.30, "wheel_r": 0.88, "wheel_w": 0.55, "base": 1.78,
		"track": 1.06, "ride": 1.80, "top": 38.0, "accel": 12.5, "steer": 1.40, "grip": 9.5,
		"brake": 28.0, "boost": 1.25, "mass_h": 1.70},
	"bike":    {"len": 2.10, "wid": 0.72, "wheel_r": 0.34, "wheel_w": 0.16, "base": 0.72,
		"track": 0.00, "ride": 0.10, "top": 58.0, "accel": 21.0, "steer": 2.35, "grip": 12.0,
		"brake": 30.0, "boost": 1.30, "mass_h": 0.9},
}

static func spec(kind: String) -> Dictionary:
	return SPEC.get(kind, SPEC["sedan"])

static var _wheel_meshes := {}

## One shared mesh per wheel size, so 166 cars do not each build their own.
static func wheel_mesh(r: float = 0.35, w: float = 0.26) -> ArrayMesh:
	var key := "%.2f_%.2f" % [r, w]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var b := MeshBatch.new()
	var x := Vector3(1, 0, 0)
	var hw := w * 0.5
	# tread blocks around the circumference: that is what makes a tyre read as
	# a tyre instead of a black disc
	var segs := 16
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(0, cos(a0), sin(a0)) * (r * 1.02)
		var d1 := Vector3(0, cos(a1), sin(a1)) * (r * 1.02)
		var n := ((d0 + d1) * 0.5 + Vector3(0, 0.001, 0)).normalized()
		b.quad(SOLID, Vector3(-hw * 0.86, 0, 0) + d0 * 0.98, Vector3(hw * 0.86, 0, 0) + d0 * 0.98,
			Vector3(hw * 0.86, 0, 0) + d1 * 0.98, Vector3(-hw * 0.86, 0, 0) + d1 * 0.98,
			Color("141518"), n)
	# carcass
	b.cylinder(SOLID, Vector3(-hw, 0, 0), r, r, w, 16, Color("101114"), x)
	b.cylinder(SOLID, Vector3(-hw * 1.06, 0, 0), r * 0.86, r * 0.86, w * 1.12, 16, Color("0d0e10"), x)
	# sidewall + alloy rim + hub + lug nuts
	b.cylinder(SOLID, Vector3(-hw * 1.10, 0, 0), r * 0.66, r * 0.66, w * 1.20, 14, Color("2a2d33"), x)
	b.cylinder(SOLID, Vector3(-hw * 1.14, 0, 0), r * 0.56, r * 0.56, w * 1.24, 12, Color("b9bfc6"), x)
	b.cylinder(SOLID, Vector3(-hw * 1.18, 0, 0), r * 0.20, r * 0.20, w * 1.30, 8, Color("8f959c"), x)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var c := Vector3(-hw * 0.7, cos(a) * r * 0.34, sin(a) * r * 0.34)
		b.cylinder(SOLID, c, r * 0.055, r * 0.055, w * 1.55, 4, Color("5d646b"), x)
	_wheel_meshes[key] = b.commit()
	return _wheel_meshes[key]

static func _taper(b: MeshBatch, y0: float, y1: float, bw: float, bd: float, tw: float, td: float,
		zoff: float, col: Color) -> void:
	var p0 := Vector3(-bw * 0.5, y0, -bd * 0.5)
	var p1 := Vector3(bw * 0.5, y0, -bd * 0.5)
	var p2 := Vector3(bw * 0.5, y0, bd * 0.5)
	var p3 := Vector3(-bw * 0.5, y0, bd * 0.5)
	var q0 := Vector3(-tw * 0.5, y1, -td * 0.5 + zoff)
	var q1 := Vector3(tw * 0.5, y1, -td * 0.5 + zoff)
	var q2 := Vector3(tw * 0.5, y1, td * 0.5 + zoff)
	var q3 := Vector3(-tw * 0.5, y1, td * 0.5 + zoff)
	b.quad(SOLID, p0, p1, q1, q0, col, Vector3(0, 0, -1))
	b.quad(SOLID, p2, p3, q3, q2, col, Vector3(0, 0, 1))
	b.quad(SOLID, p1, p2, q2, q1, col, Vector3(1, 0, 0))
	b.quad(SOLID, p3, p0, q0, q3, col, Vector3(-1, 0, 0))
	b.quad(SOLID, q0, q1, q2, q3, col, Vector3.UP)

## Returns { "root": Node3D, "wheels": Array[[Node3D, is_front]] , "wheel_r": float }
static func build(body_color: Color, kind: String = "sedan", police: bool = false,
		player: bool = true) -> Dictionary:
	var sp := spec(kind)
	var b := MeshBatch.new()
	var dark := body_color.darkened(0.35)
	var trim := CityConfig.C_METAL_D
	var L: float = sp["len"]
	var W: float = sp["wid"]
	var wr: float = sp["wheel_r"]
	var ww: float = sp["wheel_w"]
	var ride: float = sp["ride"]
	match kind:
		"bike":
			_build_bike(b, body_color, dark, trim, wr, ww)
		"monster":
			_build_monster(b, body_color, dark, trim, wr, L, W, ride)
		"jeep":
			_build_jeep(b, body_color, dark, trim, wr, L, W, ride)
		"van":
			_build_van(b, body_color, dark, trim, L, W, ride)
		"pickup":
			_build_pickup(b, body_color, dark, trim, L, W, ride)
		"suv":
			_build_body(b, body_color, dark, trim, L, W, ride, 1.36, 1.86, sp["base"], true, false)
		"sports":
			_build_body(b, body_color, dark, trim, L, W, ride, 1.04, 1.36, sp["base"], false, true)
		_:
			_build_body(b, body_color, dark, trim, L, W, ride, 1.26, 1.58, sp["base"], false, false)

	if police:
		b.box(SOLID, Vector3(0, ride + 1.32, 0.1), Vector3(0.9, 0.14, 0.4), CityConfig.C_DARK)
		b.box(GLOW, Vector3(-0.26, ride + 1.42, 0.1), Vector3(0.34, 0.16, 0.36), CityConfig.C_GLOW_RED)
		b.box(GLOW, Vector3(0.26, ride + 1.42, 0.1), Vector3(0.34, 0.16, 0.36), Color("2b6bff"))

	var root := Node3D.new()
	root.name = "CarModel_" + kind
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	root.add_child(mi)

	# ---- wheels
	var wheels: Array = []
	var mesh := wheel_mesh(wr, ww)
	var mount_y: float = wr
	if kind == "bike":
		for sz in [-1.0, 1.0]:
			var w := _wheel_node(mesh, Vector3(0.0, wr, sz * sp["base"]))
			root.add_child(w)
			wheels.append([w, sz < 0.0])
	else:
		for sz in [-1.0, 1.0]:
			for sx in [-1.0, 1.0]:
				var w := _wheel_node(mesh, Vector3(sx * sp["track"], mount_y, sz * sp["base"]))
				root.add_child(w)
				wheels.append([w, sz < 0.0])
	return {"root": root, "wheels": wheels, "wheel_r": wr}

static func _wheel_node(mesh: ArrayMesh, pos: Vector3) -> Node3D:
	var w := Node3D.new()
	w.position = pos
	var wm := MeshInstance3D.new()
	wm.mesh = mesh
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	w.add_child(wm)
	return w

# ---------------------------------------------------------------- body types

## Standard car: sills, body, bevelled shoulders, bonnet and boot lids, a
## tapered cabin with a real window band, bumpers, grille, mirrors, arches and
## lights.  Everything is placed relative to the wheelbase so the wheels sit in
## the arches instead of under the doors.
static func _build_body(b: MeshBatch, col: Color, dark: Color, trim: Color, L: float, W: float,
		ride: float, cab_h: float, cab_l: float, base: float, roof_rails: bool, spoiler: bool) -> void:
	var y0: float = ride
	var hw := W * 0.5
	# ---- lower body: sill, then the main tub
	b.box(SOLID, Vector3(0, y0 + 0.11, 0), Vector3(W - 0.10, 0.22, L - 0.18), dark)
	b.box(SOLID, Vector3(0, y0 + 0.44, 0), Vector3(W, 0.44, L), col)
	# ---- bevelled shoulder running round the whole car
	_taper(b, y0 + 0.66, y0 + 0.78, W, L, W - 0.14, L - 0.20, 0.0, col)
	# ---- bonnet and boot lids a touch lighter, so the panels read
	b.box(SOLID, Vector3(0, y0 + 0.80, -L * 0.285), Vector3(W - 0.20, 0.05, L * 0.33),
		col.lightened(0.05))
	b.box(SOLID, Vector3(0, y0 + 0.80, L * 0.330), Vector3(W - 0.22, 0.05, L * 0.26),
		col.lightened(0.03))
	# ---- cabin: tapered shell + window band + roof
	_taper(b, y0 + 0.78, y0 + cab_h, W - 0.12, cab_l, W - 0.36, cab_l * 0.66, 0.14, col)
	var win_h: float = clampf(cab_h - 0.90, 0.20, 0.30)
	var win_y: float = y0 + 0.78 + (cab_h - 0.78) * 0.48
	b.box(GLASS, Vector3(0, win_y, 0.14), Vector3(W - 0.20, win_h, cab_l * 0.78), Color("35505e"))
	b.box(GLASS, Vector3(0, win_y + 0.02, -cab_l * 0.5 + 0.16), Vector3(W - 0.40, win_h * 0.92, 0.07),
		Color("3c5866"))
	b.box(GLASS, Vector3(0, win_y + 0.02, cab_l * 0.5 + 0.06), Vector3(W - 0.44, win_h * 0.86, 0.07),
		Color("2c414c"))
	b.box(SOLID, Vector3(0, y0 + cab_h + 0.03, 0.14), Vector3(W - 0.34, 0.06, cab_l * 0.62),
		col.lightened(0.06))
	# A and B pillars
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * (W * 0.5 - 0.20), win_y, -cab_l * 0.34 + 0.14), Vector3(0.07, win_h + 0.10, 0.09), col)
		b.box(SOLID, Vector3(s * (W * 0.5 - 0.22), win_y, cab_l * 0.20 + 0.14), Vector3(0.07, win_h + 0.10, 0.08), col)
	# ---- bumpers, grille, plate
	b.box(SOLID, Vector3(0, y0 + 0.30, -L * 0.5 - 0.03), Vector3(W + 0.02, 0.30, 0.20), trim)
	b.box(SOLID, Vector3(0, y0 + 0.30, L * 0.5 + 0.03), Vector3(W + 0.02, 0.30, 0.20), trim)
	b.box(SOLID, Vector3(0, y0 + 0.56, -L * 0.5 - 0.05), Vector3(W * 0.46, 0.18, 0.06), Color("1b1d22"))
	b.box(SOLID, Vector3(0, y0 + 0.30, -L * 0.5 - 0.13), Vector3(0.62, 0.16, 0.04), Color("dfe3e7"))
	# ---- wheel arches: dark liners so the tyres sit in a hole, not under a wall
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			b.box(SOLID, Vector3(sx * (hw - 0.02), y0 + 0.20, sz * base),
				Vector3(0.10, 0.34, 0.98), Color("15171a"))
			# arch lip
			b.box(SOLID, Vector3(sx * (hw + 0.02), y0 + 0.32, sz * base),
				Vector3(0.06, 0.10, 1.06), trim)
	# ---- side detail: shut lines + handles
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * (hw + 0.005), y0 + 0.48, 0.10), Vector3(0.02, 0.36, 0.05), dark)
		b.box(SOLID, Vector3(s * (hw + 0.01), y0 + 0.52, -0.28), Vector3(0.03, 0.06, 0.24), trim)
		b.box(SOLID, Vector3(s * (hw + 0.01), y0 + 0.52, 0.52), Vector3(0.03, 0.06, 0.22), trim)
		# mirrors on a short stalk
		b.box(SOLID, Vector3(s * (hw + 0.06), y0 + 0.86, -cab_l * 0.46 + 0.14), Vector3(0.12, 0.05, 0.06), dark)
		b.box(SOLID, Vector3(s * (hw + 0.17), y0 + 0.88, -cab_l * 0.46 + 0.14), Vector3(0.22, 0.12, 0.24), dark)
	# ---- lights
	for s in [-1.0, 1.0]:
		b.box(GLOW, Vector3(s * W * 0.32, y0 + 0.56, -L * 0.5 - 0.06), Vector3(0.42, 0.16, 0.08),
			CityConfig.C_GLOW_WIN)
		b.box(GLOW, Vector3(s * W * 0.33, y0 + 0.60, L * 0.5 + 0.06), Vector3(0.44, 0.16, 0.08),
			CityConfig.C_GLOW_RED)
	b.box(GLOW, Vector3(0, y0 + 0.22, L * 0.5 + 0.14), Vector3(0.48, 0.10, 0.05), CityConfig.C_GLOW_WIN)
	if roof_rails:
		var rz: float = 0.14
		for s in [-1.0, 1.0]:
			b.box(SOLID, Vector3(s * (W * 0.31), y0 + cab_h + 0.11, rz),
				Vector3(0.07, 0.07, cab_l * 0.86), trim)
		for k in [-1.0, 1.0]:
			b.box(SOLID, Vector3(0, y0 + cab_h + 0.11, rz + k * cab_l * 0.32),
				Vector3(W * 0.62, 0.05, 0.10), trim)
	if spoiler:
		b.box(SOLID, Vector3(0, y0 + 0.96, L * 0.47), Vector3(W * 0.84, 0.06, 0.30), dark)
		for s in [-1.0, 1.0]:
			b.box(SOLID, Vector3(s * W * 0.33, y0 + 0.86, L * 0.47), Vector3(0.06, 0.22, 0.18), dark)
		# low side skirts + a front splitter, that is what makes it read "sports"
		for s in [-1.0, 1.0]:
			b.box(SOLID, Vector3(s * (hw + 0.01), y0 + 0.12, 0.0), Vector3(0.07, 0.12, L * 0.52), dark)
		b.box(SOLID, Vector3(0, y0 + 0.18, -L * 0.5 - 0.06), Vector3(W - 0.10, 0.07, 0.26), dark)

static func _build_van(b: MeshBatch, col: Color, dark: Color, trim: Color, L: float, W: float,
		ride: float) -> void:
	var y0 := ride
	b.box(SOLID, Vector3(0, y0 + 0.82, 0.1), Vector3(W, 1.62, L), col)
	b.box(SOLID, Vector3(0, y0 + 0.18, 0), Vector3(W - 0.06, 0.24, L - 0.1), dark)
	_taper(b, y0 + 1.42, y0 + 1.64, W - 0.02, L * 0.34, W - 0.12, L * 0.28, 0.28, col)
	# windscreen + side glass + rear doors
	b.box(GLASS, Vector3(0, y0 + 1.30, -L * 0.46), Vector3(W - 0.16, 0.52, 0.12), Color("3c5866"))
	for s in [-1.0, 1.0]:
		b.box(GLASS, Vector3(s * (W * 0.5 + 0.01), y0 + 1.28, -L * 0.18), Vector3(0.06, 0.46, 1.0), Color("3c5866"))
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.02), y0 + 0.80, 0.0), Vector3(0.04, 1.3, 0.06), dark)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.02), y0 + 0.86, L * 0.34), Vector3(0.04, 1.2, 0.05), dark)
	b.box(SOLID, Vector3(0, y0 + 0.86, L * 0.5 + 0.14), Vector3(W - 0.1, 1.5, 0.08), col.darkened(0.08))
	b.box(SOLID, Vector3(0, y0 + 0.86, L * 0.5 + 0.19), Vector3(0.05, 1.4, 0.05), dark)
	b.box(SOLID, Vector3(0, y0 + 0.30, -L * 0.5 - 0.02), Vector3(W + 0.02, 0.36, 0.26), trim)
	b.box(SOLID, Vector3(0, y0 + 0.30, L * 0.5 + 0.02), Vector3(W + 0.02, 0.36, 0.26), trim)
	for s in [-1.0, 1.0]:
		b.box(GLOW, Vector3(s * W * 0.34, y0 + 0.50, -L * 0.5 - 0.12), Vector3(0.42, 0.20, 0.1), CityConfig.C_GLOW_WIN)
		b.box(GLOW, Vector3(s * W * 0.36, y0 + 0.62, L * 0.5 + 0.16), Vector3(0.30, 0.34, 0.10), CityConfig.C_GLOW_RED)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.06), y0 + 1.30, -L * 0.40), Vector3(0.24, 0.14, 0.32), dark)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.01), y0 + 0.22, -L * 0.12), Vector3(0.06, 0.42, 0.8), trim)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.01), y0 + 0.22, L * 0.24), Vector3(0.06, 0.42, 0.9), trim)
	# roof panel sits down on the body, not hovering over it
	b.box(SOLID, Vector3(0, y0 + 1.66, 0.10), Vector3(W - 0.04, 0.07, L * 0.96), col.lightened(0.06))

static func _build_pickup(b: MeshBatch, col: Color, dark: Color, trim: Color, L: float, W: float,
		ride: float) -> void:
	var y0 := ride
	# chassis + cab (front half) + open bed (back half)
	b.box(SOLID, Vector3(0, y0 + 0.40, 0), Vector3(W, 0.42, L), col)
	b.box(SOLID, Vector3(0, y0 + 0.14, 0), Vector3(W - 0.06, 0.22, L - 0.1), dark)
	var cab_z := -L * 0.20
	b.box(SOLID, Vector3(0, y0 + 0.80, cab_z), Vector3(W - 0.10, 0.44, L * 0.34), col)
	_taper(b, y0 + 1.00, y0 + 1.42, W - 0.14, L * 0.32, W - 0.28, L * 0.24, 0.06, col)
	b.box(GLASS, Vector3(0, y0 + 1.16, cab_z), Vector3(W - 0.26, 0.36, L * 0.30), Color("3c5866"))
	b.box(GLASS, Vector3(0, y0 + 1.22, cab_z + L * 0.15), Vector3(W - 0.34, 0.30, 0.08), Color("3c5866"))
	b.box(SOLID, Vector3(0, y0 + 1.46, cab_z + 0.05), Vector3(W - 0.30, 0.06, L * 0.22), col.lightened(0.05))
	# cargo bed: floor + four walls
	b.box(SOLID, Vector3(0, y0 + 0.58, L * 0.24), Vector3(W - 0.16, 0.10, L * 0.44), dark.lightened(0.12))
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * (W * 0.5 - 0.07), y0 + 0.72, L * 0.24), Vector3(0.10, 0.40, L * 0.44), col)
	b.box(SOLID, Vector3(0, y0 + 0.72, L * 0.46), Vector3(W - 0.12, 0.40, 0.10), col)
	# bull bar + bumpers + lights
	b.box(SOLID, Vector3(0, y0 + 0.34, -L * 0.5 - 0.04), Vector3(W + 0.04, 0.34, 0.26), trim)
	b.box(SOLID, Vector3(0, y0 + 0.34, L * 0.5 + 0.02), Vector3(W + 0.02, 0.32, 0.24), trim)
	b.box(SOLID, Vector3(0, y0 + 0.66, -L * 0.5 - 0.10), Vector3(W * 0.8, 0.16, 0.14), Color("2b2e34"))
	for s in [-1.0, 1.0]:
		b.box(GLOW, Vector3(s * W * 0.32, y0 + 0.60, -L * 0.5 - 0.08), Vector3(0.40, 0.18, 0.1), CityConfig.C_GLOW_WIN)
		b.box(GLOW, Vector3(s * W * 0.38, y0 + 0.66, L * 0.5 + 0.06), Vector3(0.24, 0.26, 0.1), CityConfig.C_GLOW_RED)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.04), y0 + 1.14, cab_z - 0.1), Vector3(0.22, 0.12, 0.3), dark)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.01), y0 + 0.24, -L * 0.12), Vector3(0.06, 0.44, 0.86), trim)
		b.box(SOLID, Vector3(s * (W * 0.5 + 0.01), y0 + 0.24, L * 0.26), Vector3(0.06, 0.44, 0.94), trim)

static func _build_jeep(b: MeshBatch, col: Color, dark: Color, trim: Color, wr: float, L: float,
		W: float, ride: float) -> void:
	var y0 := ride
	b.box(SOLID, Vector3(0, y0 + 0.46, 0), Vector3(W, 0.62, L), col)
	b.box(SOLID, Vector3(0, y0 + 0.12, 0), Vector3(W - 0.04, 0.22, L - 0.06), dark)
	# flat bonnet + short screen + open top with a roll cage
	b.box(SOLID, Vector3(0, y0 + 0.80, -L * 0.28), Vector3(W - 0.10, 0.14, L * 0.42), col.lightened(0.04))
	b.box(GLASS, Vector3(0, y0 + 1.06, -L * 0.13), Vector3(W - 0.20, 0.40, 0.08), Color("3c5866"))
	b.box(SOLID, Vector3(0, y0 + 0.86, L * 0.34), Vector3(W - 0.14, 0.5, L * 0.28), col.darkened(0.10))
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * (W * 0.42), y0 + 1.28, -L * 0.10), Vector3(0.09, 0.60, 0.09), trim)
	b.box(SOLID, Vector3(0, y0 + 1.56, -L * 0.10), Vector3(W * 0.86, 0.08, 0.10), trim)
	b.box(SOLID, Vector3(0, y0 + 1.28, L * 0.34), Vector3(W * 0.86, 0.09, 0.09), trim)
	# bull bar, rock rails, snorkel, spare wheel on the tailgate
	b.box(SOLID, Vector3(0, y0 + 0.46, -L * 0.5 - 0.06), Vector3(W + 0.02, 0.50, 0.12), trim)
	b.box(SOLID, Vector3(0, y0 + 0.30, -L * 0.5 - 0.10), Vector3(W * 0.9, 0.12, 0.16), CityConfig.C_DARK)
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * (W * 0.5), y0 + 0.22, 0.0), Vector3(0.10, 0.14, L * 0.7), trim)
		b.box(GLOW, Vector3(s * W * 0.28, y0 + 0.72, -L * 0.5 - 0.10), Vector3(0.22, 0.22, 0.10), CityConfig.C_GLOW_WIN)
		b.box(GLOW, Vector3(s * W * 0.36, y0 + 0.62, L * 0.5 + 0.06), Vector3(0.20, 0.20, 0.10), CityConfig.C_GLOW_RED)
	b.box(SOLID, Vector3(-W * 0.34, y0 + 0.96, -L * 0.16), Vector3(0.12, 0.7, 0.14), trim)
	# spare wheel bolted to the tailgate (static, so it is part of the batch)
	b.box(SOLID, Vector3(0, y0 + 0.62, L * 0.5 + 0.14), Vector3(0.66, 0.66, 0.16), Color("1a1c20"))
	b.box(SOLID, Vector3(0, y0 + 0.62, L * 0.5 + 0.22), Vector3(0.30, 0.30, 0.06), Color("b9bfc6"))

static func _build_monster(b: MeshBatch, col: Color, dark: Color, trim: Color, wr: float,
		L: float, W: float, ride: float) -> void:
	var y0 := ride
	var tw := W * 0.40            # half width of the body, the wheels sit outside
	var base: float = spec("monster")["base"]
	var track: float = spec("monster")["track"]
	# ---- running gear: solid axles from side to side, springs up to the frame
	for sz in [-1.0, 1.0]:
		b.box(SOLID, Vector3(0, wr, sz * base), Vector3(track * 2.0 - 0.30, 0.20, 0.20), Color("2a2e35"))
		b.box(SOLID, Vector3(0, wr + 0.16, sz * base), Vector3(0.26, 0.26, 0.26), Color("3a4048"))
		for s in [-1.0, 1.0]:
			b.cylinder(SOLID, Vector3(s * track * 0.55, ride - 0.54, sz * base), 0.11, 0.11, 0.96, 8,
				Color("c3c8ce"))
	# ---- ladder frame under the body
	b.box(SOLID, Vector3(0, y0 - 0.10, 0), Vector3(tw * 2.0, 0.16, L * 0.88), dark)
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * tw * 0.75, y0 + 0.02, 0), Vector3(0.14, 0.18, L * 0.9), trim)
	# ---- body: hood, cab, bed
	var by := y0 + 0.10
	b.box(SOLID, Vector3(0, by + 0.28, 0), Vector3(tw * 2.0, 0.56, L * 0.86), col)
	b.box(SOLID, Vector3(0, by + 0.60, -L * 0.28), Vector3(tw * 1.86, 0.10, L * 0.26), col.lightened(0.05))
	# cab
	var cz := -L * 0.06
	b.box(SOLID, Vector3(0, by + 0.82, cz), Vector3(tw * 1.56, 0.48, L * 0.30), col)
	b.box(GLASS, Vector3(0, by + 0.86, cz), Vector3(tw * 1.44, 0.30, L * 0.28), Color("35505e"))
	b.box(SOLID, Vector3(0, by + 1.06, cz), Vector3(tw * 1.50, 0.07, L * 0.30), col.lightened(0.06))
	# bed at the back
	b.box(SOLID, Vector3(0, by + 0.34, L * 0.30), Vector3(tw * 1.90, 0.12, L * 0.28), dark.lightened(0.10))
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * tw * 0.92, by + 0.46, L * 0.30), Vector3(0.10, 0.36, L * 0.28), col)
	b.box(SOLID, Vector3(0, by + 0.46, L * 0.47), Vector3(tw * 1.86, 0.36, 0.10), col)
	# ---- fenders over all four wheels
	for sz in [-1.0, 1.0]:
		for s in [-1.0, 1.0]:
			# a fender that curls over the tyre instead of a flat wing
			b.box(SOLID, Vector3(s * (track - 0.06), ride + 0.14, sz * base),
				Vector3(0.58, 0.10, 1.44), col.lightened(0.04))
			b.box(SOLID, Vector3(s * (track + 0.16), ride + 0.04, sz * base),
				Vector3(0.10, 0.26, 1.44), col.lightened(0.02))
			b.box(SOLID, Vector3(s * (track - 0.30), y0 - 0.06, sz * base),
				Vector3(0.08, 0.26, 1.20), trim)
	# ---- roll cage over the bed
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * tw * 0.80, by + 1.02, L * 0.34), Vector3(0.09, 0.86, 0.09), trim)
	b.box(SOLID, Vector3(0, by + 1.44, L * 0.34), Vector3(tw * 1.70, 0.08, 0.09), trim)
	# ---- chrome stacks behind the cab
	for s in [-1.0, 1.0]:
		b.cylinder(SOLID, Vector3(s * tw * 0.62, by + 0.60, L * 0.10), 0.06, 0.06, 0.62, 8, Color("c3c8ce"))
		b.cylinder(SOLID, Vector3(s * tw * 0.62, by + 1.20, L * 0.10), 0.075, 0.075, 0.08, 8, Color("8f959c"))
	# ---- heavy bull bar, lights, tail lights
	b.box(SOLID, Vector3(0, by + 0.34, -L * 0.44), Vector3(tw * 1.94, 0.46, 0.14), trim)
	for s in [-1.0, 1.0]:
		b.box(GLOW, Vector3(s * tw * 0.62, by + 0.60, -L * 0.435), Vector3(0.26, 0.24, 0.10),
			CityConfig.C_GLOW_WIN)
		b.box(GLOW, Vector3(s * tw * 0.80, by + 0.42, L * 0.52), Vector3(0.22, 0.22, 0.10),
			CityConfig.C_GLOW_RED)
		b.box(GLOW, Vector3(s * tw * 0.50, by + 1.14, cz - L * 0.15), Vector3(0.20, 0.14, 0.08),
			CityConfig.C_GLOW_WIN)
	b.box(SOLID, Vector3(0, by + 0.18, L * 0.35), Vector3(tw * 1.6, 0.12, L * 0.3), trim)

static func _build_bike(b: MeshBatch, col: Color, dark: Color, trim: Color, wr: float, ww: float) -> void:
	# a bike is mostly air, so every part has to be where the eye expects it:
	# frame, engine, tank, seat, forks down to the axle, bars, guards, pipe
	var base: float = spec("bike")["base"]
	var fz := -base            # front axle
	var rz := base             # rear axle
	# ---- frame + engine
	b.box(SOLID, Vector3(0, 0.56, 0.0), Vector3(0.16, 0.14, base * 1.7), col)
	b.box(SOLID, Vector3(0, 0.40, -0.06), Vector3(0.34, 0.36, 0.44), Color("3a3f47"))
	b.box(SOLID, Vector3(0, 0.58, -0.06), Vector3(0.30, 0.06, 0.40), Color("8f959c"))
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * 0.15, 0.36, -0.02), Vector3(0.04, 0.34, 0.36), Color("6d747c"))
	# ---- tank + seat + tail
	b.box(SOLID, Vector3(0, 0.72, -0.24), Vector3(0.34, 0.24, 0.52), col.lightened(0.08))
	b.box(SOLID, Vector3(0, 0.74, -0.02), Vector3(0.26, 0.14, 0.12), col)
	b.box(SOLID, Vector3(0, 0.78, 0.30), Vector3(0.28, 0.10, 0.56), Color("1b1d22"))
	b.box(SOLID, Vector3(0, 0.70, 0.62), Vector3(0.24, 0.16, 0.20), col)
	# ---- front end: forks, mudguard, clamps, bars, headlight
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * 0.10, 0.55, fz + 0.16), Vector3(0.05, 0.52, 0.05), Color("b9bfc6"))
		b.box(SOLID, Vector3(s * 0.12, 0.44, rz - 0.20), Vector3(0.05, 0.10, 0.62), Color("4a5058"))
			# grips + levers
		b.box(SOLID, Vector3(s * 0.30, 0.94, fz + 0.20), Vector3(0.16, 0.06, 0.06), Color("22262e"))
		b.box(SOLID, Vector3(s * 0.13, 0.62, 0.44), Vector3(0.05, 0.05, 0.34), Color("8f959c"))
	b.box(SOLID, Vector3(0, 0.94, fz + 0.20), Vector3(0.62, 0.05, 0.05), trim)
	b.box(SOLID, Vector3(0, 0.86, fz + 0.18), Vector3(0.10, 0.16, 0.10), trim)
	b.box(SOLID, Vector3(0, 0.78, fz + 0.10), Vector3(0.26, 0.09, 0.42), col.darkened(0.12))
	b.box(SOLID, Vector3(0, 0.72, rz - 0.10), Vector3(0.24, 0.08, 0.36), col.darkened(0.12))
	# ---- lights, plate, exhaust
	b.box(GLOW, Vector3(0, 0.86, fz + 0.02), Vector3(0.20, 0.16, 0.08), CityConfig.C_GLOW_WIN)
	b.box(GLOW, Vector3(0, 0.72, rz + 0.06), Vector3(0.14, 0.10, 0.06), CityConfig.C_GLOW_RED)
	b.box(SOLID, Vector3(0, 0.56, rz + 0.06), Vector3(0.18, 0.12, 0.04), Color("dfe3e7"))
	b.cylinder(SOLID, Vector3(0.15, 0.40, 0.10), 0.05, 0.05, 0.66, 8, Color("a9b0b8"), Vector3(0, 0, 1))
	b.cylinder(SOLID, Vector3(0.15, 0.42, 0.60), 0.065, 0.065, 0.12, 8, Color("8f959c"), Vector3(0, 0, 1))
	# ---- foot pegs + chain guard
	for s in [-1.0, 1.0]:
		b.box(SOLID, Vector3(s * 0.22, 0.34, 0.10), Vector3(0.14, 0.04, 0.10), Color("22262e"))
	b.box(SOLID, Vector3(-0.14, 0.40, 0.42), Vector3(0.04, 0.12, 0.48), Color("2f343b"))
	# ---- the rider: a bike nobody is sitting on looks like a toy
	var jacket := Color("2b3550")
	var pants := Color("242a34")
	var skin := Color("c79a72")
	b.box(SOLID, Vector3(0, 0.96, 0.16), Vector3(0.34, 0.30, 0.26), jacket)
	b.box(SOLID, Vector3(0, 1.18, 0.09), Vector3(0.38, 0.26, 0.30), jacket.lightened(0.08))
	b.box(SOLID, Vector3(0, 1.36, 0.05), Vector3(0.24, 0.10, 0.24), skin)
	b.box(SOLID, Vector3(0, 1.47, 0.05), Vector3(0.26, 0.16, 0.26), Color("1b1d22"))
	b.box(GLOW, Vector3(0, 1.45, -0.08), Vector3(0.20, 0.09, 0.06), Color("2c414c"))
	for s in [-1.0, 1.0]:
		# upper arm then forearm down to the grip
		b.box(SOLID, Vector3(s * 0.22, 1.14, -0.10), Vector3(0.10, 0.30, 0.12), jacket)
		b.box(SOLID, Vector3(s * 0.27, 0.98, -0.34), Vector3(0.09, 0.14, 0.40), jacket.darkened(0.12))
		b.box(SOLID, Vector3(s * 0.29, 0.92, -0.52), Vector3(0.10, 0.10, 0.12), skin)
		# thigh, shin, boot
		b.box(SOLID, Vector3(s * 0.17, 0.86, 0.06), Vector3(0.15, 0.14, 0.40), pants)
		b.box(SOLID, Vector3(s * 0.21, 0.62, 0.24), Vector3(0.13, 0.34, 0.14), pants)
		b.box(SOLID, Vector3(s * 0.21, 0.44, 0.16), Vector3(0.14, 0.12, 0.28), Color("14161a"))
