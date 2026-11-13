class_name Grenade
extends RigidBody3D

## Free-Fire frag grenade: throw it, it bounces, the pin pops after the fuse and
## the blast hurts everything close (targets, barrels, the player).

const FUSE := 2.6
const BLAST := 8.5
const DAMAGE := 95.0

var fuse := FUSE
var _done := false
var combat: CombatSystem = null

static func create(pos: Vector3, vel: Vector3) -> Grenade:
	var g := Grenade.new()
	g.position = pos
	g.linear_velocity = vel
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	return g

func _ready() -> void:
	name = "Grenade"
	mass = 0.6
	continuous_cd = true
	contact_monitor = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.11
	cs.shape = sp
	add_child(cs)

	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("3d4a34")
	m.roughness = 0.6
	m.metallic = 0.35
	mi.material_override = m
	add_child(mi)

	# blinking top light so you can see it in flight
	var led := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.06, 0.05, 0.06)
	led.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("ff2b2b")
	lmat.emission_enabled = true
	lmat.emission = Color("ff2b2b")
	lmat.emission_energy_multiplier = 2.5
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.material_override = lmat
	led.position = Vector3(0, 0.12, 0)
	add_child(led)
	set_meta("led", led)

func _physics_process(dt: float) -> void:
	fuse -= dt
	var led := get_meta("led", null) as MeshInstance3D
	if led != null:
		led.visible = fmod(maxf(fuse, 0.0), 0.25) < 0.13
	if fuse <= 0.0 and not _done:
		_done = true
		_explode()

func _explode() -> void:
	var p := global_position
	if combat != null:
		combat.grenade_blast(p, BLAST, DAMAGE)
	ExplosionFX.spawn(get_parent(), p, 1.15)
	queue_free()
