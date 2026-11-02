class_name Jet
extends Node3D
## A procedural jet (makeJet in 20_ship.js): faceted lathe fuselage, extruded wings and fins, glass canopy,
## glowing accent strips and two exhaust flames. Used for the player ship and the enemy jets.
## The nose points along +Z, like the web build, so Basis(right, up, fwd) orients it directly.

var inner: Node3D
var flames: Array[MeshInstance3D] = []
var flame_mat: ShaderMaterial
var flame_mat2: ShaderMaterial
var needle_mat: ShaderMaterial
var body_mat: StandardMaterial3D
var nozzles: Array[Vector3] = []
var noz_m: StandardMaterial3D
## local wingtip positions (inside `inner`, so trails follow the bank)
const WINGTIPS := [Vector3(1.5, -0.03, -0.82), Vector3(-1.5, -0.03, -0.82)]

const FLAME_SHADER := preload("res://shaders/thruster.gdshader")


static func make(body_color: Color, accent: Color, flame_a: Color, flame_b: Color, s := 1.0) -> Jet:
	var j := Jet.new()
	j._build(body_color, accent, flame_a, flame_b)
	j.scale = Vector3.ONE * s
	return j

func _flame_mat(c1: Color, c2: Color, layer: int) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = FLAME_SHADER
	m.set_shader_parameter("uC1", Vector3(c1.r, c1.g, c1.b)); m.set_shader_parameter("uC2", Vector3(c2.r, c2.g, c2.b))
	m.set_shader_parameter("uPow", 1.0)
	m.set_shader_parameter("uLayer", layer)
	m.set_shader_parameter("uPearl", 0.25)
	m.set_shader_parameter("uSeed", randf() * 10.0)
	return m

func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new(); m.mesh = mesh; m.material_override = mat; m.position = pos
	inner.add_child(m); return m

func _build(body_color: Color, accent: Color, flame_a: Color, flame_b: Color) -> void:
	inner = Node3D.new(); inner.name = "Inner"; add_child(inner)
	body_mat = StandardMaterial3D.new(); body_mat.albedo_color = body_color; body_mat.metallic = 0.6; body_mat.roughness = 0.28
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var prof := [Vector2(0, -1.15), Vector2(0.26, -1.05), Vector2(0.36, -0.45), Vector2(0.31, 0.35), Vector2(0.15, 1.0), Vector2(0, 1.45)]
	_mi(Meshes.lathe(prof, 8, Transform3D(Basis.from_scale(Vector3(1, 0.62, 1)) * Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO)), body_mat)
	var wing := Meshes.extrude([Vector2(0.2, -0.45), Vector2(1.55, 0.7), Vector2(1.42, 0.95), Vector2(0.2, 0.8)], 0.06,
		Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, -0.03, 0)))
	_mi(wing, body_mat)
	_mi(wing, body_mat).scale.x = -1
	var fin := Meshes.extrude([Vector2(0, 0), Vector2(0.55, -0.15), Vector2(0.6, 0.05), Vector2(0.1, 0.45)], 0.04, Transform3D(Basis(Vector3.UP, -PI / 2), Vector3.ZERO))
	var f1 := _mi(fin, body_mat, Vector3(0.22, 0.12, -0.95)); f1.rotation.z = -0.35
	var f2 := _mi(fin, body_mat, Vector3(-0.22, 0.12, -0.95)); f2.rotation.z = 0.35
	var glass_m := StandardMaterial3D.new(); glass_m.albedo_color = Color.html("#10142a"); glass_m.metallic = 1.0; glass_m.roughness = 0.05
	var glass := _mi(Meshes.sphere(0.22, 12, 8), glass_m, Vector3(0, 0.17, 0.35)); glass.scale = Vector3(0.9, 0.55, 2.0)
	var acc_m := Meshes.unshaded(accent, false, false)
	for sx in [1.0, -1.0]:
		var b := BoxMesh.new(); b.size = Vector3(0.035, 0.04, 1.75)
		var s := _mi(b, acc_m, Vector3(sx * 0.88, 0.02, 0.15)); s.rotation.y = sx * 0.83
	var noz := Meshes.cylinder(0.13, 0.17, 0.3, 10)
	# dark metal bell; only a faint glow of the exhaust colour (a bright emissive bell bloomed into a white blob)
	noz_m = StandardMaterial3D.new(); noz_m.albedo_color = Color.html("#1a1a26"); noz_m.metallic = 0.9; noz_m.roughness = 0.35
	noz_m.emission_enabled = true; noz_m.emission = flame_a.linear_to_srgb().clamp() * 0.5; noz_m.emission_energy_multiplier = 0.35
	var cone := Meshes.flame_cone(0.17, 20)       # sheath
	var core_cone := Meshes.flame_cone(0.08, 14)  # jet
	var needle := Meshes.flame_cone(0.014, 6)     # axis line
	flame_mat = _flame_mat(flame_a, flame_b, 0)
	flame_mat2 = _flame_mat(flame_a, flame_b, 1)
	needle_mat = _flame_mat(Color(1, 1, 1), flame_a, 2)
	for sx in [0.2, -0.2]:
		var n := _mi(noz, noz_m, Vector3(sx, 0, -1.12)); n.rotation.x = PI / 2
		var f := _mi(cone, flame_mat, Vector3(sx, 0, -1.25))
		var fc := _mi(core_cone, flame_mat2, Vector3(sx, 0, -1.25))
		var nd := _mi(needle, needle_mat, Vector3(sx, 0, -1.25))
		flames.append(f); flames.append(fc); flames.append(nd); nozzles.append(Vector3(sx, 0, -1.25))

func set_flame_colors(c1: Color, c2: Color, core1: Color, core2: Color) -> void:
	noz_m.emission = (c1 * 0.5).linear_to_srgb().clamp()
	flame_mat.set_shader_parameter("uC1", Vector3(c1.r, c1.g, c1.b)); flame_mat.set_shader_parameter("uC2", Vector3(c2.r, c2.g, c2.b))
	flame_mat2.set_shader_parameter("uC1", Vector3(c1.r, c1.g, c1.b)); flame_mat2.set_shader_parameter("uC2", Vector3(c2.r, c2.g, c2.b))
	needle_mat.set_shader_parameter("uC1", Vector3(core1.r, core1.g, core1.b)); needle_mat.set_shader_parameter("uC2", Vector3(core2.r, core2.g, core2.b))

## pearl sheen on the exhaust: the player runs it full, enemy jets only a hint
func set_pearl(p: float) -> void:
	flame_mat.set_shader_parameter("uPearl", p); flame_mat2.set_shader_parameter("uPearl", p); needle_mat.set_shader_parameter("uPearl", p)

func nozzle_world(i: int) -> Vector3:
	return inner.global_transform * nozzles[i]

func wingtip_world(i: int) -> Vector3:
	return inner.global_transform * WINGTIPS[i]

func set_flame_pow(a: float, b: float) -> void:
	flame_mat.set_shader_parameter("uPow", a); flame_mat2.set_shader_parameter("uPow", b); needle_mat.set_shader_parameter("uPow", b)
