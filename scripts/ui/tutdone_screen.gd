extends ScreenBase
## Flight School complete: the summary card, then a run or the title.

func _ready() -> void:
	%TutPlayBtn.pressed.connect(func(): AudioSys.ui("select"); GAME.start_game())
	%TutTitleBtn.pressed.connect(func(): AudioSys.ui("back"); GAME.to_title())
	wire_sounds()
