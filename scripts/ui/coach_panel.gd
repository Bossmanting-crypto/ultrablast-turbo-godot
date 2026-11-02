class_name CoachPanel
extends PanelContainer
## The coach card (#coach in the web build): Flight School step cards and one-time run hints.
## Classes from the CSS become flags here: tut (cyan border), passed (gold border), compact (centred strip
## during puzzles and rifts), hidden_pz (faded out while an overlay carries its own instructions).

@onready var step_lbl: Label = %Step
@onready var skip_btn: Button = %Skip
@onready var dots: Control = %Dots
@onready var title_lbl: Label = %Title
@onready var keys_box: HFlowContainer = %Keys
@onready var body: RichTextLabel = %Body
@onready var count_lbl: Label = %Count
@onready var prog_bar: Control = %Prog
@onready var next_btn: Button = %Next

var tut := false
var passed := false
var compact := false
var hidden_pz := false
var prog = null
var dot_n := 0
var dot_cur := 0
var _style: StyleBoxFlat
var _tween: Tween

func _ready() -> void:
	visible = false
	_style = (get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	add_theme_stylebox_override("panel", _style)
	dots.draw.connect(_draw_dots)
	prog_bar.draw.connect(_draw_prog)
	skip_btn.pressed.connect(func(): Ctl.events.append({"t": "skip"}))
	next_btn.pressed.connect(func(): Ctl.events.append({"t": "next"}))
	skip_btn.focus_mode = Control.FOCUS_NONE
	next_btn.focus_mode = Control.FOCUS_NONE
	_layout()

func _process(_d: float) -> void:
	if not visible: return
	var target := 0.0 if hidden_pz else 1.0
	modulate.a = move_toward(modulate.a, target, _d * 6.0)
	if passed:
		var k := 0.5 + 0.5 * sin(Ctl.now * 5.7)
		next_btn.modulate = Color(1, 1, 1).lerp(Color(1.15, 1.1, 0.95), k)

func hide_card() -> void:
	visible = false; tut = false; compact = false; hidden_pz = false; passed = false
	_layout()

func render(step: String, title: String, text: String, count: String, p, skip: bool, is_tut: bool, late := false) -> void:
	visible = true; tut = is_tut
	step_lbl.text = step; title_lbl.text = title
	body.text = text
	count_lbl.text = count
	prog = p
	prog_bar.visible = p != null and not compact
	skip_btn.visible = skip
	if not is_tut:
		_clear_keys(); dot_n = 0; next_btn.visible = false; passed = false
	_layout()
	# slide in from the left (later, if a big event text is on screen)
	if _tween: _tween.kill()
	modulate.a = 0.0
	var x0 := position.x
	position.x = x0 - 18
	_tween = create_tween()
	if late: _tween.tween_interval(1.15)
	_tween.tween_property(self, "position:x", x0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.35)

func set_count(t: String) -> void:
	count_lbl.text = t
func set_prog(v: float) -> void: prog = v; prog_bar.queue_redraw()

func set_keys(tokens: Array) -> void:
	_clear_keys()
	for tok in tokens:
		var s: String = tok
		var l := Label.new()
		if s.begins_with("kc:"):
			l.text = s.substr(3); l.theme_type_variation = &"Kbd"
			l.add_theme_font_size_override("font_size", 13)
		else:
			l.text = s.to_upper(); l.add_theme_color_override("font_color", Color.html("#b9a9c9")); l.add_theme_font_size_override("font_size", 11)
		keys_box.add_child(l)
	_layout()

func _clear_keys() -> void:
	for c in keys_box.get_children(): c.queue_free()

func set_dots(n: int, cur: int) -> void:
	dot_n = n; dot_cur = cur; dots.queue_redraw(); _layout()

func set_passed(p: bool, label: String, key: String) -> void:
	passed = p
	next_btn.visible = p
	next_btn.text = "%s  [%s]" % [label, key]
	_layout()

func set_compact(c: bool) -> void:
	if c == compact: return
	compact = c; _layout()

func set_hidden_pz(h: bool) -> void: hidden_pz = h

func _layout() -> void:
	var vs := get_viewport_rect().size
	body.visible = not compact
	keys_box.visible = not compact and keys_box.get_child_count() > 0
	dots.visible = not compact and dot_n > 0
	prog_bar.visible = prog != null and not compact
	title_lbl.add_theme_font_size_override("font_size", 15 if compact else 20)
	var w := minf(460, vs.x * 0.84) if compact else minf(330, vs.x - 32)
	custom_minimum_size.x = w
	size = Vector2(w, 0)
	_shrink.call_deferred()
	if compact: position = Vector2((vs.x - w) / 2, 92)
	else: position = Vector2(16, clampf(vs.y * 0.19, 100, 180))
	var bc := Color(0.957, 0.776, 0.627, 0.4)
	if tut: bc = Color(0.56, 0.91, 1, 0.55)
	if passed: bc = Color.html("#ffd27a")
	_style.border_color = bc
	_style.shadow_color = Color(1, 0.82, 0.48, 0.35) if passed else Color(0, 0, 0, 0.35)

## a PanelContainer never shrinks on its own: fit it to its content after text or width changes
func _shrink() -> void:
	size = Vector2(custom_minimum_size.x, get_combined_minimum_size().y)

func _draw_dots() -> void:
	if dot_n <= 0: return
	var w := dots.size.x
	var gap := 4.0
	var dw := (w - gap * (dot_n - 1)) / dot_n
	for k in dot_n:
		var c := Color(0.957, 0.776, 0.627, 0.18)
		if k < dot_cur - 1: c = Color.html("#8fe9ff")
		elif k == dot_cur - 1: c = Color.html("#ffd27a")
		dots.draw_rect(Rect2(k * (dw + gap), 0, dw, 3), c)

func _draw_prog() -> void:
	var s := prog_bar.size
	prog_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.043, 0.133, 0.6))
	var f := clampf(float(prog) if prog != null else 0.0, 0, 1)
	if f > 0:
		var a := Color.html("#8fe9ff")
		var b := Color.html("#ffd27a")
		prog_bar.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * f, 0), Vector2(s.x * f, s.y), Vector2(0, s.y)]), PackedColorArray([a, b, b, a]))
