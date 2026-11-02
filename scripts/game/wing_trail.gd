class_name WingTrail
extends MeshInstance3D
## A wingtip vapour trail: samples the tip's world position every frame and draws a camera-facing ribbon that
## fades with age. Intensity per sample comes from speed and turn rate, so the trails bloom when you push.

const LIFE := 0.5
const MAX_LEN := 4.5       # metres: the chase camera sits ~8 m back, so the trail must end before it
const MAX_PTS := 48
const SHADER := preload("res://shaders/wing_trail.gdshader")

var pts: Array = []        # {p: Vector3, t: float, a: float}
var width := 0.05
var mat: ShaderMaterial
var im := ImmediateMesh.new()

func _init() -> void:
	top_level = true
	mesh = im
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0

func set_color(c: Color, pearl: float) -> void:
	mat.set_shader_parameter("uCol", Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("uPearl", pearl)

func clear() -> void:
	pts.clear()
	im.clear_surfaces()

func push(p: Vector3, intensity: float, now: float, cam_pos: Vector3) -> void:
	if pts.is_empty() or pts[0].p.distance_squared_to(p) > 0.0004:
		pts.push_front({p = p, t = now, a = intensity})
	else:
		pts[0].a = intensity
	while pts.size() > MAX_PTS or (pts.size() > 0 and now - pts[pts.size() - 1].t > LIFE):
		pts.pop_back()
	var run := 0.0
	for i in range(1, pts.size()):
		run += pts[i].p.distance_to(pts[i - 1].p)
		if run > MAX_LEN:
			pts.resize(i + 1)
			break
	_rebuild(now, cam_pos)

func _rebuild(now: float, cam_pos: Vector3) -> void:
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var any := false
	for q in pts:
		if q.a > 0.01:
			any = true
			break
	if not any:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, mat)
	for i in pts.size():
		var q: Dictionary = pts[i]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)].p
		var prv: Vector3 = pts[maxi(i - 1, 0)].p
		var tan := (prv - nxt)
		if tan.length_squared() < 1e-8:
			tan = Vector3.FORWARD
		var side := tan.cross(cam_pos - q.p).normalized()
		var age := clampf(maxf((now - q.t) / LIFE, _dist_to(i) / MAX_LEN), 0.0, 1.0)
		var w := width * (1.0 + age * 1.6)  # vapour spreads as it ages
		im.surface_set_color(Color(1, 1, 1, q.a))
		im.surface_set_uv(Vector2(age, 0.0))
		im.surface_add_vertex(q.p + side * w)
		im.surface_set_color(Color(1, 1, 1, q.a))
		im.surface_set_uv(Vector2(age, 1.0))
		im.surface_add_vertex(q.p - side * w)
	im.surface_end()

func _dist_to(i: int) -> float:
	var d := 0.0
	for k in range(1, i + 1):
		d += pts[k].p.distance_to(pts[k - 1].p)
	return d
