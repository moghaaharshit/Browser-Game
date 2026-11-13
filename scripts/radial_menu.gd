class_name RadialMenu
extends CanvasLayer

## GTA-5 style weapon wheel in the middle of the screen.  Hold TAB and the wheel
## opens with the mouse cursor out; the segment under the cursor lights up and
## the name of the item sits in the middle.  Let go of TAB (or click) and that
## item is in your hands.
##
## Slots: the ten guns around the ring, then grenade, gloo wall and medkit.

signal picked(kind: int, index: int)   ## kind 0 = gun, 1 = grenade, 2 = gloo, 3 = medkit

var combat: CombatSystem
var open := false
## On a phone there is no TAB to hold, so the bag button *pins* the wheel open
## and the next tap picks a slot.
var pinned := false
var touch_mode := false

var _root: Control
var _hover := -1
var _t := 0.0

const ITEMS := [
	{"kind": 1, "name": "GRENADE", "short": "GRN", "col": Color(0.55, 0.66, 0.42)},
	{"kind": 2, "name": "GLOO WALL", "short": "GLO", "col": Color(0.35, 0.68, 1.0)},
	{"kind": 3, "name": "MEDKIT", "short": "MED", "col": Color(0.95, 0.35, 0.38)},
]

func _ready() -> void:
	layer = 14
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "WheelRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.draw.connect(_draw_all)
	_root.visible = false

func attach(c: CombatSystem) -> void:
	combat = c

func slot_count() -> int:
	return Weapons.count() + ITEMS.size()

func slot_kind(i: int) -> int:
	if i >= Weapons.count():
		return int(ITEMS[i - Weapons.count()]["kind"])
	return 0

func slot_index(i: int) -> int:
	if i >= Weapons.count():
		return i - Weapons.count()
	return i

func slot_name(i: int) -> String:
	if i >= Weapons.count():
		return String(ITEMS[i - Weapons.count()]["name"])
	return String(Weapons.get_def(i)["name"])

func _current_slot() -> int:
	if combat == null:
		return 0
	match combat.active_item:
		1:
			return Weapons.count() + 0
		2:
			return Weapons.count() + 1
		3:
			return Weapons.count() + 2
	return combat.gun_index

# ---------------------------------------------------------------- input

func _process(dt: float) -> void:
	_t += dt
	if pinned:
		if not open:
			pinned = false
	else:
		var held := InputMap.has_action("wheel") and Input.is_action_pressed("wheel")
		if held and not open:
			_open()
		elif not held and open:
			_apply()
			_close()
	if open and not pinned:
		_hover = _slot_at(get_viewport().get_mouse_position())
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_apply()
			_close()
	if _root != null:
		_root.queue_redraw()

func _open() -> void:
	open = true
	_hover = _current_slot()
	_root.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close() -> void:
	open = false
	pinned = false
	_root.visible = false
	# on the web the pointer can only be re-locked by a click (see Main._input)
	if not _over_ui() and not touch_mode and not OS.has_feature("web"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Bag button on the touch HUD: tap once to open, tap a segment to take it.
func toggle_pin() -> void:
	if open:
		_close()
		return
	pinned = true
	_open()

## A tap while the wheel is pinned: pick whatever is under the finger.
func touch_pick(p: Vector2) -> void:
	if not open:
		return
	var slot := _slot_at(p)
	if slot < 0:
		_close()
		return
	_hover = slot
	_apply()
	_close()

## Finger dragged over the wheel: just highlight, do not fire.
func touch_hover(p: Vector2) -> void:
	if open:
		_hover = _slot_at(p)

## The big map owns the cursor too — do not steal it back from there.
func _over_ui() -> bool:
	var p := get_parent()
	while p != null:
		if p.has_method("is_map_open") and bool(p.call("is_map_open")):
			return true
		p = p.get_parent()
	return false

func _apply() -> void:
	if combat == null or _hover < 0:
		return
	var kind := slot_kind(_hover)
	var idx := slot_index(_hover)
	if kind == 0:
		combat.equip_slot(idx)
		combat.equip_item(0)
	else:
		combat.equip_item(kind)
	picked.emit(kind, idx)

func _center() -> Vector2:
	return _root.size * 0.5

func _radii() -> Vector2:
	var m := minf(_root.size.x, _root.size.y)
	return Vector2(m * 0.135, m * 0.315)

func _slot_at(p: Vector2) -> int:
	var c := _center()
	var d := p - c
	var r := _radii()
	if d.length() < r.x * 0.55:
		return -1
	# screen y grows downwards; angle 0 = straight up
	var ang := atan2(d.x, -d.y)
	if ang < 0.0:
		ang += TAU
	var n := slot_count()
	var seg := TAU / float(n)
	# slot 0 sits at the top, then clockwise
	return int(round(ang / seg)) % n

# ---------------------------------------------------------------- drawing

func _draw_all() -> void:
	if not open or combat == null:
		return
	var c := _center()
	var r := _radii()
	var n := slot_count()
	var seg := TAU / float(n)
	var vs := _root.size
	# dim the world behind the wheel
	_root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05, 0.38))
	# base disc
	_root.draw_circle(c, r.y + 10.0, Color(0.04, 0.05, 0.07, 0.90))
	_root.draw_arc(c, r.y + 10.0, 0.0, TAU, 96, Color(0.55, 0.62, 0.70, 0.55), 2.0)
	_root.draw_circle(c, r.x - 12.0, Color(0.05, 0.06, 0.08, 0.94))
	for i in n:
		_draw_slot(c, r, i, seg, i == _hover, i == _current_slot())
	# inner hub with the hovered name + count
	_root.draw_arc(c, r.x - 12.0, 0.0, TAU, 64, Color(0.55, 0.62, 0.70, 0.40), 1.5)
	var f := ThemeDB.fallback_font
	var title := "WEAPON WHEEL"
	var big := "—"
	if _hover >= 0:
		title = slot_name(_hover)
		big = _slot_count_text(_hover)
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_root.draw_string_outline(f, c + Vector2(-tw * 0.5, -6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6,
		Color(0, 0, 0, 0.85))
	_root.draw_string(f, c + Vector2(-tw * 0.5, -6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(1, 1, 1, 0.96))
	if _hover >= 0:
		var bw := f.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_root.draw_string(f, c + Vector2(-bw * 0.5, 18.0), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.80, 0.86, 0.92, 0.92))
	var hint := "hold TAB  ·  move the mouse  ·  release to equip"
	if pinned or touch_mode:
		hint = "tap a weapon  ·  tap outside to close"
	var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_root.draw_string(f, Vector2(c.x - hw * 0.5, vs.y - 42.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.85, 0.90, 0.96, 0.65))

func _slot_count_text(i: int) -> String:
	if i >= Weapons.count():
		match int(ITEMS[i - Weapons.count()]["kind"]):
			1:
				return "x%d carried" % combat.grenades
			2:
				return "x%d carried" % combat.gloo_stock
			_:
				return "x%d carried" % combat.medkits
	var d := Weapons.get_def(i)
	return "%d / %d  ·  %s" % [int(combat.mag[i]), int(combat.reserve[i]), String(d["kind_name"]) if d.has("kind_name") else String(d["name"])]

func _draw_slot(c: Vector2, r: Vector2, i: int, seg: float, hovered: bool, current: bool) -> void:
	var a0 := -PI * 0.5 + seg * float(i) + seg * 0.06
	var a1 := -PI * 0.5 + seg * float(i + 1) - seg * 0.06
	var col := Color(1, 1, 1, 0.92)
	if i >= Weapons.count():
		col = ITEMS[i - Weapons.count()]["col"]
	var fill := Color(0.10, 0.12, 0.16, 0.55)
	if current:
		fill = Color(0.30, 0.42, 0.30, 0.55)
	if hovered:
		fill = Color(col.r * 0.55 + 0.15, col.g * 0.55 + 0.15, col.b * 0.55 + 0.15, 0.85)
	var steps := 6
	for s in steps:
		var t0 := lerpf(a0, a1, float(s) / float(steps))
		var t1 := lerpf(a0, a1, float(s + 1) / float(steps))
		var p := PackedVector2Array([
			c + Vector2(cos(t0), sin(t0)) * r.x,
			c + Vector2(cos(t0), sin(t0)) * r.y,
			c + Vector2(cos(t1), sin(t1)) * r.y,
			c + Vector2(cos(t1), sin(t1)) * r.x,
		])
		_root.draw_colored_polygon(p, fill)
	# outline
	var prev := c + Vector2(cos(a0), sin(a0)) * r.y
	for s in range(1, 13):
		var t := lerpf(a0, a1, float(s) / 12.0)
		var nxt := c + Vector2(cos(t), sin(t)) * r.y
		_root.draw_line(prev, nxt, Color(0, 0, 0, 0.55), 1.4)
		prev = nxt
	# divider walls
	_root.draw_line(c + Vector2(cos(a0), sin(a0)) * r.x, c + Vector2(cos(a0), sin(a0)) * r.y,
		Color(0.6, 0.68, 0.76, 0.35), 1.2)
	# label along the mid radius
	var mid := (a0 + a1) * 0.5
	var dir := Vector2(cos(mid), sin(mid))
	var f := ThemeDB.fallback_font
	var nm := slot_name(i)
	var fs := 15 if hovered else 13
	var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p2 := c + dir * (r.x + r.y) * 0.5 - Vector2(w * 0.5, -5.0)
	_root.draw_string_outline(f, p2, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4,
		Color(0, 0, 0, 0.85))
	_root.draw_string(f, p2, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(1, 1, 1, 1.0) if hovered else Color(col.r, col.g, col.b, 0.80))
	# small index badge for the guns, ammo count for the items
	var badge := ""
	if i < Weapons.count():
		badge = str(i + 1)
	else:
		match int(ITEMS[i - Weapons.count()]["kind"]):
			1:
				badge = "x%d" % combat.grenades
			2:
				badge = "x%d" % combat.gloo_stock
			_:
				badge = "x%d" % combat.medkits
	if badge != "":
		var bw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var bp := c + dir * (r.x + 20.0) - Vector2(bw * 0.5, -4.0)
		_root.draw_string_outline(f, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3,
			Color(0, 0, 0, 0.8))
		_root.draw_string(f, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.92, 0.55, 0.95))
