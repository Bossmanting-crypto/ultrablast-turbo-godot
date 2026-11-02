class_name CatmullCurve
extends RefCounted
## Centripetal Catmull-Rom spline with arc-length parameterisation and rotation-minimising frames.
## Mirrors three.js CatmullRomCurve3('centripetal') + computeFrenetFrames so rift tunnels bend the same way.

var points: PackedVector3Array
var _lengths: PackedFloat32Array
const DIV := 200

func _init(pts: PackedVector3Array) -> void:
	points = pts
	_lengths.resize(DIV + 1)
	var last := get_point(0.0)
	var sum := 0.0
	_lengths[0] = 0.0
	for i in range(1, DIV + 1):
		var p := get_point(float(i) / DIV)
		sum += p.distance_to(last)
		_lengths[i] = sum
		last = p

func get_length() -> float:
	return _lengths[DIV]

static func _cr(x0: float, x1: float, x2: float, x3: float, dt0: float, dt1: float, dt2: float, t: float) -> float:
	var t1 := (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
	var t2 := (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
	t1 *= dt1; t2 *= dt1
	var c0 := x1
	var c1 := t1
	var c2 := -3.0 * x1 + 3.0 * x2 - 2.0 * t1 - t2
	var c3 := 2.0 * x1 - 2.0 * x2 + t1 + t2
	return c0 + c1 * t + c2 * t * t + c3 * t * t * t

func get_point(t: float) -> Vector3:
	var l := points.size()
	var p := (l - 1) * t
	var ip := int(floor(p))
	var w := p - ip
	if w == 0.0 and ip == l - 1:
		ip = l - 2; w = 1.0
	var p0: Vector3 = points[ip - 1] if ip > 0 else (points[0] - points[1]) + points[0]
	var p1: Vector3 = points[ip]
	var p2: Vector3 = points[ip + 1]
	var p3: Vector3 = points[ip + 2] if ip + 2 < l else (points[l - 1] - points[l - 2]) + points[l - 1]
	var dt0 := pow(p0.distance_squared_to(p1), 0.25)
	var dt1 := pow(p1.distance_squared_to(p2), 0.25)
	var dt2 := pow(p2.distance_squared_to(p3), 0.25)
	if dt1 < 1e-4: dt1 = 1.0
	if dt0 < 1e-4: dt0 = dt1
	if dt2 < 1e-4: dt2 = dt1
	return Vector3(_cr(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2, w), _cr(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2, w), _cr(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2, w))

func u_to_t(u: float) -> float:
	var target := u * _lengths[DIV]
	var lo := 0
	var hi := DIV
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var c := _lengths[mid] - target
		if c < 0.0: lo = mid + 1
		elif c > 0.0: hi = mid - 1
		else: hi = mid; break
	var i := maxi(0, hi)
	if _lengths[i] == target: return float(i) / DIV
	if i >= DIV: return 1.0
	var seg := _lengths[i + 1] - _lengths[i]
	return (i + (target - _lengths[i]) / seg) / DIV

func get_point_at(u: float) -> Vector3:
	return get_point(u_to_t(u))

func get_tangent(t: float) -> Vector3:
	var t1 := maxf(0.0, t - 1e-4)
	var t2 := minf(1.0, t + 1e-4)
	return (get_point(t2) - get_point(t1)).normalized()

func get_tangent_at(u: float) -> Vector3:
	return get_tangent(u_to_t(u))

## Returns {tangents, normals, binormals} at segments+1 evenly spaced arc-length samples.
func frames(segments: int) -> Dictionary:
	var T := PackedVector3Array(); var N := PackedVector3Array(); var B := PackedVector3Array()
	T.resize(segments + 1); N.resize(segments + 1); B.resize(segments + 1)
	for i in segments + 1: T[i] = get_tangent_at(float(i) / segments)
	var t0 := T[0]
	var mn := INF
	var nrm := Vector3.ZERO
	if absf(t0.x) <= mn: mn = absf(t0.x); nrm = Vector3(1, 0, 0)
	if absf(t0.y) <= mn: mn = absf(t0.y); nrm = Vector3(0, 1, 0)
	if absf(t0.z) <= mn: nrm = Vector3(0, 0, 1)
	var v := t0.cross(nrm).normalized()
	N[0] = t0.cross(v)
	B[0] = t0.cross(N[0])
	for i in range(1, segments + 1):
		N[i] = N[i - 1]
		var ax := T[i - 1].cross(T[i])
		if ax.length() > 1e-9:
			ax = ax.normalized()
			var th := acos(clampf(T[i - 1].dot(T[i]), -1.0, 1.0))
			N[i] = N[i].rotated(ax, th)
		B[i] = T[i].cross(N[i])
	return {"tangents": T, "normals": N, "binormals": B}
