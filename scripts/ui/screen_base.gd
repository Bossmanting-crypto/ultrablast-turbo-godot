class_name ScreenBase
extends Control
## Shared menu behaviour: the first button takes focus when the screen opens (so stick / D-pad and Enter work
## straight away), every button and checkbox clicks and hovers with the UI sounds.

func on_show() -> void:
	var b := _first_button(self)
	if b: b.grab_focus.call_deferred()

func _first_button(n: Node) -> Control:
	for c in n.get_children():
		if c is BaseButton and c.visible: return c
		var r := _first_button(c)
		if r: return r
	return null

func wire_sounds(n: Node = self) -> void:
	for c in n.get_children():
		if c is BaseButton:
			c.mouse_entered.connect(func(): AudioSys.ui("hover"))
			c.focus_entered.connect(func(): AudioSys.ui("hover"))
		wire_sounds(c)

func _unhandled_input(e: InputEvent) -> void:
	if not visible: return
	# any first press unlocks audio (title music starts), like the web build's first gesture
	if e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton: AudioSys.init()
