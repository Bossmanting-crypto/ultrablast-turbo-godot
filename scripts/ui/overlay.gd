extends Control
## A full-screen drawing layer for the 2D overlay (the web build's #fx canvas). Layer 0 draws the in-world
## marks (reticle, brackets, threats, puzzles), layer 1 the additive crash doodles, layer 2 event text and popups.
@export var layer := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if GAME.booted: FX.draw_layer(self, layer)
