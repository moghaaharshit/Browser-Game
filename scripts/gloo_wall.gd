class_name GlooWall
extends Node3D

## A Free-Fire gloo wall: a glowing translucent panel you drop in front of you
## for instant cover.  Only three can exist at a time — CombatSystem frees the
## oldest one when you place a fourth.

const W := 3.2
const H := 2.7
const T := 0.22

var body: StaticBody3D

static func create(pos: Vector3, face_yaw: float) -> GlooWall:
	var g := GlooWall.new()
	g.position = pos
	g.rotation.y = face_yaw
	return g

func _ready() -> void:
	name = "GlooWall"
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W, H, T)
	panel.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.80, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.30, 0.70, 1.0)
	m.emission_energy_multiplier = 0.9
	m.roughness = 0.12
	m.metallic = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel.material_override = m
	panel.position = Vector3(0, H * 0.5, 0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)

	# frame: two posts and a top bar, so it reads as a solid object
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.72, 0.90, 1.0)
	frame.emission_enabled = true
	frame.emission = Color(0.45, 0.80, 1.0)
	frame.emission_energy_multiplier = 1.3
	for x in [-W * 0.5 + 0.08, W * 0.5 - 0.08]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.16, H, T + 0.06)
		post.mesh = pm
		post.material_override = frame
		post.position = Vector3(x, H * 0.5, 0)
		add_child(post)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(W, 0.16, T + 0.06)
	top.mesh = tm
	top.material_override = frame
	top.position = Vector3(0, H - 0.08, 0)
	add_child(top)

	body = StaticBody3D.new()
	body.name = "GlooBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H, T + 0.1)
	cs.shape = bs
	cs.position = Vector3(0, H * 0.5, 0)
	body.add_child(cs)
	body.set_meta("gloo", self)
	add_child(body)

	# gentle pop-in
	scale = Vector3(1.0, 0.06, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
