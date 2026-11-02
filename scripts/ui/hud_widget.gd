class_name HudWidget
extends Control
## Small custom-drawn HUD pieces (the CSS gauges, cells, pips and chips of the web build).
enum Kind { BAR, CELLS, PIPS, BOOM, HOME, IRIS, RANKBAR, GAUGE }
@export var kind: Kind = Kind.BAR
@export var color := Color(1, 0.82, 0.48)
@export var color2 := Color(1, 0.48, 0.18)
var value := 0.0          # 0..1 fill (bars), cooldown progress (boom), aperture (iris)
var value2 := 0.0         # second bar (momentum under boost)
var cells := [0.0, 0.0, 0.0]
var pips := [false, false, false]
var rail := [false, false, false]
var gold_avail := false
var gold_on := false
var flags := {}           # locked, ready, cool, dash, warn, close

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	var s := size
	var peach := Color(0.957, 0.776, 0.627)
	var night := Color(0.04, 0.043, 0.133, 0.55)
	match kind:
		Kind.BAR, Kind.RANKBAR:
			draw_rect(Rect2(Vector2.ZERO, s), night)
			if kind == Kind.BAR: draw_rect(Rect2(Vector2.ZERO, s), Color(peach, 0.6), false, 1.0)
			_grad_rect(Rect2(0, 0, s.x * clampf(value, 0, 1), s.y), color, color2)
		Kind.GAUGE:
			draw_rect(Rect2(Vector2.ZERO, s), night)
			draw_rect(Rect2(Vector2.ZERO, s), Color(peach, 0.45), false, 1.0)
			_grad_rect(Rect2(0, 0, s.x * clampf(value, 0, 1), s.y), Color.html("#ff7a2e"), Color.html("#fffbe0"))
			draw_rect(Rect2(0, s.y - 2, s.x * clampf(value2, 0, 1), 2), Color(0.56, 0.91, 1, 0.75))
		Kind.CELLS:
			var locked: bool = flags.get("locked", true)
			var ready: bool = flags.get("ready", false)
			for i in 3:
				var x := i * 35.0
				var f: float = clampf(cells[i], 0, 1)
				var pts := PackedVector2Array([Vector2(x + 3, 0), Vector2(x + 33, 0), Vector2(x + 30, 11), Vector2(x, 11)])
				draw_colored_polygon(pts, night)
				if f > 0:
					var w := 30.0 * f
					var c1 := Color.html("#7a6d92") if locked else Color.html("#ff7a2e")
					var c2 := Color.html("#7a6d92") if locked else Color.html("#ffd27a")
					draw_polygon(PackedVector2Array([Vector2(x + 3, 0), Vector2(x + 3 + w, 0), Vector2(x + w, 11), Vector2(x, 11)]), PackedColorArray([c1, c2, c2, c1]))
				var bc := Color(0.725, 0.663, 0.788, 0.45) if locked else Color(1, 0.824, 0.478, 0.6)
				if f >= 1 and not locked: bc = Color(1, 0.824, 0.478, 1.0 if not ready else 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 10.0))
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), bc, 1.0, true)
		Kind.PIPS:
			var cool: bool = flags.get("cool", false)
			for i in 3:
				var c := Vector2(9 + i * 26, s.y / 2)
				var on: bool = pips[i]
				var a := 1.0 if on else (0.2 if cool else 0.45)
				if rail[i] and not on: draw_arc(c, 9, 0, TAU, 24, Color(0.86, 0.91, 0.66, 0.9), 2, true)
				else: draw_arc(c, 9, 0, TAU, 24, Color(peach, a), 2, true)
				if on: draw_circle(c, 8, peach)
			var g := Vector2(9 + 3 * 26 + 2, s.y / 2)
			var gold := Color.html("#ffd27a")
			draw_arc(g, 11, 0, TAU, 28, Color(gold, 1.0 if gold_on else (0.85 if gold_avail else 0.15)), 2, true)
			if gold_on: draw_circle(g, 10, gold)
		Kind.BOOM:
			var c := s / 2
			var r := minf(s.x, s.y) / 2
			draw_circle(c, r, Color(0.04, 0.043, 0.133, 0.6))
			if value > 0: draw_arc(c, r - 2, -PI / 2, -PI / 2 + TAU * clampf(value, 0, 1), 40, Color(1, 0.416, 0.816, 0.9), 4, true)
			draw_circle(c, r - 4, Color(0.055, 0.047, 0.15, 0.9))
			if flags.get("ready", false): draw_arc(c, r + 1, 0, TAU, 40, Color(1, 0.54, 0.84, 0.7), 2, true)
			_center_text("BOOM", 9, Color(1, 0.953, 0.894))
		Kind.HOME:
			var c := s / 2
			var r := minf(s.x, s.y) / 2 - 1
			draw_circle(c, r, Color(0.055, 0.047, 0.15, 0.7))
			var col := Color(0.56, 0.91, 1, 0.45)
			var tc := Color.html("#8fe9ff")
			if flags.get("locked", false): col = Color.html("#ffd27a"); tc = col
			if flags.get("dash", false): col = Color.WHITE; tc = col
			draw_arc(c, r, 0, TAU, 40, col, 2, true)
			_center_text("HOMING", 8, tc)
		Kind.IRIS:
			var c := s / 2
			var r := minf(s.x, s.y) / 2 - 1
			var warn: bool = flags.get("warn", false)
			var close: bool = flags.get("close", false)
			var blink := warn and int(Time.get_ticks_msec() / 250) % 2 == 0
			var bc := Color(1, 0.54, 0.84) if warn or close else Color(0.79, 0.66, 1, 0.7)
			if blink: bc.a = 0.25
			draw_circle(c, r * clampf(value, 0.1, 1), Color(0.56, 0.91, 1, 0.5))
			draw_arc(c, r, 0, TAU, 32, bc, 2, true)

func _grad_rect(r: Rect2, a: Color, b: Color) -> void:
	if r.size.x <= 0: return
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([a, b, b, a]))

func _center_text(t: String, fs: int, col: Color) -> void:
	var f: Font = D2.ui_bold
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(size.x / 2 - w / 2, size.y / 2 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
