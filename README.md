# ULTRABLAST TURBO (Godot 4.5)

This is a Godot 4.5 port of the PC web build (pc-v4.2, [Ultrablast-turbo-pc](https://github.com/Bossmanting-crypto/Ultrablast-turbo-pc)), written in GDScript with the Forward+ renderer. The title screen shows **BUILD GODOT-1**, and every playtest export records it too.

## Run it

1. Install [Godot 4.5](https://godotengine.org/download) (the standard build; the .NET build isn't needed).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
3. Press **F5**.

The first import takes a minute because Godot converts the audio, models and textures.

## Controls

| | Keyboard / mouse | Xbox pad |
|---|---|---|
| Steer | Mouse or WASD / arrows | Left stick |
| Homing dash | E (or F, Q, J, K, Shift), right mouse button | X (or B, Y, RB, LT) |
| Boost: hold to thrust and charge, let go to blast | Space, left mouse button | A or RT |
| Puzzle inputs | WASD / arrows | D-pad |
| Pause | Esc / P | Start |
| Continue in Flight School / skip | Enter / Tab | View |
| Playtest note | T | |

You can rebind everything under **Project → Project Settings → Input Map**. Menus use Godot's focus navigation, so the stick, D-pad, A and B all work there.

## Flight feel

These features are new in the Godot build:

- **Ace Combat throttle.** Holding boost thrusts. When you let go, the jet settles back to cruise over a couple of seconds, and the flame shrinks and dims as it does.
- **Gravity you can feel.** Every body pulls on you, and the mini-planets pull hardest. Outside a planet's field, its pull bends your heading toward it, so you can slingshot around it. Holding the throttle or boosting resists the pull.
- **Climbing and diving.** Climbing away from the core, or from a mini-planet you're near, costs speed. Diving toward it gains speed.
- **Slow means heavy.** Below cruise speed the jet sinks a little and the nose drops until you open the throttle again.
- **Thruster colours.** Blue at cruise, cyan while thrusting, gold on a blast, white while homing, magenta in turbo.
- **The exhaust.** The look follows Louis du Mont's realtime thruster FX for Blender. Each nozzle has three nested cones: a filament sheath, a dense jet and a thin needle. Shock rings ride down the plume, sparks peel off it, and a pearlescent thin-film sheen runs through it all. There's also a heat haze behind the nozzles and vapour trails off the wingtips. A single throttle value drives brightness, reach, ring rate and sparks, like the reference's one slider.

## Layout

```
project.godot          autoload list, input map, render settings, global shader uniform uTime
scenes/main.tscn       WorldEnvironment (ACES, glow = bloom), camera, sky sphere, 3D root,
                       post layer (lens), doodle layer, FX overlays, HUD, screens
scenes/ui/             hud, title, pause, game over and Flight School summary screens, theme.tres
scripts/core/          util (U), ctl (input + rumble), audio (AudioSys), rec (playtest recorder REC),
                       meshes (three.js-style geometry), catmull_curve (rift tunnel paths)
scripts/game/          world, ship (P), jet, wing_trail, fx, enemies, threats, style (ST), homing (HOM),
                       blast (BL: charge, puzzles, turbo, supercut), tutorial (TUT), game (GAME: loop + screens)
scripts/ui/            hud, coach card, menu screens, 2D overlay drawing
shaders/               one .gdshader per material (see below); include/ has the shared noise and varyings
assets/                models (glb), sfx (mp3; loops as ogg), music, textures (sky, doodles, glyph rings), fonts
tools/                 autotest.gd, gen_scenes.py, setup_input.gd, setup_audio_buses.gd, gen_glyph_textures.mjs
```

The autoload names match the web build's globals (`P`, `ST`, `HOM`, `BL`, `TUT`, `GAME`, `REC`). That way each system reads like its JavaScript original, which makes porting future changes straightforward.

## Shaders

| File | What it draws |
|---|---|
| `sky` | Equirect panorama with rotation, tint, brightness and saturation |
| `lens_post` | Speed blur, chromatic split, barrel warp, grade, flash, vignette, plus the engine heat haze |
| `core_shell`, `core_inner`, `fence_shell` | The world core: glass shell with dissolve and defense plates, glyph heart, electric fence |
| `orb_body`, `rail_zone` | Mini-planets: toon hull with alarm and hit flash, grind-rail zone |
| `barrier` | The glass shell: hex cells, proximity glow, impact ripples, Iris countdown etch |
| `tunnel` | Rift tunnel walls: flowing lanes, bands, opening reveal, gold variant |
| `crystal` | Faceted instanced jewels (crystals, gems, homing gems) |
| `thruster` | Pearlescent exhaust: sheath, jet and needle layers |
| `wing_trail` | Wingtip vapour ribbons |
| `particles`, `shockwave`, `wave`, `halo`, `glow_add`, `bubble`, `text_gradient` | FX particles, shock shells, superblast wave, crystal halos, additive glows, turbo bubble, event-text fill |

## Testing

`tools/autotest.gd` runs scripted playthroughs and saves screenshots:

```
godot --path . -- --test --scenario=run --shots=/tmp/shots --frames=600
```

The scenarios are `title`, `run`, `tutorial`, `puzzle`, `supercut`, `turrets`, `thrusters` (throttle, gravity and slow-sink measurements) and `fxlab` (the exhaust on a grey bench in every thruster state). Without a display, run it under `xvfb-run`.

## Credits

The credits are the same as the web build and are listed on the pause screen:

- **Sound:** designed from CC0 recordings: Warfork weapon and world sounds, Kenney sci-fi and impact packs, Ben Burnes micro packs (Organic Wooshes, Electromagnetic Sounds, Fans and Drones), and the breaking, bang and household SFX packs collected by lavenderdotpet.
- **Music:** "Battle Theme A" by cynicmusic (CC0).
- **Models (CC BY 4.0, Sketchfab):** "Glowing Gem" by RiZoRuS77, "Red Gem" by bang_m, "Magic Crystal IX" by -X-ScornGames.
- **Fonts:** Bungee and Chakra Petch (SIL OFL).
