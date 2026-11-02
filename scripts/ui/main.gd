extends Node
## Main scene: owns the 3D world, camera, lens post, overlays, HUD and screens, and hands them to GAME.

func _ready() -> void:
	# the sun shines from (-0.5, 0.6, 0.6) toward the core, as in the web build
	var sun: DirectionalLight3D = %Sun
	sun.look_at_from_position(Vector3(-0.5, 0.6, 0.6) * 100.0, Vector3.ZERO)
	GAME.boot(self)
	if OS.get_cmdline_user_args().has("--test"):
		var t = load("res://tools/autotest.gd").new()
		add_child(t)
