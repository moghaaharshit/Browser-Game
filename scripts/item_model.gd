class_name ItemModel
extends RefCounted

## Small hand-held models for the carried items: a grenade, a gloo-wall canister
## and a medkit.  The gun models live in GunModel; these are what shows in the
## player's hand when the weapon wheel has a consumable selected.

const SOLID := MeshBatch.SOLID
const GLOW := MeshBatch.GLOW

## Returns a Node3D the walker can mount in its hand.  Roughly 0.30 m tall.
static func build(kind: String) -> Node3D:
	var b := MeshBatch.new()
	match kind:
		"grenade":
			b.cylinder(SOLID, Vector3(0, -0.06, 0), 0.055, 0.055, 0.12, 10, Color("4a5a36"))
			b.cylinder(SOLID, Vector3(0, 0.06, 0), 0.050, 0.048, 0.02, 10, Color("39472a"))
			b.cylinder(SOLID, Vector3(0, 0.08, 0), 0.022, 0.022, 0.035, 8, Color("767c62"))
			b.box(SOLID, Vector3(0.038, 0.085, 0), Vector3(0.055, 0.014, 0.022), Color("9aa08c"))
			# lever that springs off when the pin goes
			b.box(SOLID, Vector3(0, 0.105, 0.028), Vector3(0.014, 0.05, 0.012), Color("8b9199"))
			# pin ring
			b.cylinder(GLOW, Vector3(0.045, 0.10, 0), 0.018, 0.018, 0.006, 8, Color("d8b23a"), Vector3(0, 0, 1))
		"gloo":
			# a fat blue canister with a glowing seam, held like a briefcase
			b.box(SOLID, Vector3(0, -0.02, 0), Vector3(0.26, 0.30, 0.13), Color("3f9fe0"))
			b.box(SOLID, Vector3(0, 0.13, 0), Vector3(0.20, 0.05, 0.11), Color("2d7cb4"))
			b.box(GLOW, Vector3(0, -0.02, -0.068), Vector3(0.19, 0.21, 0.012), Color("9fe4ff"))
			b.box(SOLID, Vector3(0, 0.17, 0), Vector3(0.055, 0.06, 0.055), Color("1f2a36"))
			for i in 3:
				b.box(SOLID, Vector3(-0.08 + float(i) * 0.08, 0.155, 0), Vector3(0.02, 0.03, 0.03), Color("7fd0f5"))
		"medkit":
			b.box(SOLID, Vector3(0, -0.02, 0), Vector3(0.28, 0.22, 0.12), Color("e8eaee"))
			b.box(SOLID, Vector3(0, 0.095, 0), Vector3(0.20, 0.03, 0.10), Color("b9bfc6"))
			b.box(GLOW, Vector3(0, -0.02, -0.063), Vector3(0.13, 0.05, 0.012), Color("ff5a5a"))
			b.box(GLOW, Vector3(0, -0.02, -0.063), Vector3(0.05, 0.13, 0.012), Color("ff5a5a"))
			b.box(SOLID, Vector3(0, 0.115, 0), Vector3(0.09, 0.03, 0.03), Color("6b7079"))
		_:
			b.box(SOLID, Vector3(0, 0, 0), Vector3(0.16, 0.16, 0.16), Color("8b9199"))
	var root := Node3D.new()
	root.name = "Item_" + kind
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root
