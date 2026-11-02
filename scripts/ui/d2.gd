class_name D2
extends RefCounted
## Canvas helpers that stand in for the web build's 2D context calls (arcs, strokes, outlined text,
## dashed lines, glyphs), so the overlay drawing code ports line for line onto CanvasItem._draw().

static var display: Font = preload("res://assets/fonts/Bungee-Regular.woff2")
static var ui_bold: Font = preload("res://assets/fonts/ChakraPetch-700.woff2")
static var ui_semi: Font = preload("res://assets/fonts/ChakraPetch-600.woff2")
static var ui: Font = preload("res://assets/fonts/ChakraPetch-400.woff2")

static func col(css: String, a: float = 1.0) -> Color:
	var c := Color.html(css); c.a *= a; return c

static func rgba(r: float, g: float, b: float, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

static func arc(c: CanvasItem, x: float, y: float, r: float, a0: float, a1: float, color: Color, w: float = 1.0) -> void:
	if r <= 0.0: return
	var segs := clampi(int(absf(a1 - a0) * r / 6.0) + 6, 6, 128)
	c.draw_arc(Vector2(x, y), r, a0, a1, segs, color, w, true)

static func ring(c: CanvasItem, x: float, y: float, r: float, color: Color, w: float = 1.0) -> void:
	arc(c, x, y, r, 0.0, TAU, color, w)

static func disc(c: CanvasItem, x: float, y: float, r: float, color: Color) -> void:
	if r > 0.0: c.draw_circle(Vector2(x, y), r, color)

static func line(c: CanvasItem, x0: float, y0: float, x1: float, y1: float, color: Color, w: float = 1.0) -> void:
	c.draw_line(Vector2(x0, y0), Vector2(x1, y1), color, w, true)

static func poly_fill(c: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	if pts.size() >= 3: c.draw_colored_polygon(pts, color)

static func poly_line(c: CanvasItem, pts: PackedVector2Array, color: Color, w: float = 1.0, closed := false) -> void:
	if pts.size() < 2: return
	var p := pts
	if closed:
		p = pts.duplicate(); p.append(pts[0])
	c.draw_polyline(p, color, w, true)

## Dashed stroke along a polyline (setLineDash([on, off])).
static func dashed(c: CanvasItem, pts: PackedVector2Array, on: float, off: float, color: Color, w: float = 1.0) -> void:
	var draw := true
	var left := on
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			var p0 := a.lerp(b, t / seg)
			var p1 := a.lerp(b, (t + step) / seg)
			if draw: c.draw_line(p0, p1, color, w, true)
			t += step; left -= step
			if left <= 0.0:
				draw = not draw; left = on if draw else off

static func arc_points(x: float, y: float, r: float, a0: float, a1: float, n: int = 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(Vector2(x + cos(a) * r, y + sin(a) * r))
	return out

## Centred text with an optional dark outline (strokeText + fillText).
static func text(c: CanvasItem, font: Font, size: int, s: String, x: float, y: float, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 0, outline_col := Color(0.04, 0.03, 0.12, 0.85)) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var px := x
	if align == HORIZONTAL_ALIGNMENT_CENTER: px = x - w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT: px = x - w
	var base := y + font.get_ascent(size) * 0.36   # canvas text in the web build was drawn on the alphabetic baseline / middle
	if outline > 0: c.draw_string_outline(font, Vector2(px, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	c.draw_string(font, Vector2(px, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Text drawn on its alphabetic baseline (ctx.textBaseline default).
static func text_base(c: CanvasItem, font: Font, size: int, s: String, x: float, y: float, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 0, outline_col := Color(0.04, 0.03, 0.12, 0.85)) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var px := x
	if align == HORIZONTAL_ALIGNMENT_CENTER: px = x - w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT: px = x - w
	if outline > 0: c.draw_string_outline(font, Vector2(px, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	c.draw_string(font, Vector2(px, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func text_width(font: Font, size: int, s: String) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Rotated/translated drawing: call push(c, x, y, rot, scale) ... pop(c).
static func push(c: CanvasItem, x: float, y: float, rot: float = 0.0, s: float = 1.0) -> void:
	c.draw_set_transform(Vector2(x, y), rot, Vector2(s, s))

static func pop(c: CanvasItem) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------- alien script glyphs (drawGlyph in 00_core.js, same seeds) ----------
static func glyph(c: CanvasItem, seed: int, x: float, y: float, s: float, color: Color, w: float, xf := Transform2D.IDENTITY) -> void:
	var r := U.Mulberry.new(seed * 9301 + 49297)
	var strokes: Array = []
	if r.next() < 0.55:
		var R := s * 0.42
		var a0 := r.next() * TAU
		var span := TAU * (0.5 + r.next() * 0.5)
		strokes.append(arc_points(x, y, R, a0, a0 + span, 20))
		if r.next() < 0.7:
			var R2 := s * (0.12 + r.next() * 0.12)
			var b0 := r.next() * TAU
			strokes.append(arc_points(x, y, R2, b0, b0 + TAU * (0.6 + r.next() * 0.4), 14))
		var ticks := int(floor(r.next() * 3))
		for i in ticks:
			var a := r.next() * TAU
			strokes.append(PackedVector2Array([Vector2(x + cos(a) * R, y + sin(a) * R), Vector2(x + cos(a) * (R + s * 0.18), y + sin(a) * (R + s * 0.18))]))
		if r.next() < 0.5:
			var a := r.next() * TAU
			strokes.append(arc_points(x + cos(a) * R * 0.62, y + sin(a) * R * 0.62, 1.5, 0, TAU, 8))
	else:
		var g := s / 3.0
		var ox := x - s / 2.0
		var oy := y - s / 2.0
		var segs := 3 + int(floor(r.next() * 3))
		var cx := int(floor(r.next() * 4))
		var cy := int(floor(r.next() * 4))
		var pl := PackedVector2Array([Vector2(ox + cx * g, oy + cy * g)])
		for i in segs:
			if r.next() < 0.5: cx = clampi(cx + (-1 if r.next() < 0.5 else 1) * (1 + int(floor(r.next() * 2))), 0, 3)
			else: cy = clampi(cy + (-1 if r.next() < 0.5 else 1) * (1 + int(floor(r.next() * 2))), 0, 3)
			pl.append(Vector2(ox + cx * g, oy + cy * g))
		strokes.append(pl)
		if r.next() < 0.5: strokes.append(arc_points(ox + g * 1.5, oy + g * 1.5, 1.6, 0, TAU, 8))
	for st in strokes:
		var p: PackedVector2Array = st
		if xf != Transform2D.IDENTITY: p = xf * p
		c.draw_polyline(p, color, w, true)
