class_name ExplosionFX
extends Node3D

## One-shot explosion: fireball, shockwave ring, smoke, debris and a short
## light flash.  Pure nodes with hand-rolled easing, no particles resource, so
## several can pop at once (the barrels chain react) without any hitch.

const LIFE := 0.85

var _t := 0.0
var _core: MeshInstance3D
var _ring: MeshInstance3D
var _smoke: MeshInstance3D
var _light: OmniLight3D
var _debris: Array = []

static func spawn(parent: Node, pos: Vector3, power: float = 1.0) -> ExplosionFX:
	var fx := ExplosionFX.new()
	fx.position = pos
	parent.add_child(fx)
	fx._build(power)
	return fx

func _build(power: float) -> void:
	# fireball
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	_core.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.62, 0.16, 1.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.10)
	m.emission_energy_multiplier = 9.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core.material_override = m
	_core.scale = Vector3.ONE * 0.4
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	# ground shockwave ring
	_ring = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.08
	cm.radial_segments = 22
	cm.rings = 1
	_ring.mesh = cm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.85, 0.55, 0.85)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.75, 0.35)
	rm.emission_energy_multiplier = 4.0
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rm
	_ring.position = Vector3(0, 0.1, 0)
	_ring.scale = Vector3.ONE * 0.5
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# smoke ball
	_smoke = MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 1.0
	gm.height = 2.0
	gm.radial_segments = 10
	gm.rings = 6
	_smoke.mesh = gm
	var gm2 := StandardMaterial3D.new()
	gm2.albedo_color = Color(0.56, 0.54, 0.51, 0.55)
	gm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke.material_override = gm2
	_smoke.position = Vector3(0, 0.9, 0)
	_smoke.scale = Vector3.ONE * 0.6
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.25)
	_light.light_energy = 14.0 * power
	_light.omni_range = 22.0
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)

	# debris shards
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 37.0) + int(position.z * 91.0)
	for i in 7:
		var d := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.12, 0.3)
		bm.size = Vector3(s, s * 0.6, s)
		d.mesh = bm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color("8a2f22")
		d.material_override = dm
		d.position = Vector3(rng.randf_range(-0.3, 0.3), 0.6, rng.randf_range(-0.3, 0.3))
		add_child(d)
		_debris.append({
			"n": d,
			"v": Vector3(rng.randf_range(-7, 7), rng.randf_range(6, 13), rng.randf_range(-7, 7)),
			"spin": Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9)),
		})

func _process(dt: float) -> void:
	_t += dt
	var k := clampf(_t / LIFE, 0.0, 1.0)
	# fireball: fast punch out, quick fade
	var fb := clampf(_t / 0.18, 0.0, 1.0)
	_core.scale = Vector3.ONE * (0.5 + fb * 3.6) * (1.0 - k * 0.35)
	var cmat := _core.material_override as StandardMaterial3D
	cmat.albedo_color.a = clampf(1.0 - fb * 1.15, 0.0, 1.0)
	cmat.emission_energy_multiplier = 9.0 * clampf(1.0 - fb, 0.0, 1.0)
	_core.visible = cmat.albedo_color.a > 0.02
	# ring: expands the whole life
	var rk := clampf(_t / 0.55, 0.0, 1.0)
	_ring.scale = Vector3.ONE * (0.6 + rk * 9.0)
	var rmat := _ring.material_override as StandardMaterial3D
	rmat.albedo_color.a = clampf(1.0 - rk, 0.0, 1.0) * 0.9
	_ring.visible = rk < 0.99
	# smoke: rises and swells slowly
	var smk := clampf(_t / 0.75, 0.0, 1.0)
	_smoke.scale = Vector3.ONE * (0.8 + smk * 3.4)
	_smoke.position.y = 1.1 + smk * 3.4
	var smat := _smoke.material_override as StandardMaterial3D
	smat.albedo_color.a = clampf(0.55 - smk * 0.55, 0.0, 1.0)
	_smoke.visible = smat.albedo_color.a > 0.02
	# light
	_light.light_energy = maxf(0.0, 14.0 * (1.0 - clampf(_t / 0.28, 0.0, 1.0)))
	# debris
	for d in _debris:
		var n: Node3D = d["n"]
		var v: Vector3 = d["v"]
		v.y -= 26.0 * dt
		n.position += v * dt
		if n.position.y < 0.08:
			n.position.y = 0.08
			v.y = -v.y * 0.32
			v.x *= 0.62
			v.z *= 0.62
		var sp: Vector3 = d["spin"]
		n.rotation += sp * dt * 0.4
		d["v"] = v
	if _t > LIFE:
		queue_free()
