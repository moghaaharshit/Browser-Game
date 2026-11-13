class_name AvatarModel
extends Node3D

## A fully procedural humanoid, built out of boxes at runtime.  No imported
## model, no skeleton resource: every joint is a plain Node3D pivot, so the
## walker script can pose it directly every frame (idle, walk, sprint, crouch,
## prone, jump, punches).
##
## Joint pivots all rotate around their own origin, children hang below them,
## and +X rotation swings a limb FORWARD (the avatar faces -Z, same as the car).

const SKIN := Color("c98f63")
const SKIN_D := Color("ac7550")
const HAIR := Color("2a2028")
const SHIRT := Color("2f6fa8")
const SHIRT_D := Color("255a8a")
const VEST := Color("1f2a36")
const PANTS := Color("38424f")
const PANTS_D := Color("2c3440")
const SHOE := Color("1d2027")
const BELT := Color("171a20")
const GLOVE := Color("22262e")
const EYE := Color("12151a")

var body: Node3D          ## whole body; used for lean / lying down
var hips: Node3D
var spine: Node3D
var neck: Node3D
var head: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hand_l: Node3D
var hand_r: Node3D

const HIP_Y := 1.00
const THIGH_L := 0.50
const SHIN_L := 0.47
const SHOULDER_Y := 0.46       ## above the hip joint
const SHOULDER_X := 0.235
const UPPER_ARM := 0.31
const FOREARM := 0.29

var _mats: Dictionary = {}

func _ready() -> void:
	name = "Avatar"
	_build()

func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var key := c.to_html() + ("g" if glow else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.82 if not glow else 0.35
	m.metallic = 0.0
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.4
	_mats[key] = m
	return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col, glow)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _pivot(parent: Node3D, pos: Vector3, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n

func _build() -> void:
	body = _pivot(self, Vector3(0, 0, 0), "Body")
	hips = _pivot(body, Vector3(0, HIP_Y, 0), "Hips")

	# ---- pelvis + belt
	_box(hips, Vector3(0, -0.06, 0), Vector3(0.34, 0.26, 0.23), PANTS)
	_box(hips, Vector3(0, 0.07, 0), Vector3(0.355, 0.06, 0.245), BELT)

	# ---- spine / chest
	spine = _pivot(hips, Vector3(0, 0.11, 0), "Spine")
	_box(spine, Vector3(0, 0.14, 0), Vector3(0.37, 0.30, 0.24), SHIRT)
	_box(spine, Vector3(0, 0.30, 0), Vector3(0.41, 0.22, 0.25), SHIRT)
	# tactical vest over the chest, with a shoulder strap
	_box(spine, Vector3(0, 0.22, 0), Vector3(0.325, 0.30, 0.265), VEST)
	_box(spine, Vector3(0, 0.22, -0.135), Vector3(0.30, 0.16, 0.02), Color("2b3947"))
	for s in [-1.0, 1.0]:
		_box(spine, Vector3(s * 0.12, 0.135, -0.15), Vector3(0.075, 0.075, 0.03), Color("3a4a5a"))

	# ---- neck + head
	neck = _pivot(spine, Vector3(0, 0.41, 0), "Neck")
	_box(neck, Vector3(0, 0.05, 0), Vector3(0.12, 0.10, 0.12), SKIN_D)
	head = _pivot(neck, Vector3(0, 0.10, 0), "Head")
	_box(head, Vector3(0, 0.12, 0), Vector3(0.21, 0.24, 0.22), SKIN)
	_box(head, Vector3(0, 0.245, 0.005), Vector3(0.225, 0.055, 0.235), HAIR)
	_box(head, Vector3(0, 0.17, 0.112), Vector3(0.20, 0.10, 0.02), HAIR)   # fringe
	for s in [-1.0, 1.0]:
		_box(head, Vector3(s * 0.055, 0.145, -0.108), Vector3(0.045, 0.03, 0.012), EYE)
	_box(head, Vector3(0, 0.075, -0.113), Vector3(0.06, 0.012, 0.01), SKIN_D)

	# ---- arms
	sh_l = _pivot(spine, Vector3(-SHOULDER_X, SHOULDER_Y, 0), "ShoulderL")
	sh_r = _pivot(spine, Vector3(SHOULDER_X, SHOULDER_Y, 0), "ShoulderR")
	for side in [[sh_l, -1.0], [sh_r, 1.0]]:
		var sh: Node3D = side[0]
		var s: float = side[1]
		_box(sh, Vector3(0, -0.02, 0), Vector3(0.135, 0.14, 0.15), SHIRT)       # deltoid
		_box(sh, Vector3(0, -UPPER_ARM * 0.5 - 0.04, 0), Vector3(0.115, UPPER_ARM, 0.125), SHIRT_D)
		var el := _pivot(sh, Vector3(0, -UPPER_ARM - 0.04, 0), "Elbow")
		_box(el, Vector3(0, -0.06, 0), Vector3(0.10, 0.13, 0.11), SKIN_D)      # elbow pad
		_box(el, Vector3(0, -FOREARM * 0.5 - 0.10, 0), Vector3(0.095, FOREARM, 0.10), SKIN)
		var hd := _pivot(el, Vector3(0, -FOREARM - 0.10, 0), "Hand")
		_box(hd, Vector3(0, -0.055, 0), Vector3(0.105, 0.115, 0.105), GLOVE)
		_box(hd, Vector3(0, -0.115, -0.02), Vector3(0.10, 0.075, 0.10), GLOVE)
		if s < 0.0:
			el_l = el
			hand_l = hd
		else:
			el_r = el
			hand_r = hd

	# ---- legs
	thigh_l = _pivot(hips, Vector3(-0.105, -0.02, 0), "ThighL")
	thigh_r = _pivot(hips, Vector3(0.105, -0.02, 0), "ThighR")
	for side in [[thigh_l, -1.0], [thigh_r, 1.0]]:
		var th: Node3D = side[0]
		_box(th, Vector3(0, -THIGH_L * 0.5, 0), Vector3(0.165, THIGH_L, 0.175), PANTS)
		var kn := _pivot(th, Vector3(0, -THIGH_L, 0), "Knee")
		_box(kn, Vector3(0, -0.02, 0), Vector3(0.155, 0.10, 0.165), PANTS_D)
		_box(kn, Vector3(0, -SHIN_L * 0.5 - 0.05, 0), Vector3(0.135, SHIN_L, 0.145), PANTS)
		_box(kn, Vector3(0, -SHIN_L - 0.02, 0), Vector3(0.145, 0.08, 0.16), SKIN_D)   # ankle
		var ft := _pivot(kn, Vector3(0, -SHIN_L - 0.05, 0), "Foot")
		_box(ft, Vector3(0, -0.04, -0.06), Vector3(0.15, 0.10, 0.28), SHOE)
		_box(ft, Vector3(0, -0.075, -0.185), Vector3(0.15, 0.045, 0.06), SHOE)
		if side[1] < 0.0:
			knee_l = kn
			foot_l = ft
		else:
			knee_r = kn
			foot_r = ft

func total_height() -> float:
	return HIP_Y + 0.95
