class_name GameHUD
extends CanvasLayer

## The whole HUD is one analogue speedometer: a dial with a needle.
## No panels, no text boxes, nothing else on screen.

const MAX_KMH := 240.0        ## full scale of the dial
const A0 := PI * 0.75         ## dial starts at 135 deg (bottom left)
const SWEEP := PI * 1.5       ## ...and sweeps 270 deg clockwise
const SIZE := 300.0
const MARGIN := 22.0

var _gauge: Control
var _disp := 0.0              ## smoothed needle position (km/h)
var _target := 0.0
var _boost := 0.0             ## 0..1 fade of the boost ring
var _scale := 1.0             ## 1.0 on a desktop, smaller on a phone
var _corner := 1              ## 1 = bottom right, 0 = top left

func _ready() -> void:
	layer = 10
	_gauge = Control.new()
	_gauge.name = "Speedometer"
	_gauge.custom_minimum_size = Vector2(SIZE, SIZE)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gauge)
	_gauge.draw.connect(_draw_gauge)
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	# keep the dial glued to the bottom right corner, whatever the window size
	var vs := get_viewport() if get_viewport() != null else null
	if vs == null:
		return
	var rect := vs.get_visible_rect().size
	var s := SIZE * _scale
	var m := MARGIN * _scale
	_gauge.size = Vector2(s, s)
	if _corner == 1:
		_gauge.position = rect - Vector2(s + m, s + m)
	else:
		_gauge.position = Vector2(m, m)

## Phone layout: a smaller dial in the top left corner, so the bottom corners are
## free for the thumb sticks and the fire button.
func set_compact(on: bool) -> void:
	_scale = 0.62 if on else 1.0
	_corner = 0 if on else 1
	_layout()

func _process(delta: float) -> void:
	_disp = lerpf(_disp, _target, 1.0 - exp(-11.0 * delta))
	if _gauge != null:
		_gauge.queue_redraw()

# ---------------------------------------------------------------- public API
# (these are kept so the rest of the game keeps working; nothing is shown)

## While you are on foot the dial is pointless, so it hides itself.
func set_on_foot(v: bool) -> void:
	if _gauge != null:
		_gauge.visible = not v
	_target = 0.0 if v else _target

func update_drive(kmh: float, boosting: bool) -> void:
	_target = clampf(kmh, 0.0, MAX_KMH)
	var b := 1.0 if boosting else 0.0
	_boost = lerpf(_boost, b, 0.15)

func update_stats(_fps: int, _blocks: int, _pending: int, _cars: int,
		_lights: int, _radius: int) -> void:
	pass

func update_area(_name: String) -> void:
	pass

func toast(_msg: String, _seconds: float = 2.5) -> void:
	pass

func set_help_visible(_v: bool) -> void:
	pass

# ---------------------------------------------------------------- drawing

func _draw_gauge() -> void:
	var s := _gauge.size
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.5 - 8.0
	var col_main := Color(1, 1, 1, 0.92)

	# dial face
	_gauge.draw_circle(c, r, Color(0.03, 0.04, 0.07, 0.80))
	_gauge.draw_arc(c, r, 0.0, TAU, 72, Color(1, 1, 1, 0.16), 2.0, true)
	_gauge.draw_arc(c, r - 5.0, A0, A0 + SWEEP, 72, Color(1, 1, 1, 0.10), 1.0, true)

	# progress ring up to the current speed
	var t := clampf(_disp / MAX_KMH, 0.0, 1.0)
	var ring_col := Color("2ff2ff").lerp(Color("ff3ba7"), t)
	_gauge.draw_arc(c, r - 12.0, A0, A0 + SWEEP * t, 64, ring_col, 5.0, true)

	# boost ring (inner, pink glow)
	if _boost > 0.02:
		var bc := Color("ff3ba7")
		bc.a = 0.55 * _boost
		_gauge.draw_arc(c, r - 21.0, A0, A0 + SWEEP * t, 64, bc, 3.0, true)

	# ticks + numbers
	var font := ThemeDB.get_fallback_font()
	var step := 20.0
	var v := 0.0
	while v <= MAX_KMH + 0.1:
		var a := A0 + SWEEP * (v / MAX_KMH)
		var dir := Vector2(cos(a), sin(a))
		var major := fmod(v, 40.0) < 0.5
		var r0 := r - (30.0 if major else 26.0)
		var r1 := r - 20.0
		_gauge.draw_line(c + dir * r0, c + dir * r1,
			Color(1, 1, 1, 0.85 if major else 0.35), 2.0 if major else 1.0, true)
		if major:
			var tp := c + dir * (r - 44.0)
			var fs := 14
			var w := font.get_string_size(str(int(v)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_gauge.draw_string(font, tp - Vector2(w * 0.5, -fs * 0.35), str(int(v)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.88, 0.92, 0.96, 0.8))
		v += step

	# unit label
	var unit := "km/h"
	var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_gauge.draw_string(font, c + Vector2(-uw * 0.5, r * 0.52), unit,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 0.95, 0.55))

	# needle
	var na := A0 + SWEEP * t
	var ndir := Vector2(cos(na), sin(na))
	var ncol := Color("ff4d6d")
	_gauge.draw_line(c - ndir * 12.0, c + ndir * (r - 30.0), Color(0, 0, 0, 0.35), 7.0, true)
	_gauge.draw_line(c - ndir * 10.0, c + ndir * (r - 30.0), ncol, 4.0, true)
	_gauge.draw_circle(c, 10.0, Color(0.10, 0.11, 0.13))
	_gauge.draw_circle(c, 10.0, Color(1, 1, 1, 0.20))
	_gauge.draw_circle(c, 4.5, ncol)

	# glass highlight
	_gauge.draw_arc(c - Vector2(0, 2), r - 3.0, PI * 1.08, PI * 1.38, 16,
		Color(1, 1, 1, 0.10), 6.0, true)
