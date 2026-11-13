class_name GunModel
extends Node3D

## Procedural gun models: receiver, barrel, hand guard, magazine, grip, stock,
## sights (iron or scope), plus the small details that make a weapon read as a
## weapon — ejection port, charging handle, trigger + guard, sling loops,
## muzzle brake, bipod, scope lens glow.  The muzzle always points down -Z,
## the same axis the avatar faces.

static func build(def: Dictionary) -> Node3D:
	var g := GunModel.new()
	g.name = "Gun"
	g._make(def)
	return g

var _mats: Dictionary = {}

func _mat(c: Color, metallic := 0.6, rough := 0.42) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), metallic, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	_mats[key] = m
	return m

func _box(p: Node3D, pos: Vector3, size: Vector3, col: Color, metallic := 0.6, rough := 0.42) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col, metallic, rough)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.add_child(mi)
	return mi

func _cyl(p: Node3D, pos: Vector3, r: float, length: float, col: Color, axis := Vector3(0, 0, 1),
		metallic := 0.75, rough := 0.3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat(col, metallic, rough)
	mi.position = pos
	var dir := axis.normalized()
	if absf(dir.z) > 0.9:
		mi.rotation.x = PI * 0.5
	elif absf(dir.x) > 0.9:
		mi.rotation.z = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.add_child(mi)
	return mi

func _glow(p: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := _box(p, pos, size, col)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m

func _make(def: Dictionary) -> void:
	var kind := int(def["kind"])
	var furn: Color = def["furniture"]
	var metal: Color = def["metal"]
	var dark := metal.darkened(0.45)
	var body := Node3D.new()
	add_child(body)

	match kind:
		Weapons.PISTOL:
			_box(body, Vector3(0, 0, -0.10), Vector3(0.045, 0.062, 0.26), metal, 0.8, 0.28)
			_box(body, Vector3(0, 0.012, -0.02), Vector3(0.050, 0.030, 0.20), dark, 0.7, 0.35)  # slide top
			_cyl(body, Vector3(0, 0.004, -0.235), 0.016, 0.10, dark)
			_box(body, Vector3(0, -0.085, 0.02), Vector3(0.042, 0.135, 0.058), furn, 0.2, 0.7) as MeshInstance3D
			# trigger guard + trigger
			_box(body, Vector3(0, -0.055, -0.045), Vector3(0.020, 0.052, 0.018), dark)
			_box(body, Vector3(0, -0.038, -0.062), Vector3(0.034, 0.010, 0.075), dark)
			# iron sights
			_box(body, Vector3(0, 0.030, -0.215), Vector3(0.012, 0.014, 0.010), dark)
			_box(body, Vector3(0, 0.030, 0.010), Vector3(0.028, 0.014, 0.010), dark)
			# ejection port
			_box(body, Vector3(0.024, 0.012, -0.055), Vector3(0.006, 0.024, 0.060), dark, 0.4, 0.6)

		Weapons.SMG:
			_box(body, Vector3(0, 0, -0.06), Vector3(0.058, 0.085, 0.40), metal, 0.7, 0.34)
			_box(body, Vector3(0, 0.010, -0.30), Vector3(0.050, 0.050, 0.14), dark)
			_cyl(body, Vector3(0, 0.010, -0.44), 0.018, 0.16, dark)
			_box(body, Vector3(0, 0.058, -0.10), Vector3(0.030, 0.016, 0.26), dark)     # top rail
			_box(body, Vector3(0, -0.075, -0.10), Vector3(0.052, 0.070, 0.16), furn, 0.2, 0.7)  # hand guard
			_box(body, Vector3(0.0, -0.150, 0.010), Vector3(0.044, 0.185, 0.062), furn, 0.2, 0.7)  # magazine
			_box(body, Vector3(0, -0.115, 0.115), Vector3(0.042, 0.130, 0.056), furn, 0.2, 0.7)   # grip
			_box(body, Vector3(0, -0.040, 0.175), Vector3(0.030, 0.030, 0.22), dark)              # wire stock
			_box(body, Vector3(0, 0.030, 0.300), Vector3(0.036, 0.115, 0.030), dark)
			_box(body, Vector3(0, 0.072, -0.36), Vector3(0.014, 0.026, 0.012), dark)   # front post
			_box(body, Vector3(0, 0.072, 0.02), Vector3(0.032, 0.022, 0.012), dark)
			_box(body, Vector3(0.030, 0.010, -0.02), Vector3(0.006, 0.020, 0.075), dark, 0.4, 0.6)
			_box(body, Vector3(0.026, 0.045, 0.06), Vector3(0.020, 0.014, 0.030), dark)   # charging handle

		Weapons.AR:
			_box(body, Vector3(0, 0, -0.02), Vector3(0.062, 0.105, 0.46), metal, 0.65, 0.36)
			_box(body, Vector3(0, 0.020, -0.34), Vector3(0.070, 0.078, 0.22), furn, 0.3, 0.55)   # hand guard
			for i in 4:
				_box(body, Vector3(0, 0.062, -0.26 - float(i) * 0.055), Vector3(0.072, 0.010, 0.030), dark)
			_cyl(body, Vector3(0, 0.018, -0.54), 0.017, 0.24, dark)
			_cyl(body, Vector3(0, 0.018, -0.665), 0.024, 0.055, dark)                            # muzzle brake
			_box(body, Vector3(0, 0.070, -0.10), Vector3(0.028, 0.014, 0.30), dark)              # rail
			_box(body, Vector3(0, 0.086, -0.02), Vector3(0.030, 0.024, 0.055), dark)             # rear sight
			_box(body, Vector3(0, 0.086, -0.42), Vector3(0.016, 0.030, 0.014), dark)             # front post
			_box(body, Vector3(0, -0.135, -0.030), Vector3(0.050, 0.170, 0.075), furn, 0.25, 0.6)  # curved mag
			_box(body, Vector3(0, -0.215, 0.010), Vector3(0.048, 0.090, 0.068), furn, 0.25, 0.6)
			_box(body, Vector3(0, -0.115, 0.105), Vector3(0.046, 0.135, 0.062), furn, 0.2, 0.7)    # grip
			_box(body, Vector3(0, 0.005, 0.245), Vector3(0.052, 0.090, 0.230), furn, 0.25, 0.6)    # stock
			_box(body, Vector3(0, 0.030, 0.360), Vector3(0.056, 0.110, 0.030), dark)
			_box(body, Vector3(0, -0.042, -0.030), Vector3(0.030, 0.012, 0.080), dark)             # trigger guard
			_box(body, Vector3(0.033, 0.020, -0.03), Vector3(0.006, 0.024, 0.070), dark, 0.4, 0.6)  # ejection port
			_box(body, Vector3(0.036, 0.050, 0.06), Vector3(0.024, 0.014, 0.034), dark)             # charging handle

		Weapons.SHOTGUN:
			_box(body, Vector3(0, 0, 0.0), Vector3(0.068, 0.110, 0.44), metal, 0.6, 0.38)
			_cyl(body, Vector3(0, 0.030, -0.44), 0.024, 0.52, dark)
			_cyl(body, Vector3(0, -0.022, -0.40), 0.020, 0.40, dark)      # magazine tube
			_box(body, Vector3(0, -0.030, -0.30), Vector3(0.072, 0.070, 0.20), furn, 0.25, 0.62)  # pump
			_box(body, Vector3(0, 0.080, -0.30), Vector3(0.014, 0.020, 0.014), dark)              # bead sight
			_box(body, Vector3(0, -0.110, 0.100), Vector3(0.048, 0.140, 0.064), furn, 0.2, 0.7)   # grip
			_box(body, Vector3(0, 0.010, 0.270), Vector3(0.058, 0.115, 0.230), furn, 0.25, 0.6)   # stock
			_box(body, Vector3(0, 0.040, 0.390), Vector3(0.062, 0.120, 0.030), dark)
			_box(body, Vector3(0, -0.040, 0.010), Vector3(0.032, 0.012, 0.080), dark)

		Weapons.LMG:
			_box(body, Vector3(0, 0, -0.02), Vector3(0.080, 0.135, 0.54), metal, 0.65, 0.36)
			_cyl(body, Vector3(0, 0.020, -0.56), 0.022, 0.60, dark)
			_box(body, Vector3(0, -0.030, -0.34), Vector3(0.078, 0.080, 0.26), furn, 0.3, 0.55)   # hand guard
			for i in 5:
				_box(body, Vector3(0, -0.070, -0.24 - float(i) * 0.05), Vector3(0.082, 0.016, 0.030), dark)
			_cyl(body, Vector3(0, -0.190, 0.030), 0.115, 0.085, dark, Vector3(1, 0, 0), 0.7, 0.45)  # drum mag
			_cyl(body, Vector3(0, -0.190, 0.030), 0.070, 0.095, furn, Vector3(1, 0, 0), 0.3, 0.6)
			_box(body, Vector3(0, -0.120, 0.140), Vector3(0.050, 0.145, 0.066), furn, 0.2, 0.7)
			_box(body, Vector3(0, 0.040, -0.10), Vector3(0.030, 0.018, 0.34), dark)              # top cover rail
			_box(body, Vector3(0, 0.100, -0.02), Vector3(0.034, 0.028, 0.060), dark)             # rear sight
			_box(body, Vector3(0, 0.098, -0.50), Vector3(0.016, 0.034, 0.014), dark)             # front post
			# bipod folded under the muzzle
			for s in [-1.0, 1.0]:
				var leg := Node3D.new()
				leg.position = Vector3(0, -0.02, -0.46)
				leg.rotation = Vector3(0.35, 0, s * 0.42)
				body.add_child(leg)
				_cyl(leg, Vector3(0, -0.11, 0), 0.010, 0.23, dark, Vector3(0, 1, 0))
			_box(body, Vector3(0, 0.010, 0.300), Vector3(0.058, 0.125, 0.220), furn, 0.25, 0.6)  # stock
			_box(body, Vector3(0, 0.045, 0.415), Vector3(0.062, 0.130, 0.030), dark)
			_box(body, Vector3(0, -0.045, -0.010), Vector3(0.034, 0.012, 0.085), dark)

		Weapons.SNIPER:
			_box(body, Vector3(0, 0, -0.04), Vector3(0.058, 0.100, 0.50), metal, 0.6, 0.4)
			_cyl(body, Vector3(0, 0.014, -0.62), 0.017, 0.74, dark)              # long barrel
			_cyl(body, Vector3(0, 0.014, -0.985), 0.026, 0.070, dark)            # muzzle brake
			for i in 3:
				_box(body, Vector3(0, 0.014, -1.02 + float(i) * 0.012), Vector3(0.062, 0.010, 0.008), dark)
			_box(body, Vector3(0, 0.010, -0.34), Vector3(0.070, 0.086, 0.36), furn, 0.25, 0.6)  # wooden fore-end
			_box(body, Vector3(0, -0.120, 0.150), Vector3(0.050, 0.150, 0.070), furn, 0.2, 0.7) # grip
			_box(body, Vector3(0, -0.005, 0.320), Vector3(0.060, 0.130, 0.290), furn, 0.25, 0.6) # stock
			_box(body, Vector3(0, 0.050, 0.470), Vector3(0.064, 0.140, 0.034), dark)            # butt pad
			_box(body, Vector3(0, 0.055, 0.180), Vector3(0.040, 0.055, 0.090), furn, 0.2, 0.7)   # cheek riser
			# bolt handle
			var bolt := Node3D.new()
			bolt.position = Vector3(0.035, 0.020, 0.06)
			bolt.rotation = Vector3(0, 0, -0.5)
			body.add_child(bolt)
			_cyl(bolt, Vector3(0.045, 0, 0), 0.010, 0.09, dark, Vector3(1, 0, 0))
			_box(bolt, Vector3(0.085, 0, 0), Vector3(0.030, 0.030, 0.030), dark)
			# scope
			var scope := Node3D.new()
			scope.position = Vector3(0, 0.135, -0.10)
			body.add_child(scope)
			_cyl(scope, Vector3.ZERO, 0.043, 0.36, Color("191b1e"), Vector3(0, 0, 1), 0.8, 0.28)
			_cyl(scope, Vector3(0, 0, 0.205), 0.052, 0.070, Color("191b1e"), Vector3(0, 0, 1), 0.8, 0.28)
			_cyl(scope, Vector3(0, 0, -0.215), 0.048, 0.080, Color("191b1e"), Vector3(0, 0, 1), 0.8, 0.28)
			# lens glow (reads as glass from the front)
			var lens := _cyl(scope, Vector3(0, 0, -0.256), 0.040, 0.012, Color("8fd9e8"), Vector3(0, 0, 1), 0.1, 0.05)
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.56, 0.85, 0.91)
			lm.emission_enabled = true
			lm.emission = Color(0.35, 0.75, 0.90)
			lm.emission_energy_multiplier = 0.8
			lm.metallic = 0.6
			lm.roughness = 0.06
			lens.material_override = lm
			for z in [-0.13, 0.10]:
				_box(scope, Vector3(0, -0.060, z), Vector3(0.070, 0.060, 0.030), dark)   # rings
			_box(scope, Vector3(0, 0.052, 0.02), Vector3(0.022, 0.030, 0.022), dark)    # turret
			_box(scope, Vector3(0.040, 0, 0.02), Vector3(0.026, 0.040, 0.040), dark)
			# bipod
			for s in [-1.0, 1.0]:
				var leg := Node3D.new()
				leg.position = Vector3(0, -0.03, -0.52)
				leg.rotation = Vector3(0.30, 0, s * 0.40)
				body.add_child(leg)
				_cyl(leg, Vector3(0, -0.10, 0), 0.009, 0.21, dark, Vector3(0, 1, 0))
			_box(body, Vector3(0, -0.045, 0.030), Vector3(0.032, 0.012, 0.080), dark)  # trigger guard
