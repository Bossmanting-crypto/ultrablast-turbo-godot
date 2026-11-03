extends Node
## Input (port of the input block in 00_core.js). Two action buttons: BOOST (hold to charge rings, let go to
## blast) and HOMING (dash into the locked target). Precision taps (puzzles, supercut, tunnel exit) accept either.
## Bindings live in the project Input Map (tools/setup_input.gd). Edge presses become queued events that the
## game loop consumes; held state is polled every frame by poll().

var events: Array = []          # [{t: "boost"|"home"|"dir"|"pause"|"mute"|"next"|"skip"|"tap", d?: "up"...}]
var steer_x := 0.0
var steer_y := 0.0
var aim_x := 0.0
var aim_y := 0.0
var charge_held := false
var mx := 0.0                   # mouse in -1..1 (x right, y down) like the web build
var my := 0.0
var mouse_t := -99.0
## Mouse flight (v5, playtest: "it flies itself when I leave the controls"): the mouse is a virtual stick you push by
## moving it; it springs back to centre a moment after you stop, so a resting hand means straight flight. It used to
## be the cursor's offset from the screen centre, which kept turning wherever you left it. Clicking the game
## captures the pointer; menus and puzzles release it.
const MOUSE_PX := 160.0
var mvx := 0.0
var mvy := 0.0
var poll_t := 0.0
var kb_t := -99.0
var dev := "kb"                 # "kb" or "pad": prompts and labels follow it
var pad_hold := false           # the A that pressed LAUNCH is not a boost
var invert_y := false
var joy_id := -1
var now := 0.0                  # real seconds since boot (NOW in the web build)
var test_hold := false          # tools/autotest.gd: hold boost
var test_steer = null           # tools/autotest.gd: Vector2 steering override

signal device_changed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	Input.joy_connection_changed.connect(_on_joy)
	var pads := Input.get_connected_joypads()
	if pads.size(): joy_id = pads[0]

func _on_joy(id: int, connected: bool) -> void:
	if connected:
		joy_id = id
		if GAME and GAME.has_method("pad_note"): GAME.pad_note("Controller connected. Stick or D-pad to choose, A to select.")
	elif id == joy_id:
		var pads := Input.get_connected_joypads()
		joy_id = pads[0] if pads.size() else -1

func is_pad() -> bool: return dev == "pad"

## Label by device: KL(kb, pad) in the web build.
func kl(kb: String, pad: String = "") -> String:
	return pad if is_pad() and pad != "" else kb

func _set_dev(d: String) -> void:
	if dev != d:
		dev = d
		device_changed.emit()

func _process(delta: float) -> void:
	now += delta

func _unhandled_input(e: InputEvent) -> void:
	if REC.typing: return
	if e is InputEventKey and e.pressed and not e.echo: _set_dev("kb"); kb_t = now
	elif e is InputEventMouseMotion:
		var vp := get_viewport().get_visible_rect().size
		mx = e.position.x / vp.x * 2.0 - 1.0
		my = e.position.y / vp.y * 2.0 - 1.0
		if GAME.state == "play" and absf(e.relative.x) + absf(e.relative.y) > 0.5:
			mvx = clampf(mvx + e.relative.x / MOUSE_PX, -1, 1); mvy = clampf(mvy + e.relative.y / MOUSE_PX, -1, 1)
			mouse_t = now
		if absf(e.relative.x) + absf(e.relative.y) > 3.0: _set_dev("kb")
		return
	elif e is InputEventMouseButton and e.pressed:
		mouse_t = now
		if GAME.state == "play" and P.mode != "puzzle" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif (e is InputEventJoypadButton and e.pressed) or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		joy_id = e.device
		_set_dev("pad")
	if e is InputEventKey and e.echo: return
	var play: bool = GAME.state == "play"
	if e.is_action_pressed("boost"):
		if not (e is InputEventJoypadButton or e is InputEventJoypadMotion) or not pad_hold:
			events.append({"t": "boost"})
	if e.is_action_pressed("homing"):
		events.append({"t": "home", "aim": e is InputEventMouseButton or is_pad(), "pad": is_pad()})
	for d in ["up", "down", "left", "right"]:
		if e.is_action_pressed("dir_" + d): events.append({"t": "dir", "d": d})
	if e.is_action_pressed("pause"): events.append({"t": "pause"})
	if e.is_action_pressed("mute"): events.append({"t": "mute"})
	if e.is_action_pressed("next"): events.append({"t": "next"})
	if e.is_action_pressed("skip") and play and TUT.active: events.append({"t": "skip"})
	if e.is_action_pressed("note") and play: REC.open_typed()
	if play: get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: charge_held = false

## Per frame: steering, aim and the held boost.
func poll() -> void:
	var pad_x := 0.0
	var pad_y := 0.0
	var pad_charge := false
	if joy_id >= 0:
		var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.15 else v
		pad_x = dz.call(Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X))
		pad_y = dz.call(Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y))
		var held := Input.is_joy_button_pressed(joy_id, JOY_BUTTON_A) or Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_RIGHT) > 0.35
		if GAME.state != "play": pad_hold = held; pad_x = 0.0; pad_y = 0.0
		else:
			if pad_hold and not held: pad_hold = false
			pad_charge = not pad_hold and held
		if absf(pad_x) + absf(pad_y) > 0.3 or pad_charge: _set_dev("pad"); kb_t = now
	var x := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var y := Input.get_action_strength("steer_up") - Input.get_action_strength("steer_down")
	var ax := x
	var ay := -y
	if pad_x != 0.0 or pad_y != 0.0:
		x = pad_x; y = -pad_y; ax = pad_x; ay = pad_y
	elif x == 0.0 and y == 0.0 and mouse_t > kb_t:
		var shape := func(v: float) -> float:
			var a := absf(v)
			if a < 0.04: return 0.0
			return signf(v) * minf(1.0, (a - 0.04) / 0.96)
		x = shape.call(mvx); y = -shape.call(mvy)
		ax = mvx; ay = mvy
	# the virtual stick springs back to centre once the mouse rests
	var pdt := clampf(now - poll_t, 0.0, 0.1); poll_t = now
	if now - mouse_t > 0.12:
		var kk := exp(-7.0 * pdt); mvx *= kk; mvy *= kk
	if (GAME.state != "play" or P.mode == "puzzle") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; mvx = 0.0; mvy = 0.0
	if invert_y: y = -y
	if test_steer != null: x = test_steer.x; y = test_steer.y
	steer_x = x; steer_y = y; aim_x = ax; aim_y = ay
	var kb_charge := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	charge_held = kb_charge or pad_charge or test_hold

## Rumble follows screen shake: every hit that shakes the camera also shakes the hands.
func rumble(strong: float, weak: float, ms: float) -> void:
	if joy_id < 0 or dev != "pad" or U.sget("ub_rumble", true) == false: return
	Input.start_joy_vibration(joy_id, minf(1.0, weak), minf(1.0, strong), ms / 1000.0)

## Puzzle input helpers (the web build filtered the event list with these).
static func is_boost_ev(e: Dictionary) -> bool: return e.t == "boost"
static func is_home_ev(e: Dictionary) -> bool: return e.t == "home"
static func is_tap_ev(e: Dictionary) -> bool: return e.t == "boost" or e.t == "home" or e.t == "tap"
