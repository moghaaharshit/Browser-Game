class_name CombatSystem
extends Node3D

## Free-Fire style gunplay: 10 weapons, drag-fire, aim-down-sights with a real
## sniper scope, headshots, grenades and gloo walls (three at a time, oldest one
## disappears when you place a fourth).
##
## Everything is hitscan: the shot is a raycast from the camera through the
## crosshair, so what you see in the middle of the screen is what you hit.

signal shot_fired(hit: bool, headshot: bool, killed: bool)
signal refresh()

const RAY_MASK := 1 | 2 | 8        ## world + cars + dummy hit boxes (never the player)
const MAX_MARKS := 28

var walker: PlayerWalker
var cam: Camera3D
var world: CityWorld
var audio_enabled := true

var gun_index := 4
var mag: Array = []
var reserve: Array = []
var reloading := false
var reload_left := 0.0
var cooldown := 0.0
var bloom := 0.0
var ads := false
var active := false

var gloo_walls: Array = []
var grenades := Weapons.GRENADE_MAX
## carried items.  Loot found in the houses fills these up.
var gloo_stock := 5
const GLOO_CAP := 5
const GLOO_REFILL := 10.0     ## seconds after a gloo wall goes down that the stock refills
var gloo_refill_left := 0.0
var medkits := 0
var vest := 0
var helmet := 0
## what the left mouse button does: 0 = the gun, 1 = grenade, 2 = gloo, 3 = medkit
var active_item := 0
var dummies: Array = []

var _marks: Array = []
var _fx: Array = []
var _recoil_kick := 0.0

func _ready() -> void:
	name = "Combat"
	for i in Weapons.count():
		mag.append(int(Weapons.get_def(i)["mag"]))
		reserve.append(int(Weapons.get_def(i)["reserve"]))

func setup(p_walker: PlayerWalker, p_cam: Camera3D, p_world: CityWorld) -> void:
	walker = p_walker
	cam = p_cam
	world = p_world
	_equip(gun_index)

# ------------------------------------------------------------------ weapons

func def() -> Dictionary:
	return Weapons.get_def(gun_index)

func gun_name() -> String:
	return String(def()["name"])

func mag_left() -> int:
	return int(mag[gun_index])

func reserve_left() -> int:
	return int(reserve[gun_index])

## Every gun now aims down a circular sight, so ADS always means "look through
## the optic".  Snipers get the full magnified scope, everything else a red-dot
## style ring at a gentler zoom.
func is_scoped() -> bool:
	return ads

func scope_kind() -> String:
	if not ads:
		return ""
	return String(def().get("sight", "reddot"))

func _equip(i: int) -> void:
	gun_index = ((i % Weapons.count()) + Weapons.count()) % Weapons.count()
	reloading = false
	reload_left = 0.0
	cooldown = 0.0
	bloom = 0.0
	_refresh_hands()
	refresh.emit()

## Whatever is "in hand" is a real model: the gun you equipped, or the grenade /
## gloo canister / medkit the wheel selected.
func _refresh_hands() -> void:
	if walker == null:
		return
	if active_item == 0:
		walker.set_held(GunModel.build(def()), "gun")
		return
	var kind := "grenade"
	if active_item == 2:
		kind = "gloo"
	elif active_item == 3:
		kind = "medkit"
	walker.set_held(ItemModel.build(kind), kind)

func next_gun(step: int) -> void:
	_equip(gun_index + step)

func equip_slot(i: int) -> void:
	if i >= 0 and i < Weapons.count():
		_equip(i)

func start_reload() -> void:
	if reloading or mag_left() >= int(def()["mag"]) or reserve_left() <= 0:
		return
	reloading = true
	reload_left = float(def()["reload"])
	refresh.emit()

func _finish_reload() -> void:
	reloading = false
	var need := int(def()["mag"]) - mag_left()
	var take := mini(need, reserve_left())
	mag[gun_index] = mag_left() + take
	reserve[gun_index] = reserve_left() - take
	refresh.emit()

# ------------------------------------------------------------------ loop

func _process(dt: float) -> void:
	if walker == null:
		return
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - dt)
	if bloom > 0.0:
		bloom = maxf(0.0, bloom - dt * 3.2)
	# a gloo wall refills itself ten seconds after it was used
	if gloo_refill_left > 0.0:
		gloo_refill_left = maxf(0.0, gloo_refill_left - dt)
		if gloo_refill_left <= 0.0 and gloo_stock < GLOO_CAP:
			gloo_stock = GLOO_CAP
			refresh.emit()
	if reloading:
		reload_left -= dt
		if reload_left <= 0.0:
			_finish_reload()
	# recoil is purely cosmetic (arms kick, crosshair blooms).  The aim itself
	# stays exactly where the mouse points, it must never climb on its own.
	if _recoil_kick > 0.0:
		_recoil_kick = maxf(0.0, _recoil_kick - dt * 6.0)
	# aiming down sights (hold right mouse) — the walker asks for it
	var want_ads := active and Input.is_action_pressed("aim")
	if want_ads != ads:
		ads = want_ads
		walker.aiming = ads
		refresh.emit()
	if walker.holding_gun != null:
		walker.gun_pitch = walker.pitch
	if not active:
		return
	# --- an item is in hand: one click uses it, the gun waits
	if active_item != 0:
		if Input.is_action_just_pressed("punch"):
			use_active_item()
		return
	# --- fire (drag fire: hold and keep firing, drag the mouse to steer)
	if Input.is_action_pressed("punch"):
		if reloading:
			pass
		elif cooldown <= 0.0:
			if mag_left() <= 0:
				start_reload()
			else:
				_fire_shot()

func _fire_shot() -> void:
	var d := def()
	cooldown = 60.0 / float(d["rpm"])
	mag[gun_index] = mag_left() - 1
	var cone := Weapons.cone(d, ads, walker.stance())
	cone += bloom * 1.1
	var origin: Vector3 = cam.global_position
	var base_dir: Vector3 = -cam.global_transform.basis.z
	var pellets := int(d["pellets"])
	var any_hit := false
	var head := false
	var killed := false
	for p in pellets:
		var dir := _spread(base_dir, cone)
		var res := _cast(origin, dir, float(d["range"]))
		if bool(res["hit"]):
			any_hit = true
			if bool(res["head"]):
				head = true
			if bool(res["kill"]):
				killed = true
			_spark(res["pos"], res["normal"], bool(res["head"]))
		_tracer(walker.gun_muzzle(), res["pos"] if bool(res["hit"]) else origin + dir * 120.0,
			d["tracer"])
	_muzzle_flash()
	bloom = minf(bloom + 0.40, 1.6)
	_recoil_kick += float(d["recoil"]) * 0.02
	walker.kick_arms(float(d["kick"]))
	# turn the whole body to the side you just fired at
	walker.face_aim(0.8)
	shot_fired.emit(any_hit, head, killed)
	refresh.emit()
	if mag_left() <= 0:
		start_reload()

func _spread(dir: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.001:
		return dir
	var rad := deg_to_rad(degrees)
	var a := randf() * TAU
	var r := sqrt(randf()) * rad
	var up_ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var right := dir.cross(up_ref).normalized()
	var up := right.cross(dir).normalized()
	return (dir * cos(r) + (right * cos(a) + up * sin(a)) * sin(r)).normalized()

## One hitscan ray. Returns {hit, pos, normal, head, kill}.
func _cast(origin: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * dist, RAY_MASK)
	q.hit_from_inside = false
	q.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"hit": false, "pos": origin + dir * dist, "normal": -dir, "head": false, "kill": false}
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	var col: Object = hit["collider"]
	var head := false
	var kill := false
	if col is Node:
		var node := col as Node
		var dummy: TargetDummy = null
		if node.has_meta("dummy"):
			dummy = node.get_meta("dummy") as TargetDummy
		if dummy != null:
			head = bool(node.get_meta("head", false))
			var dmg := float(def()["damage"])
			if head:
				dmg *= float(def()["head"])
			kill = dummy.take_hit(dmg, head)
			if kill and not dummies.has(dummy):
				dummies.append(dummy)
		elif node.has_meta("barrel"):
			var br := node.get_meta("barrel") as ExplosiveBarrel
			if br != null and world != null:
				world.detonate_barrel(br, 1.05)
	_impact_mark(pos, nrm)
	return {"hit": true, "pos": pos, "normal": nrm, "head": head, "kill": kill}

# ------------------------------------------------------------------ gloo / grenade

func place_gloo() -> bool:
	if walker == null or gloo_stock <= 0:
		return false
	gloo_stock -= 1
	gloo_refill_left = GLOO_REFILL
	var fwd := walker.planar_forward()
	var pos := walker.global_position + fwd * 2.5
	if world != null and world.island != null:
		pos.y = world.island.height(pos.x, pos.z) + 0.05
	var g := GlooWall.create(pos, walker.yaw)
	get_parent().add_child(g)
	gloo_walls.append(g)
	# only three at a time: the oldest one pops when the fourth goes down
	while gloo_walls.size() > Weapons.GLOO_MAX:
		var old: GlooWall = gloo_walls.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	refresh.emit()
	return true

func throw_grenade() -> bool:
	if grenades <= 0 or walker == null:
		return false
	grenades -= 1
	var fwd := walker.eye_forward()
	var start := walker.global_position + Vector3(0, 1.45, 0) + fwd * 0.6
	var g := Grenade.create(start, fwd * 21.0 + Vector3(0, 5.2, 0))
	g.combat = self
	get_parent().add_child(g)
	refresh.emit()
	return true

func grenade_blast(pos: Vector3, radius: float, damage: float) -> void:
	for d in dummies.duplicate():
		if not is_instance_valid(d):
			dummies.erase(d)
			continue
		var dd: TargetDummy = d
		var dist := dd.global_position.distance_to(pos)
		if dist < radius:
			var dmg := damage * (1.0 - dist / radius)
			dd.take_hit(dmg, false)
	if world != null:
		world.ram_barrels(pos, radius * 0.7, 1.2)
	if walker != null:
		var dv: Vector3 = walker.global_position - pos
		dv.y = 0.0
		if dv.length() < radius * 1.2:
			walker.velocity += dv.normalized() * 9.0 + Vector3(0, 3.5, 0)

# ------------------------------------------------------------------ items

const ITEM_NAMES := ["GUN", "GRENADE", "GLOO WALL", "MEDKIT"]

func equip_item(k: int) -> void:
	active_item = clampi(k, 0, 3)
	_refresh_hands()
	refresh.emit()

func item_label() -> String:
	if active_item == 1:
		return "GRENADE  x%d" % grenades
	if active_item == 2:
		return "GLOO  x%d" % gloo_stock
	if active_item == 3:
		return "MEDKIT  x%d" % medkits
	return gun_name()

## Called when the wheel or an item key was used.  Returns true when the item
## actually went off, so the HUD can tell the player why nothing happened.
func use_active_item() -> bool:
	match active_item:
		1:
			if throw_grenade():
				return true
			return false
		2:
			if place_gloo():
				return true
			return false
		3:
			return use_medkit()
	return false

func use_medkit() -> bool:
	if medkits <= 0:
		return false
	medkits -= 1
	if walker != null:
		walker.health = 100.0
	refresh.emit()
	return true

## Loot pickups.  Unknown kinds are ignored.
func give_item(kind: String, amount: int = 1) -> String:
	match kind:
		"grenade":
			grenades = mini(grenades + amount, 9)
			return "GRENADE +%d" % amount
		"gloo":
			gloo_stock = mini(gloo_stock + amount, 12)
			return "GLOO WALL +%d" % amount
		"medkit":
			medkits = mini(medkits + amount, 6)
			return "MEDKIT +%d" % amount
		"vest":
			vest = mini(vest + amount, 3)
			if walker != null:
				walker.armor = 100.0
			return "BODY VEST"
		"helmet":
			helmet = mini(helmet + amount, 3)
			if walker != null:
				walker.armor = minf(100.0, walker.armor + 50.0)
			return "HELMET"
		"gun":
			if walker != null:
				walker.health = 100.0
			return "GUN RACK"
	return ""

## Ammo for the gun that was just picked up off the floor.
func add_ammo(idx: int, rounds: int) -> void:
	if idx < 0 or idx >= reserve.size():
		return
	reserve[idx] = int(reserve[idx]) + rounds
	refresh.emit()

# ------------------------------------------------------------------ fx

func _tracer(from: Vector3, to: Vector3, col: Color) -> void:
	var d := to - from
	if d.length() < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.075, 0.075, d.length())
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	get_parent().add_child(mi)
	mi.global_position = from + d * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(mi.queue_free)

func _muzzle_flash() -> void:
	if walker == null or walker.holding_gun == null:
		return
	var p := walker.gun_muzzle()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.30
	sm.height = 0.60
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.62)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.45)
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	get_parent().add_child(mi)
	mi.global_position = p
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.55)
	light.light_energy = 3.4
	light.omni_range = 9.0
	light.shadow_enabled = false
	get_parent().add_child(light)
	light.global_position = p
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.09)
	lt.tween_callback(light.queue_free)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1.9, 1.9, 1.9), 0.05)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.07)
	tw.tween_callback(mi.queue_free)

func _spark(pos: Vector3, nrm: Vector3, head: bool) -> void:
	for i in (5 if not head else 9):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 0.05)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		var c := Color(1.0, 0.35, 0.25) if head else Color(1.0, 0.86, 0.55)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		get_parent().add_child(mi)
		mi.global_position = pos
		var dir := (nrm + Vector3(randf_range(-0.8, 0.8), randf_range(-0.2, 0.9), randf_range(-0.8, 0.8))).normalized()
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", pos + dir * randf_range(0.4, 1.1), 0.16)
		tw.parallel().tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), 0.16)
		tw.tween_callback(mi.queue_free)

func _impact_mark(pos: Vector3, nrm: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	get_parent().add_child(mi)
	mi.global_position = pos + nrm * 0.012
	var up := Vector3.UP if absf(nrm.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.look_at(pos + nrm, up)
	_marks.append(mi)
	while _marks.size() > MAX_MARKS:
		var old: Node3D = _marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()

# ------------------------------------------------------------------ dummies

## Put a row of shooting-range bots on the road near the player.
func spawn_dummies(around: Vector3, count: int = 6) -> void:
	if world == null:
		return
	var samples: Array = world.roads.samples
	if samples.size() < 10:
		return
	var best := 0
	var bd := 1.0e30
	for i in samples.size():
		var p: Vector3 = samples[i]
		var d := Vector2(p.x - around.x, p.z - around.z).length_squared()
		if d < bd:
			bd = d
			best = i
	for k in count:
		var idx := best + 8 + k * 4
		if idx >= samples.size():
			break
		var p: Vector3 = samples[idx]
		var q: Vector3 = samples[mini(idx + 1, samples.size() - 1)]
		var dir := q - p
		dir.y = 0.0
		if dir.length() < 0.1:
			continue
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var pos := p + side * randf_range(-3.2, 3.2)
		if world.island != null:
			pos.y = world.island.height(pos.x, pos.z) + 0.05
		var d := TargetDummy.create(pos, atan2(-dir.x, -dir.z) + PI)
		get_parent().add_child(d)
		dummies.append(d)
