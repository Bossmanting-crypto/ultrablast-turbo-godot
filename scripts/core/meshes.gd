class_name Meshes
extends RefCounted
## Procedural meshes that match the three.js primitives the web build uses (same axes and UV layout):
## tori lie in the XY plane (axis +Z), quads face +Z, tubes follow a CatmullCurve.
## Godot treats clockwise triangles as front faces, so index order is flipped relative to three.js.

static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	if uvs.size(): arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## three.js TorusGeometry(radius, tube, radialSegments, tubularSegments)
static func torus(radius: float, tube: float, radial: int, tubular: int) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var uv := PackedVector2Array(); var idx := PackedInt32Array()
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * TAU
			var w := float(j) / radial * TAU
			var p := Vector3((radius + tube * cos(w)) * cos(u), (radius + tube * cos(w)) * sin(u), tube * sin(w))
			v.append(p)
			n.append((p - Vector3(radius * cos(u), radius * sin(u), 0)).normalized())
			uv.append(Vector2(float(i) / tubular, float(j) / radial))
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			idx.append_array([a, d, b, b, d, c])
	return _commit(v, n, uv, idx)

## Flat-shaded polyhedra (OctahedronGeometry / IcosahedronGeometry with detail 0)
static func _poly(base: Array, faces: Array, r: float, scale: Vector3 = Vector3.ONE) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	for f in faces:
		var a: Vector3 = (base[f[0]] as Vector3).normalized() * r * scale
		var b: Vector3 = (base[f[1]] as Vector3).normalized() * r * scale
		var c: Vector3 = (base[f[2]] as Vector3).normalized() * r * scale
		var nn := (b - a).cross(c - a).normalized()
		var k := v.size()
		v.append_array([a, b, c]); n.append_array([nn, nn, nn])
		idx.append_array([k, k + 2, k + 1])
	return _commit(v, n, PackedVector2Array(), idx)

static func octahedron(r: float, scale: Vector3 = Vector3.ONE) -> ArrayMesh:
	var b := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var f := [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 2, 5], [1, 5, 3], [1, 3, 4], [1, 4, 2]]
	return _poly(b, f, r, scale)

static func icosahedron(r: float) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var b := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	return _poly(b, f, r)

## three.js TubeGeometry along a CatmullCurve (uv.x along the tube, uv.y around it)
static func tube(curve: CatmullCurve, fr: Dictionary, segments: int, radius: float, radial: int) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var uv := PackedVector2Array(); var idx := PackedInt32Array()
	var N: PackedVector3Array = fr.normals
	var B: PackedVector3Array = fr.binormals
	for i in segments + 1:
		var P := curve.get_point_at(float(i) / segments)
		for j in radial + 1:
			var a := float(j) / radial * TAU
			var nn: Vector3 = (-cos(a)) * N[i] + sin(a) * B[i]
			v.append(P + nn * radius); n.append(nn)
			uv.append(Vector2(float(i) / segments, float(j) / radial))
	for i in range(1, segments + 1):
		for j in range(1, radial + 1):
			var a := (radial + 1) * (i - 1) + (j - 1)
			var b := (radial + 1) * i + (j - 1)
			var c := (radial + 1) * i + j
			var d := (radial + 1) * (i - 1) + j
			idx.append_array([a, d, b, b, d, c])
	return _commit(v, n, uv, idx)

## Plane facing +Z (three.js PlaneGeometry)
static func quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new(); q.size = Vector2(w, h); return q

static func sphere(r: float, radial: int = 48, rings: int = 32) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; s.radial_segments = radial; s.rings = rings; return s

## three.js CylinderGeometry(top, bottom, height, radial): Y axis, centred
static func cylinder(top: float, bottom: float, h: float, radial: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = bottom; c.height = h; c.radial_segments = radial; c.rings = 1; return c

## col is LINEAR (like three.js Color(r,g,b)); StandardMaterial3D wants sRGB, so it is encoded here.
static func unshaded(col: Color, additive := false, double := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.linear_to_srgb()
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if double: m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Hex colours are sRGB (three.js converts them to linear); this gives the linear value.
static func lin(hex: String) -> Color:
	return Color.html(hex).srgb_to_linear()

## Wireframe copy of a triangle mesh (three.js wireframe: true): every triangle edge once, as lines.
static func wire(src: ArrayMesh) -> ArrayMesh:
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var seen := {}
	var out := PackedVector3Array()
	for f in range(0, idx.size(), 3):
		for e in [[idx[f], idx[f + 1]], [idx[f + 1], idx[f + 2]], [idx[f + 2], idx[f]]]:
			var a: Vector3 = v[e[0]]
			var b: Vector3 = v[e[1]]
			var key := str((a + b).snapped(Vector3.ONE * 0.001))
			if seen.has(key): continue
			seen[key] = true
			out.append(a); out.append(b)
	var la := []
	la.resize(Mesh.ARRAY_MAX)
	la[Mesh.ARRAY_VERTEX] = out
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
	return m

## Flat-shaded triangle soup from a vertex list (every 3 = one triangle, three.js CCW order).
static func flat(tris: PackedVector3Array, xf := Transform3D.IDENTITY) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var idx := PackedInt32Array()
	for f in range(0, tris.size(), 3):
		var a := xf * tris[f]
		var b := xf * tris[f + 1]
		var c := xf * tris[f + 2]
		var nn := (b - a).cross(c - a).normalized()
		var k := v.size()
		v.append_array([a, b, c]); n.append_array([nn, nn, nn])
		idx.append_array([k, k + 2, k + 1])
	return _commit(v, n, PackedVector2Array(), idx)

## three.js LatheGeometry(points, segments): profile (r, y) spun around Y.
static func lathe(profile: Array, segments: int, xf := Transform3D.IDENTITY) -> ArrayMesh:
	var grid := []
	for i in segments + 1:
		var phi := float(i) / segments * TAU
		var col := []
		for p in profile: col.append(Vector3(p.x * sin(phi), p.y, p.x * cos(phi)))
		grid.append(col)
	var tris := PackedVector3Array()
	for i in segments:
		for j in profile.size() - 1:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			tris.append_array([a, b, d, c, d, b])
	return flat(tris, xf)

## three.js ExtrudeGeometry(shape, {depth, bevelEnabled: false}) for a convex 2D polygon, extruded along +Z.
static func extrude(shape: Array, depth: float, xf := Transform3D.IDENTITY) -> ArrayMesh:
	var tris := PackedVector3Array()
	var n := shape.size()
	for i in range(1, n - 1):
		var a: Vector2 = shape[0]; var b: Vector2 = shape[i]; var c: Vector2 = shape[i + 1]
		tris.append_array([Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(c.x, c.y, depth)])
		tris.append_array([Vector3(a.x, a.y, 0), Vector3(c.x, c.y, 0), Vector3(b.x, b.y, 0)])
	for i in n:
		var p: Vector2 = shape[i]; var q: Vector2 = shape[(i + 1) % n]
		tris.append_array([Vector3(p.x, p.y, 0), Vector3(q.x, q.y, 0), Vector3(q.x, q.y, depth)])
		tris.append_array([Vector3(p.x, p.y, 0), Vector3(q.x, q.y, depth), Vector3(p.x, p.y, depth)])
	return flat(tris, xf)

## Open cone for exhaust flames: base (radius r) at z = 0, apex at z = -1, uv.x around, uv.y along.
static func flame_cone(r: float, radial: int) -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var uv := PackedVector2Array(); var idx := PackedInt32Array()
	for j in 2:
		for i in radial + 1:
			var a := float(i) / radial * TAU
			var rr := r if j == 0 else 0.0
			v.append(Vector3(cos(a) * rr, sin(a) * rr, -float(j)))
			n.append(Vector3(cos(a), sin(a), 0.15).normalized())
			uv.append(Vector2(float(i) / radial, float(j)))
	for i in radial:
		var a := i
		var b := i + 1
		var c := radial + 1 + i + 1
		var d := radial + 1 + i
		idx.append_array([a, d, b, b, d, c])
	return _commit(v, n, uv, idx)

## Line strip mesh (three.js Line) from points.
static func line_strip(points: PackedVector3Array) -> ArrayMesh:
	var la := []
	la.resize(Mesh.ARRAY_MAX)
	la[Mesh.ARRAY_VERTEX] = points
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, la)
	return m
