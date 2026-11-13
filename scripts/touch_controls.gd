class_name TouchControls
extends CanvasLayer

## On-screen thumb controls for phones, tablets and any browser tab that reports a
## touch screen.  Nothing is imported: every button is drawn with `_draw()`.
##
##   bottom left   move stick      (floating — it appears where your thumb lands)
##   bottom right  FIRE            press and drag to aim while firing
##                 SPRINT / JUMP / CROUCH / RELOAD around it
##                 right half of the screen (not on a button) is a look pad
##   top centre    BAG             opens the weapon wheel, tap a segment to take it
##                 CAM / MAP next to it
##
## Driving swaps the right hand cluster for BOOST / BRAKE / EXIT and turns the
## move stick into throttle + steering, so the same thumb drives the car.
##
## The HUD layer talks to the game by pressing the normal input actions, so the
## keyboard code paths stay the only source of truth.

const LAYER := 12

## Look sensitivity in radians per pixel.  A thumb drag covers far less screen
## than a mouse, so it is a bit quicker than the mouse.
const LOOK_SENS := 0.0055

var main: Node
var walker: PlayerWalker
var car: PlayerCar

var enabled := false
var driving := false

var _root: Control
var _u := 1.0                      ## one "unit" = 1/720 of the short screen side
var _btn: Array = []               ## [{name,pos,r,label,kind}] built by _layout()
var _held := {}                    ## touch index -> button name
var _press := {}                   ## button name -> true while pressed
var _ours := {}                    ## touch indexes this layer owns

var _joy_id := -1
var _joy_base := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _joy_home := Vector2.ZERO

var _look_id := -1
var _fire_look_id := -1
var _tap_t := 0.0                  ## small visible flash for tap buttons
var _flash := {}

# ------------------------------------------------------------------ setup

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "TouchRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.draw.connect(_draw_all)
	_root.visible = false
	get_viewport().size_changed.connect(_layout)

## Called by main once the world exists.
func attach(p_main: Node, p_walker: PlayerWalker, p_car: PlayerCar) -> void:
	main = p_main
	walker = p_walker
	car = p_car
	var touch := DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if "--touch" in OS.get_cmdline_args() or "--touch" in OS.get_cmdline_user_args():
		touch = true
	set_enabled(touch)

func set_enabled(on: bool) -> void:
	enabled = on
	_root.visible = on
	if main != null and main.get("hud") != null:
		(main.get("hud") as GameHUD).set_compact(on)
	if main != null and main.get("radial") != null:
		(main.get("radial") as RadialMenu).touch_mode = on
	if main != null and main.get("combat_hud") != null:
		(main.get("combat_hud") as CombatHUD).set_compact(on)
	_bind_fire(on)
	if not on:
		_release_all()
	_layout()

## Every touch also arrives as an emulated mouse click (that is what keeps the big
## map usable on a phone), and the left button is bound to "punch" — so a tap on
## the joystick would fire the gun.  While the thumb controls are on, fire comes
## from the button only.
func _bind_fire(touch_on: bool) -> void:
	if not InputMap.has_action("punch"):
		return
	InputMap.action_erase_events("punch")
	if touch_on:
		return
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("punch", mb)

func _layout() -> void:
	if _root == null:
		return
	# _root fills the viewport through its anchors; its size is the same space the
	# touch positions arrive in, so the buttons line up on any screen and any DPR
	var vs: Vector2 = _root.size
	if vs.x < 8.0 or vs.y < 8.0:
		vs = get_viewport().get_visible_rect().size
	var w := vs.x
	var h := vs.y
	_u = clampf(minf(w, h) / 720.0, 0.55, 2.0)
	var u := _u
	driving = main != null and not bool(main.get("on_foot"))
	_joy_home = Vector2(150.0 * u, h - 150.0 * u)
	_btn.clear()
	if driving:
		_add("boost", Vector2(w - 118.0 * u, h - 128.0 * u), 78.0 * u, "BOOST", "hold")
		_add("brake", Vector2(w - 258.0 * u, h - 108.0 * u), 52.0 * u, "BRAKE", "hold")
		_add("exit", Vector2(w - 330.0 * u, h - 232.0 * u), 44.0 * u, "EXIT", "tap")
		_add("cam", Vector2(w * 0.5 - 110.0 * u, 46.0 * u), 30.0 * u, "CAM", "tap")
	else:
		_add("fire", Vector2(w - 120.0 * u, h - 128.0 * u), 84.0 * u, "", "fire")
		_add("sprint", Vector2(w - 262.0 * u, h - 104.0 * u), 52.0 * u, "", "hold")
		_add("jump", Vector2(w - 104.0 * u, h - 286.0 * u), 48.0 * u, "", "hold")
		_add("crouch", Vector2(w - 252.0 * u, h - 226.0 * u), 40.0 * u, "", "toggle")
		_add("reload", Vector2(w - 372.0 * u, h - 118.0 * u), 40.0 * u, "RELOAD", "tap")
		_add("car", Vector2(w - 372.0 * u, h - 232.0 * u), 44.0 * u, "", "tap")
		_add("bag", Vector2(w * 0.5, 50.0 * u), 36.0 * u, "", "tap")
		_add("cam", Vector2(w * 0.5 - 108.0 * u, 46.0 * u), 28.0 * u, "CAM", "tap")
		_add("map", Vector2(w * 0.5 + 108.0 * u, 46.0 * u), 28.0 * u, "MAP", "tap")

func _add(name: String, pos: Vector2, r: float, label: String, kind: String) -> void:
	_btn.append({"name": name, "pos": pos, "r": r, "label": label, "kind": kind})

func _button_at(p: Vector2) -> Dictionary:
	for b in _btn:
		if p.distance_to(b["pos"]) <= float(b["r"]) * 1.12:
			return b
	return {}

# ------------------------------------------------------------------ input

func _input(e: InputEvent) -> void:
	if "--debuginput" in OS.get_cmdline_user_args():
		print("EV ", e.get_class(), " ", e.as_text())
	if not enabled:
		return
	# the big map owns the whole screen while it is open
	if main != null and main.has_method("is_map_open") and bool(main.call("is_map_open")):
		_release_all()
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			if _on_down(t.index, t.position):
				get_viewport().set_input_as_handled()
		else:
			if _on_up(t.index):
				get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if _on_drag(d.index, d.position, d.relative):
			get_viewport().set_input_as_handled()

func _on_down(index: int, p: Vector2) -> bool:
	# the pinned weapon wheel eats the next tap
	var radial: RadialMenu = main.get("radial") if main != null else null
	if radial != null and radial.open:
		radial.touch_pick(p)
		return true
	var b := _button_at(p)
	if not b.is_empty():
		var name := String(b["name"])
		_held[index] = name
		_ours[index] = true
		_flash[name] = 0.22
		_press[name] = true
		match name:
			"fire":
				_fire_look_id = index
				Input.action_press("punch")
			"sprint", "jump":
				Input.action_press("boost" if name == "sprint" else "jump")
			"crouch":
				_set_toggle("crouch", not walker.crouching)
			"boost":
				Input.action_press("boost")
				if car != null:
					car.touch_boost = true
			"brake":
				if car != null:
					car.touch_brake = 1.0
			"reload":
				_tap_action("reload")
			"bag":
				if radial != null:
					radial.toggle_pin()
			"cam":
				if main != null:
					main.call("_cycle_camera")
			"map":
				if main != null and main.get("map_ui") != null:
					(main.get("map_ui") as GameMapUI).toggle()
			"car", "exit":
				if main != null:
					main.call("_toggle_vehicle")
		return true
	# floating stick on the left, look pad everywhere else
	var vs: Vector2 = _root.size
	if p.x < vs.x * 0.45 and p.y > vs.y * 0.26:
		_joy_id = index
		_ours[index] = true
		_joy_base = p
		_joy_knob = p
		_joy_vec = Vector2.ZERO
		_apply_joy()
		return true
	_look_id = index
	_ours[index] = true
	return true

func _on_up(index: int) -> bool:
	if not _ours.has(index):
		return false
	_ours.erase(index)
	if _joy_id == index:
		_joy_id = -1
		_joy_base = _joy_home
		_joy_knob = _joy_home
		_joy_vec = Vector2.ZERO
		_apply_joy()
		return true
	if _fire_look_id == index:
		_fire_look_id = -1
	if _look_id == index:
		_look_id = -1
	var name := String(_held.get(index, ""))
	_held.erase(index)
	if name == "":
		return true
	_press[name] = false
	match name:
		"fire":
			Input.action_release("punch")
		"sprint", "jump":
			Input.action_release("boost" if name == "sprint" else "jump")
		"boost":
			Input.action_release("boost")
			if car != null:
				car.touch_boost = false
		"brake":
			if car != null:
				car.touch_brake = 0.0
	return true

func _on_drag(index: int, p: Vector2, rel: Vector2) -> bool:
	if not _ours.has(index):
		return false
	if _joy_id == index:
		var d := p - _joy_base
		var limit := 96.0 * _u
		if d.length() > limit:
			# let the base slide a little so a long drag does not stall the stick
			_joy_base += d.normalized() * (d.length() - limit) * 0.55
			d = p - _joy_base
			if d.length() > limit:
				d = d.normalized() * limit
		_joy_knob = _joy_base + d
		_joy_vec = d / limit
		if _joy_vec.length() < 0.14:
			_joy_vec = Vector2.ZERO
		_apply_joy()
		return true
	if index == _look_id or index == _fire_look_id:
		if walker != null:
			walker.add_look(rel.x, rel.y, LOOK_SENS)
		return true
	return true

## Push the stick into the game: on foot it is the move vector, in a car it is
## throttle / brake / steering.
func _apply_joy() -> void:
	var v := _joy_vec
	if walker != null:
		walker.touch_move = Vector2(v.x, -v.y)
	if car != null:
		car.touch_steer = clampf(v.x, -1.0, 1.0)
		car.touch_throttle = clampf(-v.y, 0.0, 1.0)
		car.touch_brake = clampf(v.y, 0.0, 1.0)

func _set_toggle(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)

## Fire an action for exactly one frame, the way a key tap would.
func _tap_action(action: String) -> void:
	Input.action_press(action)
	_flash[action] = 0.12
	var t := get_tree().create_timer(0.06)
	t.timeout.connect(func() -> void: Input.action_release(action))

func _release_all() -> void:
	_ours.clear()
	_held.clear()
	_joy_id = -1
	_look_id = -1
	_fire_look_id = -1
	_joy_vec = Vector2.ZERO
	_press.clear()
	Input.action_release("punch")
	Input.action_release("boost")
	Input.action_release("jump")
	Input.action_release("crouch")
	if walker != null:
		walker.touch_move = Vector2.ZERO
		walker.touch_sprint = false
	if car != null:
		car.touch_throttle = 0.0
		car.touch_brake = 0.0
		car.touch_steer = 0.0
		car.touch_boost = false

func _process(dt: float) -> void:
	if not enabled:
		return
	_tap_t -= dt
	var was_driving := driving
	if main != null:
		driving = not bool(main.get("on_foot"))
	if driving != was_driving:
		_layout()
	if walker != null:
		walker.touch_sprint = bool(_press.get("sprint", false))
	for k in _flash.keys():
		_flash[k] = float(_flash[k]) - dt
		if float(_flash[k]) <= 0.0:
			_flash.erase(k)
	_root.queue_redraw()

# ------------------------------------------------------------------ drawing

func _draw_all() -> void:
	var font := ThemeDB.fallback_font
	# ---- move stick
	var on_foot := not driving
	var base := _joy_base if _joy_id >= 0 else _joy_home
	var knob := _joy_knob if _joy_id >= 0 else _joy_home
	var jr := 104.0 * _u
	_root.draw_circle(base, jr, Color(0.04, 0.06, 0.10, 0.34))
	_root.draw_arc(base, jr, 0.0, TAU, 48, Color(1, 1, 1, 0.34), 2.0, true)
	_root.draw_arc(base, jr * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.5, true)
	_root.draw_circle(knob, 44.0 * _u, Color(1, 1, 1, 0.30))
	_root.draw_circle(knob, 40.0 * _u, Color(0.80, 0.88, 1.0, 0.55))
	# ---- buttons
	for b in _btn:
		var name := String(b["name"])
		var pos: Vector2 = b["pos"]
		var r: float = float(b["r"])
		var down: bool = bool(_press.get(name, false))
		var flash: float = float(_flash.get(name, 0.0))
		var fill := Color(0.05, 0.07, 0.11, 0.42)
		var ring := Color(1, 1, 1, 0.40)
		var ink := Color(1, 1, 1, 0.90)
		match name:
			"fire":
				fill = Color(0.95, 0.22, 0.18, 0.38)
				ring = Color(1.0, 0.55, 0.45, 0.85)
			"sprint":
				fill = Color(0.25, 0.62, 1.0, 0.32)
				ring = Color(0.55, 0.80, 1.0, 0.75)
			"jump":
				fill = Color(0.30, 0.85, 0.55, 0.30)
				ring = Color(0.55, 1.0, 0.75, 0.70)
			"bag":
				fill = Color(0.95, 0.78, 0.25, 0.34)
				ring = Color(1.0, 0.90, 0.55, 0.85)
			"boost":
				fill = Color(0.95, 0.45, 0.90, 0.32)
				ring = Color(1.0, 0.70, 0.98, 0.80)
			_:
				pass
		if down:
			fill.a = minf(1.0, fill.a + 0.34)
			ring.a = 1.0
		if flash > 0.0:
			fill.a = minf(1.0, fill.a + flash * 1.6)
		_root.draw_circle(pos, r, fill)
		_root.draw_arc(pos, r, 0.0, TAU, 44, ring, maxf(2.0, r * 0.06), true)
		_glyph(name, pos, r, ink, font)
		if String(b["label"]) != "":
			var fs := int(maxf(11.0, r * 0.46))
			var sz := font.get_string_size(String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			_root.draw_string(font, pos + Vector2(-sz.x * 0.5, r + fs * 1.15),
				String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.70))

func _box(col: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	return sb

## Small vector icons — no image files anywhere in this project.
func _glyph(name: String, c: Vector2, r: float, ink: Color, font: Font) -> void:
	match name:
		"fire":
			# crosshair: ring, four ticks and a centre dot — reads as "shoot"
			var ring := r * 0.50
			_root.draw_arc(c, ring, 0.0, TAU, 40, ink, maxf(2.5, r * 0.055), true)
			for i in 4:
				var a := float(i) * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				_root.draw_line(c + d * ring * 1.28, c + d * ring * 0.72, ink,
					maxf(2.5, r * 0.055), true)
			_root.draw_circle(c, r * 0.11, ink)
		"sprint":
			for i in 2:
				var o := Vector2(c.x - r * 0.34 + float(i) * r * 0.42, c.y)
				_root.draw_polyline(PackedVector2Array([
					o + Vector2(-r * 0.16, -r * 0.38), o + Vector2(r * 0.14, 0.0),
					o + Vector2(-r * 0.16, r * 0.38)]), ink, 3.5, true)
		"jump":
			_root.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.52), c + Vector2(r * 0.40, -r * 0.02),
				c + Vector2(r * 0.14, -r * 0.02), c + Vector2(r * 0.14, r * 0.44),
				c + Vector2(-r * 0.14, r * 0.44), c + Vector2(-r * 0.14, -r * 0.02),
				c + Vector2(-r * 0.40, -r * 0.02)]), ink)
		"crouch":
			_root.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, r * 0.46), c + Vector2(r * 0.36, -r * 0.04),
				c + Vector2(r * 0.12, -r * 0.04), c + Vector2(r * 0.12, -r * 0.42),
				c + Vector2(-r * 0.12, -r * 0.42), c + Vector2(-r * 0.12, -r * 0.04),
				c + Vector2(-r * 0.36, -r * 0.04)]), ink)
		"bag":
			# backpack: pack body, front pocket, a flap line, the carry handle on
			# top and a shoulder strap on each side
			var bw := r * 0.46
			var bh := r * 0.52
			var body := Rect2(c + Vector2(-bw, -bh * 0.72), Vector2(bw * 2.0, bh * 1.72))
			_root.draw_style_box(_box(ink, 6.0), body)
			_root.draw_arc(c + Vector2(0, -bh * 0.72), r * 0.17, PI, TAU, 12, ink, maxf(3.0, r * 0.07), true)
			_root.draw_line(c + Vector2(-bw, -bh * 0.28), c + Vector2(bw, -bh * 0.28),
				Color(0.05, 0.06, 0.09, 0.75), maxf(1.6, r * 0.035), true)
			_root.draw_rect(Rect2(c + Vector2(-bw * 0.44, bh * 0.05), Vector2(bw * 0.88, bh * 0.52)),
				Color(0.05, 0.06, 0.09, 0.55))
			_root.draw_line(c + Vector2(-bw * 1.10, -bh * 0.55), c + Vector2(-bw * 1.10, bh * 0.75),
				ink, maxf(2.0, r * 0.05), true)
			_root.draw_line(c + Vector2(bw * 1.10, -bh * 0.55), c + Vector2(bw * 1.10, bh * 0.75),
				ink, maxf(2.0, r * 0.05), true)
		"car", "exit":
			_root.draw_rect(Rect2(c + Vector2(-r * 0.52, -r * 0.10), Vector2(r * 1.04, r * 0.42)), ink)
			_root.draw_rect(Rect2(c + Vector2(-r * 0.30, -r * 0.40), Vector2(r * 0.60, r * 0.34)), ink)
			_root.draw_circle(c + Vector2(-r * 0.30, r * 0.34), r * 0.16, ink)
			_root.draw_circle(c + Vector2(r * 0.30, r * 0.34), r * 0.16, ink)
		_:
			pass
