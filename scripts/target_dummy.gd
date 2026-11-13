class_name TargetDummy
extends Node3D

## A shooting-range bot: a full procedural body with separate head and body
## hit boxes, so headshots are real (any hit on the head box is a kill with
## every rifle / sniper).  Kneel-and-respawn behaviour keeps a fight going.

const HP := 100.0

var hp := HP
var dead := false
var model: AvatarModel
var _fall := 0.0
var _respawn := 0.0
var _flash := 0.0
var _bodies: Array = []

static func create(pos: Vector3, yaw: float) -> TargetDummy:
	var d := TargetDummy.new()
	d.position = pos
	d.rotation.y = yaw
	return d

func _ready() -> void:
	name = "Dummy"
	model = AvatarModel.new()
	add_child(model)
	_pose_arms()
	_hitbox(Vector3(0, 1.70, 0), Vector3(0.30, 0.30, 0.30), true)     # head
	_hitbox(Vector3(0, 1.10, 0), Vector3(0.56, 0.72, 0.34), false)    # chest
	_hitbox(Vector3(0, 0.50, 0), Vector3(0.44, 0.90, 0.30), false)    # legs

## Arms up in a shooting stance (AvatarModel exposes every joint pivot).
func _pose_arms() -> void:
	if model == null:
		return
	model.sh_l.rotation = Vector3(1.15, 0.0, 0.32)
	model.sh_r.rotation = Vector3(1.30, 0.0, -0.20)
	model.el_l.rotation = Vector3(-1.15, 0.0, 0.0)
	model.el_r.rotation = Vector3(-1.35, 0.0, 0.0)
	model.thigh_l.rotation = Vector3(0.0, 0.0, 0.06)
	model.thigh_r.rotation = Vector3(0.0, 0.0, -0.06)

func _hitbox(pos: Vector3, size: Vector3, head: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 8
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
	body.set_meta("dummy", self)
	body.set_meta("head", head)
	add_child(body)
	_bodies.append(body)

## Returns true when this hit killed the dummy.
func take_hit(damage: float, head: bool) -> bool:
	if dead:
		return false
	_flash = 1.0
	var dmg := damage
	if head:
		dmg = maxf(damage * 2.0, 999.0)     # a headshot always drops a bot
	hp -= dmg
	if hp <= 0.0:
		_die()
		return true
	return false

func _die() -> void:
	dead = true
	_fall = 0.0
	_respawn = 6.0
	for b in _bodies:
		(b as StaticBody3D).collision_layer = 0

func _process(dt: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
	# simple idle sway so they are not statues
	if not dead and model != null:
		var t := Time.get_ticks_msec() * 0.001
		model.hips.position.y = AvatarModel.HIP_Y - 0.02 + sin(t * 1.6) * 0.012
		model.spine.rotation = Vector3(0.02, sin(t * 0.7) * 0.10, 0.0)
	if dead:
		_fall = minf(1.0, _fall + dt * 2.4)
		rotation.x = -PI * 0.5 * ease(_fall, 0.4)
		_respawn -= dt
		if _respawn <= 0.0:
			_revive()

func _revive() -> void:
	dead = false
	hp = HP
	_fall = 0.0
	rotation.x = 0.0
	for b in _bodies:
		(b as StaticBody3D).collision_layer = 1 | 8
