class_name ExplosiveBarrel
extends Node3D

## A red fuel drum.  Hit it with a punch, ram it with a car or catch it in
## another blast and it goes up in a fireball (see ExplosionFX).  Two or three
## of them standing together chain react.

const R := 0.34
const H := 0.95

var alive := true
var _body: Node3D

static func create(pos: Vector3, tipped: bool = false) -> ExplosiveBarrel:
	var b := ExplosiveBarrel.new()
	b.position = pos
	if tipped:
		b.rotation = Vector3(0, randf() * TAU, PI * 0.5 - 0.08)
		b.position.y += 0.34
	return b

func _ready() -> void:
	name = "Barrel"
	_body = Node3D.new()
	add_child(_body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c0271d")
	mat.roughness = 0.42
	mat.metallic = 0.35
	mat.emission_enabled = true
	mat.emission = Color("7a0f0a")
	mat.emission_energy_multiplier = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("3a1c18")
	dark.roughness = 0.6
	dark.metallic = 0.5
	var hazard := StandardMaterial3D.new()
	hazard.albedo_color = Color("e8c33a")
	hazard.emission_enabled = true
	hazard.emission = Color("e8a020")
	hazard.emission_energy_multiplier = 0.5

	var drum := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R
	cm.bottom_radius = R
	cm.height = H
	cm.radial_segments = 16
	drum.mesh = cm
	drum.material_override = mat
	drum.position = Vector3(0, H * 0.5, 0)
	add_child(drum)

	for y in [0.16, 0.79]:
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = R + 0.022
		bm.bottom_radius = R + 0.022
		bm.height = 0.07
		bm.radial_segments = 16
		band.mesh = bm
		band.material_override = dark
		band.position = Vector3(0, y, 0)
		add_child(band)

	var stripe := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = R + 0.018
	sm.bottom_radius = R + 0.018
	sm.height = 0.16
	sm.radial_segments = 16
	stripe.mesh = sm
	stripe.material_override = hazard
	stripe.position = Vector3(0, 0.48, 0)
	add_child(stripe)

	var lid := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = R * 0.82
	lm.bottom_radius = R * 0.82
	lm.height = 0.06
	lm.radial_segments = 16
	lid.mesh = lm
	lid.material_override = dark
	lid.position = Vector3(0, H + 0.02, 0)
	add_child(lid)
	_make_solid()

## Solid + shootable: a static body the bullet raycast can hit.
func _make_solid() -> void:
	var body := StaticBody3D.new()
	body.name = "BarrelBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R
	cyl.height = H
	cs.shape = cyl
	cs.position = Vector3(0, H * 0.5, 0)
	body.add_child(cs)
	body.set_meta("barrel", self)
	add_child(body)

func world_pos() -> Vector3:
	return global_position + Vector3(0, 0.45, 0)
