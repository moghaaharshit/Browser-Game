class_name CombatHUD
extends CanvasLayer

## The gunplay overlay: dynamic crosshair, hit marker + HEADSHOT popup, ammo
## counter, gloo-wall / grenade counters and the sniper scope.  All of it is
## drawn by hand on one Control, so it stays pixel-crisp at any resolution and
## costs nothing when you are driving.

var combat: CombatSystem
var armed := false

var _root: Control
var _hit_t := 0.0
var _hit_head := false
var _hit_kill := false
var _popup_t := 0.0
var _popup := ""
var _scope_amt := 0.0
var prompt := ""      ## "[E] BODY VEST" while you stand next to a pickup
## Phone layout: the ammo sits above the fire button and the item strip moves to
## the top left, so nothing hides behind a thumb.
var compact := false

func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.name = "CombatOverlay"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.draw.connect(_draw_all)

func set_compact(on: bool) -> void:
	compact = on
	if _root != null:
		_root.queue_redraw()

func attach(c: CombatSystem) -> void:
	combat = c
	c.shot_fired.connect(_on_shot)
	c.refresh.connect(_on_refresh)

func _on_refresh() -> void:
	if _root != null:
		_root.queue_redraw()

func _on_shot(hit: bool, head: bool, kill: bool) -> void:
	if hit:
		_hit_t = 0.22
		_hit_head = head
		_hit_kill = kill
		if head:
			_popup = "HEADSHOT!" if not kill else "HEADSHOT KILL!"
			_popup_t = 0.9
		elif kill:
			_popup = "KILL"
			_popup_t = 0.8
	if _root != null:
		_root.queue_redraw()

func _process(dt: float) -> void:
	if _hit_t > 0.0:
		_hit_t = maxf(0.0, _hit_t - dt)
	if _popup_t > 0.0:
		_popup_t = maxf(0.0, _popup_t - dt)
	var want := 1.0 if (combat != null and combat.is_scoped()) else 0.0
	_scope_amt = lerpf(_scope_amt, want, 1.0 - exp(-14.0 * dt))
	if _root != null:
		_root.queue_redraw()

# ---------------------------------------------------------------- drawing

func _draw_all() -> void:
	if combat == null:
		return
	var vs := _root.size
	var c := vs * 0.5
	if _scope_amt > 0.02:
		_draw_scope(vs, c)
	if armed and _scope_amt < 0.75:
		_draw_crosshair(c)
	if _hit_t > 0.0:
		_draw_hitmarker(c)
	if armed:
		_draw_ammo(vs)
		if _scope_amt < 0.5:
			_draw_items(vs)
	if _popup_t > 0.0:
		_draw_popup(vs)
	if armed and prompt != "":
		var f2 := _font()
		var pw := f2.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var pp := Vector2(vs.x * 0.5 - pw * 0.5, vs.y * 0.62)
		_root.draw_rect(Rect2(pp + Vector2(-10.0, -20.0), Vector2(pw + 20.0, 30.0)), Color(0.02, 0.03, 0.05, 0.55))
		_root.draw_string_outline(f2, pp, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.85))
		_root.draw_string(f2, pp, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.88, 0.45, 0.96))

func _font() -> Font:
	return ThemeDB.fallback_font

func _draw_crosshair(c: Vector2) -> void:
	var spread := 6.0
	if combat != null:
		var d := combat.def()
		spread = 5.0 + float(d["spread"]) * 2.2 + combat.bloom * 5.0
		if combat.ads:
			spread *= 0.55
	# four ticks + centre dot
	var col := Color(1, 1, 1, 0.92)
	var shadow := Color(0, 0, 0, 0.55)
	for a in 4:
		var ang := float(a) * PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var p0 := c + dir * spread
		var p1 := c + dir * (spread + 7.0)
		_root.draw_line(p0 + Vector2(1, 1), p1 + Vector2(1, 1), shadow, 3.0)
		_root.draw_line(p0, p1, col, 2.0)
	_root.draw_circle(c, 4.0, shadow)
	_root.draw_circle(c, 2.4, col)
	# spread ring
	_root.draw_arc(c, spread + 3.0, 0.0, TAU, 28, Color(1, 1, 1, 0.22), 1.4)

func _draw_hitmarker(c: Vector2) -> void:
	var a := clampf(_hit_t / 0.22, 0.0, 1.0)
	var col := Color(1.0, 0.35, 0.30, a) if _hit_head else Color(1, 1, 1, a)
	var d := 9.0 + (1.0 - a) * 6.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_root.draw_line(c + Vector2(sx * d, sy * d) * 0.55, c + Vector2(sx * d, sy * d), col, 2.6)

func _draw_popup(vs: Vector2) -> void:
	var a := clampf(_popup_t / 0.5, 0.0, 1.0)
	var col := Color(1.0, 0.85, 0.25, a)
	var f := _font()
	var size := 30
	var w := f.get_string_size(_popup, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(vs.x * 0.5 - w * 0.5, vs.y * 0.5 - 74.0 - (1.0 - a) * 14.0)
	_root.draw_string_outline(f, p, _popup, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, a * 0.8))
	_root.draw_string(f, p, _popup, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_ammo(vs: Vector2) -> void:
	var d := combat.def()
	var f := _font()
	var right := vs.x - 34.0
	var y := vs.y - 40.0
	if compact:
		right = vs.x - 18.0
		y = vs.y * 0.46
	var name := String(d["name"])
	var wn := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	_root.draw_string_outline(f, Vector2(right - wn, y - 30.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 5, Color(0, 0, 0, 0.75))
	_root.draw_string(f, Vector2(right - wn, y - 30.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(1, 1, 1, 0.95))

	var magtxt := str(combat.mag_left())
	var restxt := " / %d" % combat.reserve_left()
	var magw := f.get_string_size(magtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var restw := f.get_string_size(restxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var col := Color(1, 1, 1, 0.96)
	if combat.mag_left() == 0:
		col = Color(1.0, 0.35, 0.3)
	_root.draw_string_outline(f, Vector2(right - magw - restw, y), magtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 6, Color(0, 0, 0, 0.7))
	_root.draw_string(f, Vector2(right - magw - restw, y), magtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, col)
	_root.draw_string_outline(f, Vector2(right - restw, y), restxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.7))
	_root.draw_string(f, Vector2(right - restw, y), restxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.87, 0.9, 0.95))

	if combat.reloading:
		var total := maxf(0.001, float(d["reload"]))
		var k := clampf(1.0 - combat.reload_left / total, 0.0, 1.0)
		var bar := Rect2(right - 160.0, y + 10.0, 160.0, 5.0)
		_root.draw_rect(bar, Color(0, 0, 0, 0.5))
		_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(1.0, 0.78, 0.25, 0.95))
		var rt := "RELOADING"
		var rw := f.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_root.draw_string(f, Vector2(right - rw, y + 30.0), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.86, 0.4, 0.95))

func _draw_items(vs: Vector2) -> void:
	var f := _font()
	var x := 34.0
	var y := vs.y - 40.0
	if compact:
		x = 16.0
		y = 104.0
	# gloo walls: three slots
	_root.draw_string(f, Vector2(x, y - 34.0), "GLOO", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.92, 1.0, 0.9))
	var placed: int = combat.gloo_walls.size()
	for i in Weapons.GLOO_MAX:
		var r := Rect2(x + float(i) * 22.0, y - 26.0, 17.0, 24.0)
		var on := i < placed
		_root.draw_rect(r, Color(0.45, 0.80, 1.0, 0.85) if on else Color(0.35, 0.45, 0.55, 0.35))
		_root.draw_rect(r, Color(0.85, 0.95, 1.0, 0.9), false, 1.5)
	var stock := "x%d" % combat.gloo_stock
	if combat.gloo_refill_left > 0.0:
		stock = "%ds" % int(ceilf(combat.gloo_refill_left))
	_root.draw_string(f, Vector2(x + 3.0 * 22.0 + 4.0, y - 6.0), stock, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(0.75, 0.92, 1.0, 0.95) if combat.gloo_refill_left <= 0.0 else Color(0.55, 0.80, 0.55, 0.95))
	# grenades
	var gx := x + 3.0 * 22.0 + 42.0
	_root.draw_string(f, Vector2(gx, y - 34.0), "GRENADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.86, 0.55, 0.9))
	for i in mini(combat.grenades, 4):
		_root.draw_circle(Vector2(gx + 8.0 + float(i) * 18.0, y - 14.0), 6.0, Color(0.55, 0.62, 0.45, 0.95))
	# medkits + what the left mouse button is holding
	var mx2 := gx + 4.0 * 18.0 + 14.0
	_root.draw_string(f, Vector2(mx2, y - 34.0), "MEDKIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1.0, 0.55, 0.58, 0.9))
	_root.draw_rect(Rect2(mx2, y - 26.0, 26.0, 24.0), Color(0.85, 0.28, 0.30, 0.85 if combat.medkits > 0 else 0.22))
	_root.draw_rect(Rect2(mx2, y - 26.0, 26.0, 24.0), Color(1, 1, 1, 0.55), false, 1.4)
	_root.draw_rect(Rect2(mx2 + 10.5, y - 21.0, 5.0, 14.0), Color(1, 1, 1, 0.9))
	_root.draw_rect(Rect2(mx2 + 6.0, y - 16.5, 14.0, 5.0), Color(1, 1, 1, 0.9))
	_root.draw_string(f, Vector2(mx2 + 32.0, y - 6.0), "x%d" % combat.medkits, HORIZONTAL_ALIGNMENT_LEFT, -1,
		15, Color(1.0, 0.72, 0.74, 0.95))
	var hand := "IN HAND  " + combat.item_label()
	_root.draw_string(f, Vector2(x, y + 46.0), hand, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1.0, 0.88, 0.45, 0.85) if combat.active_item != 0 else Color(1, 1, 1, 0.40))
	# weapon slots
	var wy := y + 26.0
	for i in Weapons.count():
		var nm := String(Weapons.get_def(i)["name"])
		var sel := i == combat.gun_index
		var p := Vector2(x + float(i) * 62.0, wy)
		_root.draw_string(f, p, str(i + 1) + " " + nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1.0, 0.92, 0.5, 0.98) if sel else Color(1, 1, 1, 0.42))

## Black out everything outside the lens.  A Control cannot un-draw a filled
## rect, so the mask is a fan of quads between the lens circle and a circle big
## enough to cover the screen.
func _mask_outside(c: Vector2, r: float, a: float) -> void:
	var outer := (c.length() + r) * 1.6
	var segs := 80
	var col := Color(0.0, 0.0, 0.0, a)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		_root.draw_colored_polygon(PackedVector2Array([c + d0 * r, c + d0 * outer, c + d1 * outer]), col)
		_root.draw_colored_polygon(PackedVector2Array([c + d0 * r, c + d1 * outer, c + d1 * r]), col)

func _draw_scope(vs: Vector2, c: Vector2) -> void:
	var a := _scope_amt
	if a <= 0.01:
		return
	var sniper := combat != null and combat.scope_kind() == "sniper"
	var m := minf(vs.x, vs.y)
	var r := m * (0.455 if sniper else 0.395)
	_mask_outside(c, r, a)
	# soft vignette inside the lens edge, so it reads as curved glass.  Wide
	# overlapping arcs give a smooth falloff without a single visible ring.
	var steps := 10
	var band := r * 0.055
	for i in steps:
		var k := 1.0 - float(i) / float(steps)
		var rr := r - band * 0.5 - band * float(i)
		_root.draw_arc(c, rr, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.032 * a * (0.35 + k)), band)
	# eyepiece: heavy black ring with a machined highlight on the inside
	_root.draw_arc(c, r - 3.0, 0.0, TAU, 96, Color(0.03, 0.03, 0.04, a), 9.0)
	_root.draw_arc(c, r - 8.0, 0.0, TAU, 96, Color(0.20, 0.22, 0.25, 0.85 * a), 1.6)
	_root.draw_arc(c, r - 10.5, 0.0, TAU, 96, Color(0.55, 0.60, 0.66, 0.55 * a), 1.0)
	# a hint of lens coating: cool blue sheen across the top-left of the glass
	_root.draw_arc(c, r * 0.97, PI * 0.95, PI * 1.75, 48, Color(0.35, 0.62, 0.92, 0.22 * a), 5.0)
	_root.draw_arc(c, r * 0.94, PI * 1.05, PI * 1.45, 32, Color(0.70, 0.90, 1.0, 0.16 * a), 2.4)
	if sniper:
		_sniper_reticle(c, r, a)
	else:
		_reddot_reticle(c, r, a)
	# the scope's own black edge, drawn last so nothing spills over it
	_root.draw_arc(c, r + 1.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, a), 3.0)

## AWM / KAR98K style duplex: fat outer posts, hairline inner cross, mil dots.
func _sniper_reticle(c: Vector2, r: float, a: float) -> void:
	var ink := Color(0.02, 0.02, 0.03, 0.97 * a)
	var thin := Color(0.02, 0.02, 0.03, 0.88 * a)
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_root.draw_line(c + dir * (r * 0.42), c + dir * (r * 0.985), ink, 4.2)
		_root.draw_line(c + dir * 9.0, c + dir * (r * 0.44), thin, 1.5)
	# mil dots down / across, with the tiny gap that a real reticle has
	for i in range(1, 7):
		var off := r * 0.115 * float(i)
		if off > r * 0.86:
			break
		for dir in [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]:
			_root.draw_circle(c + dir * off, maxf(1.2, r * 0.011), thin)
	# rangefinder ladder on the lower post
	for i in range(1, 5):
		var off := r * 0.16 * float(i)
		var w := r * (0.055 - 0.008 * float(i))
		_root.draw_line(c + Vector2(-w, off), c + Vector2(w, off), thin, 1.2)
	_root.draw_circle(c, maxf(1.8, r * 0.014), Color(0.95, 0.16, 0.12, a))

## Red dot / holo style ring: thin cross, glowing dot, glass tint.
func _reddot_reticle(c: Vector2, r: float, a: float) -> void:
	_root.draw_circle(c, r * 0.985, Color(0.35, 0.55, 0.75, 0.05 * a))
	var ink := Color(0.04, 0.05, 0.06, 0.9 * a)
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_root.draw_line(c + dir * (r * 0.11), c + dir * (r * 0.62), ink, 2.0)
		_root.draw_line(c + dir * (r * 0.66), c + dir * (r * 0.97), Color(0.04, 0.05, 0.06, 0.5 * a), 1.2)
	# the illuminated dot: soft halo, then a hard bright core
	_root.draw_circle(c, r * 0.045, Color(1.0, 0.15, 0.10, 0.10 * a))
	_root.draw_circle(c, r * 0.028, Color(1.0, 0.18, 0.12, 0.22 * a))
	_root.draw_circle(c, r * 0.014, Color(1.0, 0.32, 0.22, 0.95 * a))
	_root.draw_circle(c, r * 0.006, Color(1.0, 0.85, 0.80, 0.95 * a))
	# small tick marks around the ring, like a holo sight housing
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var d := Vector2(cos(ang), sin(ang))
		_root.draw_line(c + d * (r * 0.93), c + d * (r * 0.985), Color(0.05, 0.06, 0.07, 0.65 * a), 1.4)
