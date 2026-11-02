extends ScreenBase
## Game over: run stats, recorder export, fly again / title.

func _ready() -> void:
	%AgainBtn.pressed.connect(func(): AudioSys.ui("select"); GAME.start_game())
	%TitleBtn.pressed.connect(func(): AudioSys.ui("back"); GAME.to_title())
	%RecCopy.pressed.connect(func():
		var p := REC.export_all()
		%RecSaved.text = ("Exported to %s" % p) if p != "" else "Nothing to export")
	wire_sounds()

func fill(why: String, score: int, best: int, chain: int, rank: String, crystals: int, kills: int, rifts: int, saved: bool) -> void:
	%OverTitle.text = "APERTURE SEALED" if why == "TIME" else "HULL BREACHED"
	%SScore.text = Hud._commas(score); %SBest.text = Hud._commas(best)
	%SChain.text = ("%d HITS" % chain) if chain else "—"; %SLevel.text = rank; %SRifts.text = str(rifts)
	%SCrystals.text = str(crystals); %SKills.text = str(kills)
	%RecSaved.text = "Playtest session saved."
	%RecSaved.visible = saved; %RecCopy.visible = saved
