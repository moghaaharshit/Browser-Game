class_name LootItem
extends Node3D

## A pickup lying on the floor of a house or a shop: guns, ammo, body vests,
## helmets, grenades, gloo walls and medkits.  It bobs, spins and glows so you
## can spot it in a dark interior, and the player picks it up with E.

const KINDS := ["gun", "vest", "helmet", "grenade", "gloo", "medkit"]

static var all: Array = []          ## every live pickup, for the nearby check

var kind := "gun"
var amount := 1
var gun_index := 0
var _mesh: Node3D
var _t := 0.0
var _taken := false

static func make(kind_name: String, rng: RandomNumberGenerator) -> LootItem:
	var l := LootItem.new()
	l.kind = kind_name
	l.amount = 1
	match kind_name:
		"grenade":
			l.amount = rng.randi_range(1, 2)
		"gloo":
			l.amount = rng.randi_range(1, 2)
		"gun":
			l.gun_index = rng.randi_range(0, Weapons.count() - 1)
	return l

func _ready() -> void:
	name = "Loot_" + kind
	_t = randf() * TAU
	_build()
	all.append(self)

func _exit_tree() -> void:
	all.erase(self)

# ---------------------------------------------------------------- model

func _build() -> void:
	var b := MeshBatch.new()
	var rim := Color(0.35, 0.95, 1.0)
	match kind:
		"gun":
			# a stubby rifle silhouette so you can tell a gun from a box
			b.box(MeshBatch.SOLID, Vector3(0, 0.10, 0), Vector3(0.10, 0.13, 0.86), Color("3a3e45"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.20, 0.12), Vector3(0.09, 0.14, 0.34), Color("2b2e34"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.05, -0.30), Vector3(0.13, 0.16, 0.24), Color("7a5a34"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.03, 0.30), Vector3(0.10, 0.22, 0.16), Color("2b2e34"))
			b.box(MeshBatch.GLOW, Vector3(0, 0.13, -0.44), Vector3(0.05, 0.05, 0.05), Color("ffcc55"))
			rim = Color(1.0, 0.80, 0.35)
		"vest":
			b.box(MeshBatch.SOLID, Vector3(0, 0.16, 0), Vector3(0.52, 0.30, 0.20), Color("33452c"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.16, -0.11), Vector3(0.34, 0.22, 0.06), Color("405536"))
			for i in 3:
				b.box(MeshBatch.SOLID, Vector3(0, 0.06 + float(i) * 0.10, -0.14), Vector3(0.30, 0.05, 0.05), Color("5e6d42"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.30, 0.02), Vector3(0.46, 0.08, 0.22), Color("2b3a25"))
			rim = Color(0.55, 0.95, 0.45)
		"helmet":
			b.cylinder(MeshBatch.SOLID, Vector3(0, 0.05, 0), 0.20, 0.19, 0.14, 12, Color("3a4a2c"))
			b.cylinder(MeshBatch.SOLID, Vector3(0, 0.19, 0), 0.19, 0.11, 0.10, 12, Color("44562f"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.02, -0.20), Vector3(0.26, 0.04, 0.10), Color("2c3a22"))
			rim = Color(0.60, 0.95, 0.50)
		"grenade":
			b.cylinder(MeshBatch.SOLID, Vector3(0, 0.07, 0), 0.09, 0.09, 0.16, 10, Color("4a5a36"))
			b.cylinder(MeshBatch.SOLID, Vector3(0, 0.23, 0), 0.035, 0.035, 0.06, 8, Color("767c62"))
			b.box(MeshBatch.SOLID, Vector3(0.055, 0.24, 0), Vector3(0.10, 0.03, 0.04), Color("8f9480"))
			rim = Color(0.85, 0.95, 0.55)
		"gloo":
			b.box(MeshBatch.SOLID, Vector3(0, 0.22, 0), Vector3(0.42, 0.44, 0.16), Color("3f9fe0"))
			b.box(MeshBatch.GLOW, Vector3(0, 0.22, -0.09), Vector3(0.34, 0.36, 0.03), Color("9fe4ff"))
			rim = Color(0.45, 0.85, 1.0)
		"medkit":
			b.box(MeshBatch.SOLID, Vector3(0, 0.13, 0), Vector3(0.40, 0.26, 0.30), Color("e8eaee"))
			b.box(MeshBatch.GLOW, Vector3(0, 0.13, -0.16), Vector3(0.22, 0.06, 0.03), Color("ffffff"))
			b.box(MeshBatch.GLOW, Vector3(0, 0.13, -0.16), Vector3(0.06, 0.20, 0.03), Color("ffffff"))
			b.box(MeshBatch.SOLID, Vector3(0, 0.27, 0), Vector3(0.16, 0.04, 0.06), Color("9aa0a8"))
			rim = Color(1.0, 0.45, 0.45)
	# glowing floor ring so the pickup reads in the dark
	b.cylinder(MeshBatch.GLOW, Vector3(0, 0.02, 0), 0.30, 0.30, 0.02, 14, rim, Vector3.UP, false)
	_mesh = MeshInstance3D.new()
	_mesh.name = "LootMesh"
	(_mesh as MeshInstance3D).mesh = b.commit()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

func _process(dt: float) -> void:
	_t += dt
	if _mesh != null:
		_mesh.rotation.y = _t * 1.1
		_mesh.position.y = 0.06 + sin(_t * 1.7) * 0.035

# ---------------------------------------------------------------- pickup

func pretty_name() -> String:
	match kind:
		"gun":
			return String(Weapons.get_def(gun_index)["name"]) + " AMMO"
		"vest":
			return "BODY VEST"
		"helmet":
			return "HELMET"
		"grenade":
			return "GRENADE x%d" % amount
		"gloo":
			return "GLOO WALL x%d" % amount
		"medkit":
			return "MEDKIT"
	return kind

func collect(combat: CombatSystem) -> String:
	if _taken or combat == null:
		return ""
	_taken = true
	var msg := ""
	if kind == "gun":
		combat.add_ammo(gun_index, 30 + 20 * amount)
		# picking a gun up puts it in your hands straight away
		combat.equip_slot(gun_index)
		combat.equip_item(0)
		msg = pretty_name()
	else:
		msg = combat.give_item(kind, amount)
		if kind == "medkit" and combat.medkits > 0:
			msg = "MEDKIT  x%d" % combat.medkits
	queue_free()
	return msg

## Closest live pickup to a world point, or null.
static func nearest(p: Vector3, max_d: float = 2.6) -> LootItem:
	var best: LootItem = null
	var bd := max_d * max_d
	for l in all:
		if not is_instance_valid(l):
			continue
		var li: LootItem = l
		if li._taken:
			continue
		var d: float = li.global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = li
	return best
