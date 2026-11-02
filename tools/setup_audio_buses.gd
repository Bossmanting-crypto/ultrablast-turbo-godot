extends SceneTree
## Writes res://default_bus_layout.tres (run after changing the mix):
##   godot --headless --path . --script res://tools/setup_audio_buses.gd
## Mirrors the web build's WebAudio graph: master limiter, music through a low-pass, sfx / ui buses,
## an engine sub-bus, a wet reverb send, and one low-passed bus per engine/ambience loop.

const LOOPS := {"engine_bed": "Engine", "engine_thrust": "Engine", "engine_whine": "Engine", "afterburner": "Engine",
	"charge_hum": "SFX", "tunnel_wind": "SFX", "iris_drone": "SFX"}

func add_bus(name: String, send: String, db := 0.0) -> int:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name); AudioServer.set_bus_send(i, send); AudioServer.set_bus_volume_db(i, db)
	return i

func _init() -> void:
	while AudioServer.bus_count > 1: AudioServer.remove_bus(1)
	var lim := AudioEffectCompressor.new(); lim.threshold = -10.0; lim.ratio = 8.0; lim.attack_us = 2000.0; lim.release_ms = 200.0
	AudioServer.add_bus_effect(0, lim)
	var music := add_bus("Music", "Master", linear_to_db(0.35))
	var lp := AudioEffectLowPassFilter.new(); lp.cutoff_hz = 2400.0; lp.resonance = 0.6
	AudioServer.add_bus_effect(music, lp)
	add_bus("SFX", "Master", linear_to_db(0.9))
	add_bus("UI", "Master", linear_to_db(0.9 * 0.85))
	add_bus("Engine", "SFX")
	var rev := add_bus("Reverb", "Master", linear_to_db(0.55))
	var rv := AudioEffectReverb.new(); rv.room_size = 0.7; rv.damping = 0.55; rv.wet = 1.0; rv.dry = 0.0; rv.spread = 0.9
	AudioServer.add_bus_effect(rev, rv)
	for n in LOOPS:
		var b := add_bus("L_" + n, LOOPS[n])
		var f := AudioEffectLowPassFilter.new(); f.cutoff_hz = 18000.0
		AudioServer.add_bus_effect(b, f)
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
	print("bus layout saved: ", err == OK, " buses: ", AudioServer.bus_count)
	quit()
