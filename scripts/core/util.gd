extends Node
## Shared helpers (port of the utils block in 00_core.js) plus a tiny persistent key/value store.
## Godot already has clamp/lerp/smoothstep; the ones here keep the JS argument order and behaviour.

const SAVE_PATH := "user://ultrablast.cfg"
var _cfg := ConfigFile.new()

func _ready() -> void:
	_cfg.load(SAVE_PATH)

# ---------- maths ----------
func damp(a: float, b: float, k: float, dt: float) -> float:
	return lerp(a, b, 1.0 - exp(-k * dt))

func smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func rand(a: float = 0.0, b: float = 1.0) -> float:
	return a + randf() * (b - a)

func randi_r(a: int, b: int) -> int:
	return randi_range(a, b)

func pick(arr: Array):
	return arr[randi() % arr.size()]

func rand_unit() -> Vector3:
	var u := randf_range(-1.0, 1.0)
	var th := randf() * TAU
	var s := sqrt(1.0 - u * u)
	return Vector3(s * cos(th), u, s * sin(th))

## Deterministic generator (mulberry32) so glyph shapes match the web build seed for seed.
class Mulberry:
	var a: int
	func _init(seed: int) -> void:
		a = seed & 0xFFFFFFFF
	func next() -> float:
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t: int = _imul(a ^ (a >> 15), 1 | a)
		t = ((t + _imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
	static func _imul(x: int, y: int) -> int:
		return (x * y) & 0xFFFFFFFF

## A rotation that turns +Y onto dir (three.js Quaternion.setFromUnitVectors(UP, dir)).
func basis_from_up(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var q := Quaternion(Vector3.UP, d) if absf(d.dot(Vector3.UP)) < 0.9999 else (Quaternion.IDENTITY if d.y > 0 else Quaternion(Vector3.RIGHT, PI))
	return Basis(q)

## Basis whose -Z looks along fwd with the given up (three.js Object3D.lookAt for non-cameras points +Z; callers pick).
func basis_look(fwd: Vector3, up: Vector3 = Vector3.UP) -> Basis:
	var f := fwd.normalized()
	if absf(f.dot(up.normalized())) > 0.999:
		up = Vector3.RIGHT if absf(f.x) < 0.9 else Vector3.FORWARD
	return Basis.looking_at(f, up)

## +Z facing version, matching three.js lookAt on meshes (tori, planes face the target with their +Z).
func basis_face(fwd: Vector3, up: Vector3 = Vector3.UP) -> Basis:
	var b := basis_look(-fwd, up)
	return b

func set_length(v: Vector3, l: float) -> Vector3:
	var n := v.length()
	return v * (l / n) if n > 1e-9 else v

func hex(c: String) -> Color:
	return Color.html(c)

# ---------- store (localStorage stand-in) ----------
func sget(k: String, d = null):
	if not _cfg.has_section_key("store", k): return d
	return _cfg.get_value("store", k)

func sset(k: String, v) -> void:
	_cfg.set_value("store", k, v)
	_cfg.save(SAVE_PATH)

# ---------- events ----------
static func is_boost_ev(e: Dictionary) -> bool: return e.t == "boost"
static func is_home_ev(e: Dictionary) -> bool: return e.t == "home"
static func is_tap_ev(e: Dictionary) -> bool: return e.t == "boost" or e.t == "home" or e.t == "tap"
