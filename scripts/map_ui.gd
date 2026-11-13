class_name GameMapUI
extends CanvasLayer

## Two live 3D map views of the real world:
##   * a square minimap in the top-right corner, zoomed in on the player,
##     rotating with the car (heading always up),
##   * the full screen map on M, same 3D view but you can zoom it in and out
##     with the mouse wheel and click anywhere to set a destination.
## A dotted line runs from the player arrow to that destination and disappears
## once you get there.

const MINI_SIZE := 232.0
const MINI_MARGIN := 20.0
const MINI_VIEW_M := 260.0        ## metres across the minimap (zoomed in on the car)
const MINI_TEX := 256

const BIG_TEX := 1024
const BIG_SIDE_FRAC := 0.86
const BIG_ZOOM_MIN := 300.0       ## metres across the big map, most zoomed in
const BIG_ZOOM_MAX := 8600.0       ## ...and fully zoomed out (whole island)
const BIG_ZOOM_START := 6200.0

const ARRIVE_M := 30.0
const ROT_RATE := 9.0             ## how fast the maps swing round to the car heading

var player: Node3D = null

var _mini_panel: Control
var _mini_overlay: Control
var _mini_sub: SubViewport
var _mini_cam: Camera3D

var _dim: ColorRect
var _big_tex: TextureRect
var _big: Control
var _big_sub: SubViewport
var _big_cam: Camera3D
var _big_zoom := BIG_ZOOM_START

var _open := false
var _mini_tick := 0
var _rot := 0.0                   ## smoothed map rotation (= car heading)
var _yaw := 0.0
var _ppos := Vector3.ZERO
var _has_wp := false
var _wp := Vector3.ZERO

func _ready() -> void:
	layer = 20

	# ---------------------------------------------------------- minimap viewport
	_mini_sub = SubViewport.new()
	_mini_sub.name = "MiniView"
	_mini_sub.size = Vector2i(MINI_TEX, MINI_TEX)
	_mini_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mini_sub.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_mini_sub)
	_mini_cam = _make_cam(MINI_VIEW_M)
	_mini_sub.add_child(_mini_cam)
	_mini_cam.current = true

	# ---------------------------------------------------------- big map viewport
	_big_sub = SubViewport.new()
	_big_sub.name = "BigView"
	_big_sub.size = Vector2i(BIG_TEX, BIG_TEX)
	_big_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_big_sub.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_big_sub)
	_big_cam = _make_cam(BIG_ZOOM_START)
	_big_sub.add_child(_big_cam)
	_big_cam.current = true

	# both views render the real game world
	await get_tree().process_frame
	var world_3d: World3D = get_viewport().world_3d
	_mini_sub.world_3d = world_3d
	_big_sub.world_3d = world_3d

	# ---------------------------------------------------------- minimap frame
	_mini_panel = Control.new()
	_mini_panel.name = "MiniMap"
	_mini_panel.custom_minimum_size = Vector2(MINI_SIZE, MINI_SIZE)
	_mini_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mini_panel)

	var tex := TextureRect.new()
	tex.texture = _mini_sub.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size = Vector2(MINI_SIZE, MINI_SIZE)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_panel.add_child(tex)

	_mini_overlay = Control.new()
	_mini_overlay.size = Vector2(MINI_SIZE, MINI_SIZE)
	_mini_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_overlay.draw.connect(_draw_mini)
	_mini_panel.add_child(_mini_overlay)

	# ---------------------------------------------------------- big map layers
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.04, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)

	_big_tex = TextureRect.new()
	_big_tex.texture = _big_sub.get_texture()
	_big_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_big_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_tex.visible = false
	add_child(_big_tex)

	_big = Control.new()
	_big.name = "BigMap"
	_big.anchor_right = 1.0
	_big.anchor_bottom = 1.0
	_big.mouse_filter = Control.MOUSE_FILTER_STOP
	_big.visible = false
	_big.draw.connect(_draw_big)
	_big.gui_input.connect(_on_big_input)
	add_child(_big)

	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()

func _make_cam(size_m: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size_m
	cam.near = 1.0
	cam.far = 12000.0
	cam.physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF
	return cam

func set_player(p: Node3D) -> void:
	player = p
	if p != null:
		_yaw = p.global_rotation.y
		_rot = _yaw

func is_open() -> bool:
	return _open

func toggle() -> void:
	set_open(not _open)

func set_open(v: bool) -> void:
	_open = v
	if _dim == null:
		return
	_layout()
	_dim.visible = _open
	_big_tex.visible = _open
	_big.visible = _open
	if _mini_panel != null:
		_mini_panel.visible = not _open
	if _big_sub != null:
		_big_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _open \
			else SubViewport.UPDATE_DISABLED
	if _open:
		_big.queue_redraw()

func close() -> void:
	set_open(false)

func has_waypoint() -> bool:
	return _has_wp

func clear_waypoint() -> void:
	_has_wp = false

func zoom_by(steps: float) -> void:
	_big_zoom = clampf(_big_zoom * pow(1.22, -steps), BIG_ZOOM_MIN, BIG_ZOOM_MAX)
	if _big != null:
		_big.queue_redraw()

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if player == null:
		return
	var tr: Transform3D = player.get_global_transform_interpolated()
	_ppos = tr.origin
	_yaw = tr.basis.get_euler().y
	_rot = lerp_angle(_rot, _yaw, 1.0 - exp(-ROT_RATE * delta))

	# minimap: zoomed in on the car, rotating with it
	if _mini_tick % 2 == 0 and _mini_sub != null:
		_mini_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	_mini_tick += 1
	if _mini_cam != null:
		_push_cam(_mini_cam, _ppos, 420.0)

	# big map: only rendered while it is open
	if _open and _big_cam != null:
		_big_zoom = clampf(_big_zoom, BIG_ZOOM_MIN, BIG_ZOOM_MAX)
		# fly lower when zoomed in: less distance fog, so the city keeps its colours
		var alt := clampf(_big_zoom * 0.58, 1100.0, 4400.0)
		_push_cam(_big_cam, _ppos, alt)
		_big_cam.far = alt + 17000.0
		_big_cam.size = _big_zoom
		if _big_sub != null:
			_big_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# arrived?
	if _has_wp and Vector2(_ppos.x - _wp.x, _ppos.z - _wp.z).length() < ARRIVE_M:
		_has_wp = false

	if _mini_overlay != null:
		_mini_overlay.queue_redraw()
	if _open and _big != null:
		_big.queue_redraw()

## Place an orthographic camera above `centre`, looking down, rotated so that the
## car's heading points to the top of the screen.
func _push_cam(cam: Camera3D, centre: Vector3, height: float) -> void:
	var basis := Basis(Vector3.UP, _rot) * Basis(Vector3.RIGHT, -PI * 0.5)
	var pos := Vector3(centre.x, height, centre.z)
	cam.global_transform = Transform3D(basis, pos)

func _layout() -> void:
	var rect := get_viewport().get_visible_rect().size
	if _mini_panel != null:
		_mini_panel.size = Vector2(MINI_SIZE, MINI_SIZE)
		_mini_panel.position = Vector2(rect.x - MINI_SIZE - MINI_MARGIN, MINI_MARGIN)
	if _big_tex != null:
		var r := _map_rect()
		_big_tex.position = r.position
		_big_tex.size = r.size

func _map_rect() -> Rect2:
	var s := _big.size if _big != null else get_viewport().get_visible_rect().size
	var side := minf(s.x, s.y) * BIG_SIDE_FRAC
	return Rect2(Vector2((s.x - side) * 0.5, (s.y - side) * 0.5), Vector2(side, side))

# ---------------------------------------------------------------- transforms

func _w2m(w: Vector3, origin: Rect2, zoom_m: float) -> Vector2:
	var k := origin.size.x / zoom_m
	var d := Vector2(w.x - _ppos.x, w.z - _ppos.z) * k
	d = d.rotated(_rot)
	return origin.get_center() + d

func _m2w(q: Vector2, origin: Rect2, zoom_m: float) -> Vector3:
	var k := origin.size.x / zoom_m
	var d := (q - origin.get_center()) / k
	d = d.rotated(-_rot)
	return Vector3(_ppos.x + d.x, 0.0, _ppos.z + d.y)

func _arrow_dir() -> Vector2:
	# where the car's nose points on screen (the map rotation trails the car a bit)
	return Vector2(0, -1).rotated(_rot - _yaw)

func _north_dir() -> Vector2:
	return Vector2(0, -1).rotated(_rot)

# ---------------------------------------------------------------- minimap drawing

func _draw_mini() -> void:
	var c := _mini_overlay
	var s := MINI_SIZE
	var origin := Rect2(Vector2.ZERO, Vector2(s, s))
	var centre := origin.get_center()
	c.draw_rect(origin, Color(1, 1, 1, 0.25), false, 2.0)
	c.draw_rect(Rect2(Vector2(1, 1), Vector2(s - 2, s - 2)), Color(0, 0, 0, 0.35), false, 1.0)

	# compass (north moves as the map turns)
	var nd := _north_dir()
	var npos := centre + nd * (s * 0.5 - 14.0)
	c.draw_circle(npos, 8.0, Color(0.05, 0.07, 0.10, 0.75))
	c.draw_string(ThemeDB.get_fallback_font(), npos + Vector2(-4.0, 4.5), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.96, 1.0, 0.9))

	# destination + dotted line (clamped to the frame when it is far away)
	if _has_wp:
		var p := _w2m(_wp, origin, MINI_VIEW_M)
		var d := p - centre
		var half := s * 0.5 - 12.0
		if d.length() > half:
			d = d.normalized() * half
		var tip := centre + d
		_dotted(c, centre, tip, Color("ffd23b"), 6.0, 5.0, 2.0)
		_marker(c, tip, Color("ffd23b"), 6.5)

	# the player arrow, in the middle of the map
	c.draw_circle(centre, 13.0, Color(0.02, 0.04, 0.06, 0.45))
	_arrow(c, centre, _arrow_dir(), 11.0, Color("2ff2ff"), 2.0)

# ---------------------------------------------------------------- big map

func _draw_big() -> void:
	var c := _big
	var r := _map_rect()
	c.draw_rect(r, Color(0, 0, 0, 0.25), false, 3.0)
	c.draw_rect(r.grow(2.0), Color(1, 1, 1, 0.25), false, 2.0)

	var font := ThemeDB.get_fallback_font()
	var world: Node = get_parent().get("world")

	# ---- town names, projected through the live map transform
	if world != null:
		var cities: Array = world.map_cities()
		var here: int = world.city_index_at(_ppos)
		for ci in cities.size():
			var city: Dictionary = cities[ci]
			var wp: Vector3 = city["pos"]
			var sp := _w2m(wp, r, _big_zoom)
			if not r.grow(60.0).has_point(sp):
				continue
			var col: Color = _town_color(int(city["kind"]))
			var k := r.size.x / _big_zoom
			var tr := clampf(float(city["r"]) * k, 6.0, 140.0)
			c.draw_circle(sp, tr, Color(col.r, col.g, col.b, 0.20))
			c.draw_arc(sp, tr, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.85), 1.5, true)
			c.draw_circle(sp, 4.5, Color(0, 0, 0, 0.5))
			c.draw_circle(sp, 3.2, col)
			var nm := String(city["name"])
			var fs := clampi(int(round(26.0 / (1.0 + _big_zoom / 1400.0))), 7, 15)
			var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := sp + Vector2(-tw * 0.5, -tr - 6.0)
			var strong := ci == here
			c.draw_string(font, tp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0, 0, 0, 0.85))
			c.draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1, 1, 1) if strong else Color(0.90, 0.95, 1.0, 0.92))

	# ---- destination + dotted path
	var centre := r.get_center()
	if _has_wp:
		var wsp := _w2m(_wp, r, _big_zoom)
		# keep the marker on the map when the destination is outside the view
		var d := wsp - centre
		var lim := r.size.x * 0.5 - 16.0
		if d.length() > lim:
			d = d.normalized() * lim
		var tip := centre + d
		_dotted(c, centre, tip, Color("ffd23b"), 8.0, 6.0, 2.0)
		_marker(c, tip, Color("ffd23b"), 9.0)
		if wsp.distance_to(tip) < 2.0:
			var dist := Vector2(_ppos.x - _wp.x, _ppos.z - _wp.z).length()
			c.draw_string(font, tip + Vector2(13.0, 5.0), "%d m" % int(dist),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.86, 0.35))

	# ---- player arrow (in the middle of the map)
	c.draw_circle(centre, 16.0, Color(0.02, 0.04, 0.06, 0.45))
	_arrow(c, centre, _arrow_dir(), 13.0, Color("2ff2ff"), 2.5)

	# ---- compass
	var nd := _north_dir()
	var npos := centre + nd * (r.size.x * 0.5 - 22.0)
	c.draw_circle(npos, 12.0, Color(0.05, 0.07, 0.10, 0.8))
	c.draw_circle(npos, 12.0, Color(1, 1, 1, 0.25), false, 1.5)
	c.draw_string(font, npos + Vector2(-5.0, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.95, 0.98, 1.0))

	# ---- zoom readout + hint
	var zlbl := "ZOOM  %s   ·   MOUSE WHEEL TO ZOOM" % _zoom_label()
	var zw := font.get_string_size(zlbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	c.draw_string(font, Vector2(r.position.x, r.position.y - 14.0), zlbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0, 0.9))
	var hint := "CLICK ANY SPOT TO SET A DESTINATION      ·      M / ESC TO CLOSE"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	c.draw_string(font, Vector2(r.position.x + (r.size.x - hw) * 0.5, r.end.y + 26.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.80, 0.88, 0.95, 0.85))

func _zoom_label() -> String:
	if _big_zoom >= 1000.0:
		return "%.1f km" % (_big_zoom / 1000.0)
	return "%d m" % int(_big_zoom)

func _on_big_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.0)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-1.0)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var r := _map_rect()
			if r.has_point(mb.position):
				_wp = _m2w(mb.position, r, _big_zoom)
				_has_wp = true
				_big.queue_redraw()
				_mini_overlay.queue_redraw()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		# M and Esc are handled by main.gd so they are not toggled twice
		if k == KEY_EQUAL or k == KEY_KP_ADD:
			zoom_by(1.0)
			get_viewport().set_input_as_handled()
		elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
			zoom_by(-1.0)
			get_viewport().set_input_as_handled()

func _town_color(kind: int) -> Color:
	match kind:
		0:
			return Color("e0b23a")   # industrial
		2:
			return Color("ff3ba7")   # neon
		3:
			return Color("6fcf7f")   # rural
		4:
			return Color("4fd0c0")   # nature
	return Color("7fb2ff")           # town

# ---------------------------------------------------------------- primitives

func _dotted(c: Control, a: Vector2, b: Vector2, col: Color, dash: float, gap: float,
		w: float) -> void:
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var dir := (b - a) / total
	var t := 0.0
	while t < total:
		var t2 := minf(t + dash, total)
		c.draw_line(a + dir * t, a + dir * t2, Color(0, 0, 0, 0.55), w + 2.5, true)
		c.draw_line(a + dir * t, a + dir * t2, col, w, true)
		t = t2 + gap

func _arrow(c: Control, p: Vector2, fwd: Vector2, size: float, col: Color, out: float) -> void:
	var d := fwd.normalized()
	var side := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([
		p + d * size,
		p - d * size * 0.66 + side * size * 0.70,
		p - d * size * 0.22,
		p - d * size * 0.66 - side * size * 0.70,
	])
	c.draw_colored_polygon(pts, col)
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(0, 0, 0, 0.6), out, true)

func _marker(c: Control, p: Vector2, col: Color, size: float) -> void:
	var pts := PackedVector2Array([
		p + Vector2(0, -size), p + Vector2(size, 0), p + Vector2(0, size), p + Vector2(-size, 0),
	])
	c.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[2], pts[3]]), col)
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(0, 0, 0, 0.7), 2.0, true)
