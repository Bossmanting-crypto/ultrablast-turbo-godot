#!/usr/bin/env python3
"""Writes the UI and main scenes (scenes/*.tscn) from compact specs, so layouts stay easy to review in a diff.
Run from the project root:  python3 tools/gen_scenes.py
The generated .tscn files are ordinary Godot scenes: open and tweak them in the editor afterwards if you like
(re-running this script overwrites them)."""
import os

FONT_DISPLAY = 'res://assets/fonts/Bungee-Regular.woff2'
FONT_BOLD = 'res://assets/fonts/ChakraPetch-700.woff2'
FONT_UI = 'res://assets/fonts/ChakraPetch-600.woff2'

GOLD, PEACH, CYAN, MUTED, TEXT, CORAL, NIGHT, LIME = '#ffd27a', '#f4c6a0', '#8fe9ff', '#b9a9c9', '#fff3e4', '#ff5b3d', '#0a0b22', '#dce9a9'


def col(h, a=1.0):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f'Color({r:.4g}, {g:.4g}, {b:.4g}, {a:.4g})'


class Scene:
    def __init__(self):
        self.ext = []      # (type, path)
        self.sub = []      # (id, type, props)
        self.nodes = []    # (name, type, parent, props, extra_header)

    def res(self, typ, path):
        for i, (t, p) in enumerate(self.ext):
            if p == path:
                return f'ExtResource("{i + 1}")'
        self.ext.append((typ, path))
        return f'ExtResource("{len(self.ext)}")'

    def subres(self, typ, props):
        sid = f'{typ}_{len(self.sub) + 1}'
        self.sub.append((sid, typ, props))
        return f'SubResource("{sid}")'

    def node(self, name, typ, parent=None, header='', **props):
        self.nodes.append((name, typ, parent, props, header))
        return (name if parent in (None, '.') else (parent + '/' + name)) if parent is not None else '.'

    def write(self, path):
        out = [f'[gd_scene load_steps={len(self.ext) + len(self.sub) + 1} format=3]', '']
        for i, (t, p) in enumerate(self.ext):
            out.append(f'[ext_resource type="{t}" path="{p}" id="{i + 1}"]')
        if self.ext:
            out.append('')
        for sid, t, props in self.sub:
            out.append(f'[sub_resource type="{t}" id="{sid}"]')
            for k, v in props.items():
                out.append(f'{k} = {v}')
            out.append('')
        for name, typ, parent, props, header in self.nodes:
            h = f'[node name="{name}"'
            if typ:
                h += f' type="{typ}"'
            if parent is not None:
                h += f' parent="{parent}"'
            if header:
                h += ' ' + header
            out.append(h + ']')
            for k, v in props.items():
                out.append(f'{k} = {v}')
            out.append('')
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'w').write('\n'.join(out))
        print('wrote', path)


def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def label(sc, name, parent, text='', font=None, size=None, color=None, align=None, outline=None, shadow=None, uniq=False, autowrap=False, **extra):
    p = dict(layout_mode=2)
    if uniq:
        p['unique_name_in_owner'] = 'true'
    p['text'] = q(text)
    if align is not None:
        p['horizontal_alignment'] = align
    if autowrap:
        p['autowrap_mode'] = 3
    if font:
        p['theme_override_fonts/font'] = sc.res('FontFile', font)
    if size:
        p['theme_override_font_sizes/font_size'] = size
    if color:
        p['theme_override_colors/font_color'] = col(color) if color.startswith('#') else color
    if outline:
        p['theme_override_colors/font_outline_color'] = outline[0]
        p['theme_override_constants/outline_size'] = outline[1]
    if shadow:
        p['theme_override_colors/font_shadow_color'] = shadow[0]
        p['theme_override_constants/shadow_offset_x'] = shadow[1]
        p['theme_override_constants/shadow_offset_y'] = shadow[2]
    p.update(extra)
    return sc.node(name, 'Label', parent, **p)


def anchored(l, t, r, b, ol=0, ot=0, orr=0, ob=0, gh=None, gv=None):
    p = dict(layout_mode=1, anchor_left=l, anchor_top=t, anchor_right=r, anchor_bottom=b,
             offset_left=ol, offset_top=ot, offset_right=orr, offset_bottom=ob)
    if gh is not None:
        p['grow_horizontal'] = gh
    if gv is not None:
        p['grow_vertical'] = gv
    return p


def widget(sc, name, parent, kind, w, h, c1=None, c2=None):
    p = dict(layout_mode=2, unique_name_in_owner='true', custom_minimum_size=f'Vector2({w}, {h})', script=sc.res('Script', 'res://scripts/ui/hud_widget.gd'), kind=kind)
    if c1:
        p['color'] = col(c1)
    if c2:
        p['color2'] = col(c2)
    return sc.node(name, 'Control', parent, **p)


# ============ HUD ============
def hud():
    sc = Scene()
    root = sc.node('Hud', 'Control', None, layout_mode=3, anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
                   mouse_filter=2, script=sc.res('Script', 'res://scripts/ui/hud.gd'))
    deep = col('#4a1236')
    # top left: score
    sc.node('TL', 'VBoxContainer', '.', unique_name_in_owner='true', **anchored(0, 0, 0, 0, 16, 14, 400, 120), mouse_filter=2)
    label(sc, 'Score', 'TL', '0', FONT_DISPLAY, 40, GOLD, uniq=True, shadow=(deep, 3, 3))
    sc.node('Sub', 'HBoxContainer', 'TL', layout_mode=2, theme_override_constants__separation=12)
    label(sc, 'Mult', 'TL/Sub', '×1', FONT_BOLD, 14, CYAN, uniq=True)
    label(sc, 'Weapon', 'TL/Sub', '', FONT_BOLD, 14, CYAN, uniq=True)
    # top centre: timer, phase, iris, banner
    sc.node('TC', 'VBoxContainer', '.', unique_name_in_owner='true', **anchored(0.5, 0, 0.5, 0, -260, 12, 260, 140, gh=2), mouse_filter=2, theme_override_constants__separation=2)
    label(sc, 'Timer', 'TC', '3:00', FONT_DISPLAY, 28, TEXT, align=1, uniq=True, shadow=(col('#8fe9ff', 0.4), 0, 0))
    label(sc, 'WorldLbl', 'TC', 'IGNITION', FONT_BOLD, 12, MUTED, align=1, uniq=True)
    sc.node('IrisRow', 'HBoxContainer', 'TC', layout_mode=2, alignment=1, theme_override_constants__separation=8)
    widget(sc, 'Iris', 'TC/IrisRow', 5, 26, 26)
    label(sc, 'IrisTxt', 'TC/IrisRow', '', FONT_BOLD, 11, '#c9a8ff', uniq=True, custom_minimum_size='Vector2(80, 0)')
    label(sc, 'Banner', 'TC', '', FONT_DISPLAY, 17, CORAL, align=1, uniq=True, outline=(col('#ff5032', 0.35), 6))
    # top right: style rank + turbo
    sc.node('TR', 'VBoxContainer', '.', unique_name_in_owner='true', **anchored(1, 0, 1, 0, -320, 12, -16, 150, gh=0), mouse_filter=2, theme_override_constants__separation=5)
    sc.node('StyleBox', 'VBoxContainer', 'TR', layout_mode=2, unique_name_in_owner='true', theme_override_constants__separation=5)
    sc.node('RankRow', 'HBoxContainer', 'TR/StyleBox', layout_mode=2, alignment=2, theme_override_constants__separation=10)
    label(sc, 'RankN', 'TR/StyleBox/RankRow', 'DRIFT', FONT_BOLD, 12, MUTED, uniq=True, vertical_alignment=2, size_flags_vertical=8)
    label(sc, 'RankL', 'TR/StyleBox/RankRow', 'D', FONT_DISPLAY, 50, MUTED, uniq=True, shadow=(col('#2a0a22'), 3, 3))
    sc.node('BarRow', 'HBoxContainer', 'TR/StyleBox', layout_mode=2, alignment=2)
    widget(sc, 'RankBar', 'TR/StyleBox/BarRow', 6, 170, 4, MUTED, MUTED)
    sc.node('TurboRow', 'HBoxContainer', 'TR/StyleBox', layout_mode=2, unique_name_in_owner='true', alignment=2, theme_override_constants__separation=8)
    label(sc, 'TLabel', 'TR/StyleBox/TurboRow', 'TURBO', FONT_BOLD, 11, MUTED)
    widget(sc, 'Cells', 'TR/StyleBox/TurboRow', 1, 105, 11)
    label(sc, 'TurboState', 'TR/StyleBox', 'LOCKED · REACH RANK B', FONT_BOLD, 11, MUTED, align=2, uniq=True)
    # bottom left: hull
    sc.node('BL', 'VBoxContainer', '.', unique_name_in_owner='true', **anchored(0, 1, 0, 1, 16, -60, 300, -14, gv=0), mouse_filter=2, alignment=2)
    sc.node('HullRow', 'HBoxContainer', 'BL', layout_mode=2, theme_override_constants__separation=8)
    label(sc, 'HullLbl', 'BL/HullRow', 'HULL', FONT_BOLD, 11, MUTED, custom_minimum_size='Vector2(44, 0)')
    widget(sc, 'Hull', 'BL/HullRow', 0, 220, 8, LIME, GOLD)
    sc.node('FuelRow', 'HBoxContainer', 'BL', layout_mode=2, theme_override_constants__separation=8)
    label(sc, 'FuelLbl', 'BL/FuelRow', 'FUEL', FONT_BOLD, 11, MUTED, uniq=True, custom_minimum_size='Vector2(44, 0)')
    widget(sc, 'Fuel', 'BL/FuelRow', 0, 220, 8, '#4fd2ff', '#8fe9ff')
    # bottom centre: thruster widget + prompt
    sc.node('Thruster', 'VBoxContainer', '.', unique_name_in_owner='true', **anchored(0.5, 1, 0.5, 1, -300, -100, 300, -14, gh=2, gv=0), mouse_filter=2, alignment=2, theme_override_constants__separation=6)
    sc.node('ThrRow', 'HBoxContainer', 'Thruster', layout_mode=2, alignment=1, theme_override_constants__separation=16)
    widget(sc, 'HomeChip', 'Thruster/ThrRow', 4, 46, 46)
    widget(sc, 'Pips', 'Thruster/ThrRow', 2, 112, 46)
    widget(sc, 'BoomChip', 'Thruster/ThrRow', 3, 46, 46)
    label(sc, 'Prompt', 'Thruster', '', FONT_BOLD, 12, PEACH, align=1, uniq=True, outline=(col('#000000', 0.8), 6))
    # bottom right: speed + boost gauge
    sc.node('BR', 'VBoxContainer', '.', **anchored(1, 1, 1, 1, -260, -96, -16, -14, gh=0, gv=0), mouse_filter=2, alignment=2, theme_override_constants__separation=2)
    label(sc, 'Speed', 'BR', '0', FONT_DISPLAY, 40, TEXT, align=2, uniq=True, shadow=(deep, 3, 3))
    label(sc, 'SpdL', 'BR', 'KNOTS · BOOST', FONT_BOLD, 11, MUTED, align=2)
    sc.node('GaugeRow', 'HBoxContainer', 'BR', layout_mode=2, alignment=2)
    widget(sc, 'Gauge', 'BR/GaugeRow', 7, 190, 7)
    # coach card
    sc.node('Coach', 'PanelContainer', '.', unique_name_in_owner='true', layout_mode=1, offset_left=16, offset_top=150, offset_right=346, offset_bottom=360, mouse_filter=2,
            script=sc.res('Script', 'res://scripts/ui/coach_panel.gd'))
    sc.node('V', 'VBoxContainer', 'Coach', layout_mode=2, theme_override_constants__separation=8, mouse_filter=2)
    sc.node('Top', 'HBoxContainer', 'Coach/V', layout_mode=2)
    label(sc, 'Step', 'Coach/V/Top', '', FONT_BOLD, 11, CYAN, uniq=True, size_flags_horizontal=3)
    sc.node('Skip', 'Button', 'Coach/V/Top', layout_mode=2, unique_name_in_owner='true', theme_type_variation='&"GhostButton"', text=q('SKIP ›  [TAB]'), theme_override_font_sizes__font_size=11, visible='false')
    sc.node('Dots', 'Control', 'Coach/V', layout_mode=2, unique_name_in_owner='true', custom_minimum_size='Vector2(0, 3)', mouse_filter=2)
    label(sc, 'Title', 'Coach/V', '', FONT_DISPLAY, 20, GOLD, uniq=True)
    sc.node('Keys', 'HFlowContainer', 'Coach/V', layout_mode=2, unique_name_in_owner='true', theme_override_constants__h_separation=6, theme_override_constants__v_separation=6, mouse_filter=2)
    sc.node('Body', 'RichTextLabel', 'Coach/V', layout_mode=2, unique_name_in_owner='true', bbcode_enabled='true', fit_content='true', scroll_active='false', mouse_filter=2,
            theme_override_font_sizes__normal_font_size=15, theme_override_font_sizes__bold_font_size=15)
    label(sc, 'Count', 'Coach/V', '', FONT_BOLD, 12, CYAN, uniq=True)
    sc.node('Prog', 'Control', 'Coach/V', layout_mode=2, unique_name_in_owner='true', custom_minimum_size='Vector2(0, 5)', mouse_filter=2)
    sc.node('Next', 'Button', 'Coach/V', layout_mode=2, unique_name_in_owner='true', text=q('CONTINUE  [ENTER]'), theme_override_fonts__font=sc.res('FontFile', FONT_BOLD), theme_override_font_sizes__font_size=13, visible='false')
    # recorder badge + note box
    label(sc, 'RecBadge', '.', '●  REC   T = NOTE', FONT_BOLD, 10, '#ff7a7a', uniq=True, **anchored(0, 1, 0, 1, 16, -64, 220, -46, gv=0), visible='false')
    sc.node('RecNote', 'PanelContainer', '.', unique_name_in_owner='true', **anchored(0.5, 0.38, 0.5, 0.38, -260, -50, 260, 50, gh=2, gv=2), visible='false')
    sc.node('V', 'VBoxContainer', 'RecNote', layout_mode=2, theme_override_constants__separation=8)
    label(sc, 'NoteLbl', 'RecNote/V', 'PLAYTEST NOTE', FONT_BOLD, 11, CYAN)
    sc.node('RecNoteIn', 'LineEdit', 'RecNote/V', layout_mode=2, unique_name_in_owner='true', placeholder_text=q('What felt off or great? Enter saves, Esc cancels'), max_length=500)
    fix_overrides(sc)
    sc.write('scenes/ui/hud.tscn')


def fix_overrides(sc):
    """theme_override_x__y keyword args stand for theme_override_x/y."""
    for i, (name, typ, parent, props, header) in enumerate(sc.nodes):
        np = {}
        for k, v in props.items():
            if k.startswith('theme_override_') and '__' in k:
                a, b = k.split('__', 1)
                k = a + '/' + b
            np[k] = v
        sc.nodes[i] = (name, typ, parent, np, header)


# ============ screens ============
def screen_base(sc, name, script, dim=0.8):
    sc.node(name, 'Control', None, layout_mode=3, anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
            script=sc.res('Script', script))
    sc.node('Backdrop', 'ColorRect', '.', layout_mode=1, anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
            color=col(NIGHT, dim), mouse_filter=2)
    sc.node('Scroll', 'ScrollContainer', '.', layout_mode=1, anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
            horizontal_scroll_mode=0)
    sc.node('Center', 'CenterContainer', 'Scroll', layout_mode=2, size_flags_horizontal=3, size_flags_vertical=3)
    sc.node('Card', 'VBoxContainer', 'Scroll/Center', layout_mode=2, custom_minimum_size='Vector2(760, 0)', alignment=1, theme_override_constants__separation=16)
    return 'Scroll/Center/Card'


def h2(sc, parent, name, text, uniq=False):
    return label(sc, name, parent, text, FONT_DISPLAY, 54, GOLD, align=1, uniq=uniq, shadow=(col('#5a1236'), 3, 3))


def row(sc, parent, name, sep=14):
    return sc.node(name, 'HBoxContainer', parent, layout_mode=2, alignment=1, theme_override_constants__separation=sep)


def button(sc, parent, name, text, ghost=False, **kw):
    p = dict(layout_mode=2, unique_name_in_owner='true', text=q(text))
    if ghost:
        p['theme_type_variation'] = '&"GhostButton"'
    p.update(kw)
    return sc.node(name, 'Button', parent, **p)


def check(sc, parent, name, text):
    return sc.node(name, 'CheckBox', parent, layout_mode=2, unique_name_in_owner='true', text=q(text))


def title_screen():
    sc = Scene()
    card = screen_base(sc, 'Title', 'res://scripts/ui/title_screen.gd', 0.55)
    sc.node('LogoBox', 'VBoxContainer', card, layout_mode=2, theme_override_constants__separation=-34)
    label(sc, 'Logo', card + '/LogoBox', 'ULTRABLAST', FONT_DISPLAY, 104, '#ffd067', align=1, outline=(col('#7a1f3a'), 14), shadow=(col('#3d0b28'), 0, 8))
    label(sc, 'LogoSub', card + '/LogoBox', 'T U R B O', FONT_DISPLAY, 40, '#ff9a4a', align=1, outline=(col('#5a1236'), 10))
    label(sc, 'Tag', card, 'Lock on and crunch through crystals, rifts and enemy jets in one line of momentum, while the Iris closes the sky around you.',
          FONT_UI, 15, PEACH, align=1, autowrap=True, custom_minimum_size='Vector2(620, 0)')
    sc.node('Controls', 'GridContainer', card, layout_mode=2, unique_name_in_owner='true', columns=2, theme_override_constants__h_separation=12, theme_override_constants__v_separation=8)
    label(sc, 'Loop', card, 'New here? FLIGHT SCHOOL teaches one move per step. Pass it, then continue when you are ready.', FONT_UI, 13, MUTED, align=1, autowrap=True)
    row(sc, card, 'Btns')
    button(sc, card + '/Btns', 'StartBtn', 'LAUNCH')
    button(sc, card + '/Btns', 'TutBtn', 'FLIGHT SCHOOL', ghost=True)
    row(sc, card, 'Checks', 18)
    for n, t in [('InvY', 'INVERT Y'), ('MuteChk', 'MUTE'), ('RumbleChk', 'RUMBLE'), ('RecChk', 'PLAYTEST REC')]:
        check(sc, card + '/Checks', n, t)
    label(sc, 'PadNote', card, '', FONT_UI, 12, MUTED, align=1, uniq=True, visible='false')
    row(sc, card, 'RecRow', 8)
    button(sc, card + '/RecRow', 'RecExport', 'EXPORT PLAYTESTS', ghost=True, theme_override_font_sizes__font_size=11)
    button(sc, card + '/RecRow', 'RecOpen', 'OPEN FOLDER', ghost=True, theme_override_font_sizes__font_size=11)
    button(sc, card + '/RecRow', 'RecClear', 'CLEAR', ghost=True, theme_override_font_sizes__font_size=11)
    label(sc, 'RecLine', card, '', FONT_UI, 12, MUTED, align=1, uniq=True)
    label(sc, 'BestLine', card, '', FONT_DISPLAY, 15, CYAN, align=1, uniq=True)
    label(sc, 'VerLine', card, '', FONT_UI, 11, MUTED, align=1, uniq=True, modulate='Color(1, 1, 1, 0.7)')
    fix_overrides(sc)
    sc.write('scenes/ui/title_screen.tscn')


def pause_screen():
    sc = Scene()
    card = screen_base(sc, 'Pause', 'res://scripts/ui/pause_screen.gd', 0.72)
    h2(sc, card, 'H', 'PAUSED')
    sc.node('Vol', 'GridContainer', card, layout_mode=2, columns=2, size_flags_horizontal=4, theme_override_constants__h_separation=14, theme_override_constants__v_separation=10)
    label(sc, 'ML', card + '/Vol', 'MUSIC', FONT_BOLD, 12, PEACH)
    sc.node('VolMusic', 'HSlider', card + '/Vol', layout_mode=2, unique_name_in_owner='true', custom_minimum_size='Vector2(240, 20)', max_value=100.0, value=70.0)
    label(sc, 'SL', card + '/Vol', 'EFFECTS', FONT_BOLD, 12, PEACH)
    sc.node('VolSfx', 'HSlider', card + '/Vol', layout_mode=2, unique_name_in_owner='true', custom_minimum_size='Vector2(240, 20)', max_value=100.0, value=90.0)
    row(sc, card, 'MuteRow')
    check(sc, card + '/MuteRow', 'MuteChk2', 'MUTE ALL (M)')
    label(sc, 'Note', card, 'Playtest note: press T while playing', FONT_UI, 12, MUTED, align=1)
    row(sc, card, 'Btns')
    button(sc, card + '/Btns', 'ResumeBtn', 'RESUME')
    button(sc, card + '/Btns', 'QuitBtn', 'QUIT TO TITLE', ghost=True)
    label(sc, 'Credits', card, ('Sound designed from CC0 recordings: Warfork weapon and world sounds, Kenney sci-fi and impact packs, Ben Burnes micro packs '
          '(Organic Wooshes, Electromagnetic Sounds, Fans and Drones), breaking, bang and household SFX packs collected by lavenderdotpet. Music "Battle Theme A" '
          'by cynicmusic (CC0). Models (CC BY 4.0, Sketchfab): "Glowing Gem" by RiZoRuS77, "Red Gem" by bang_m, "Magic Crystal IX" by -X-ScornGames.'),
          FONT_UI, 11, MUTED, align=1, autowrap=True, custom_minimum_size='Vector2(620, 0)')
    fix_overrides(sc)
    sc.write('scenes/ui/pause_screen.tscn')


def over_screen():
    sc = Scene()
    card = screen_base(sc, 'Over', 'res://scripts/ui/over_screen.gd', 0.8)
    h2(sc, card, 'OverTitle', 'WORLD COLLAPSE', uniq=True)
    sc.node('Stats', 'GridContainer', card, layout_mode=2, columns=3, theme_override_constants__h_separation=14, theme_override_constants__v_separation=14)
    for n, t in [('SScore', 'SCORE'), ('SBest', 'BEST'), ('SChain', 'BEST SUPERCUT'), ('SLevel', 'TOP RANK'), ('SCrystals', 'CRYSTALS'), ('SKills', 'TAKEDOWNS'), ('SRifts', 'RIFTS OPENED')]:
        sc.node(n + 'Box', 'PanelContainer', card + '/Stats', layout_mode=2, custom_minimum_size='Vector2(240, 0)')
        sc.node('V', 'VBoxContainer', card + '/Stats/' + n + 'Box', layout_mode=2, alignment=1)
        label(sc, n, card + '/Stats/' + n + 'Box/V', '0', FONT_DISPLAY, 28, GOLD, align=1, uniq=True)
        label(sc, 'L', card + '/Stats/' + n + 'Box/V', t, FONT_BOLD, 11, MUTED, align=1)
    row(sc, card, 'RecRow', 8)
    label(sc, 'RecSaved', card + '/RecRow', 'Playtest session saved.', FONT_UI, 12, MUTED, uniq=True)
    button(sc, card + '/RecRow', 'RecCopy', 'EXPORT PLAYTESTS', ghost=True, theme_override_font_sizes__font_size=11)
    row(sc, card, 'Btns')
    button(sc, card + '/Btns', 'AgainBtn', 'FLY AGAIN')
    button(sc, card + '/Btns', 'TitleBtn', 'TITLE', ghost=True)
    fix_overrides(sc)
    sc.write('scenes/ui/over_screen.tscn')


def tutdone_screen():
    sc = Scene()
    card = screen_base(sc, 'TutDone', 'res://scripts/ui/tutdone_screen.gd', 0.8)
    h2(sc, card, 'H', 'FLIGHT SCHOOL COMPLETE')
    sc.node('Sum', 'GridContainer', card, layout_mode=2, columns=2, size_flags_horizontal=4, theme_override_constants__h_separation=14, theme_override_constants__v_separation=8)
    rows = [('HOMING', 'Gold ring = lock. Each dash costs a charge. Chain when the closing ring turns gold (perfect = free); five links = finisher.'),
            ('RIFTS', 'Three charge crystals open a tunnel where you look. Chain them fast for gold.'),
            ('BOOST', 'Hold to thrust and charge 3 rings, let go and fly through them. Homing while charging = bundle boom.'),
            ('PUZZLES', 'Home into a cache or an exposed orb to prime it. Hold boost to start its miniblast, solve it, let go to fire.'),
            ('TURBO', 'Rank B and a full cell. Hold past 3 rings, align, release on the cue, then chain the supercut.'),
            ('TURRETS', 'In a run: a red laser sight means a turret is aiming, white means locked. Turn, or home in and knock it out.'),
            ('THE IRIS', 'The glass shell closes in stages. Watch the glyphs etch, then stay inside.')]
    for i, (k, v) in enumerate(rows):
        label(sc, f'K{i}', card + '/Sum', k, FONT_DISPLAY, 13, GOLD)
        label(sc, f'V{i}', card + '/Sum', v, FONT_UI, 14, TEXT, autowrap=True, custom_minimum_size='Vector2(480, 0)')
    row(sc, card, 'Btns')
    button(sc, card + '/Btns', 'TutPlayBtn', 'START A RUN')
    button(sc, card + '/Btns', 'TutTitleBtn', 'TITLE', ghost=True)
    fix_overrides(sc)
    sc.write('scenes/ui/tutdone_screen.tscn')


# ============ main ============
def main():
    sc = Scene()
    env = sc.subres('Environment', {
        'background_mode': 1, 'background_color': col(NIGHT),
        'ambient_light_source': 2, 'ambient_light_color': col('#a9c2ff'), 'ambient_light_energy': 0.75,
        'tonemap_mode': 3, 'tonemap_exposure': 0.92,
        'glow_enabled': 'true', 'glow_normalized': 'false', 'glow_intensity': 0.72, 'glow_strength': 1.0, 'glow_bloom': 0.0,
        'glow_blend_mode': 0, 'glow_hdr_threshold': 0.9, 'glow_hdr_scale': 1.0,
        'glow_levels/1': 0.4, 'glow_levels/2': 0.7, 'glow_levels/3': 0.8, 'glow_levels/4': 0.4, 'glow_levels/5': 0.0,
    })
    sky_mat = sc.subres('ShaderMaterial', {'render_priority': -100, 'shader': sc.res('Shader', 'res://shaders/sky.gdshader'),
                                           'shader_parameter/map': sc.res('Texture2D', 'res://assets/textures/sky.webp'),
                                           'shader_parameter/uBright': 0.95})
    sky_mesh = sc.subres('SphereMesh', {'radius': 1500.0, 'height': 3000.0, 'radial_segments': 64, 'rings': 32})
    lens_mat = sc.subres('ShaderMaterial', {'shader': sc.res('Shader', 'res://shaders/lens_post.gdshader')})
    add_mat = sc.subres('CanvasItemMaterial', {'blend_mode': 1})
    sc.node('Main', 'Node', None, script=sc.res('Script', 'res://scripts/ui/main.gd'))
    sc.node('Env', 'WorldEnvironment', '.', unique_name_in_owner='true', environment=env)
    sc.node('Sun', 'DirectionalLight3D', '.', unique_name_in_owner='true', light_color=col('#ffdcb0'), light_energy=1.6, shadow_enabled='false')
    sc.node('Camera', 'Camera3D', '.', unique_name_in_owner='true', transform='Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 22, -10)', fov=72.0, near=0.1, far=3200.0, current='true')
    sc.node('Sky', 'MeshInstance3D', '.', unique_name_in_owner='true', mesh=sky_mesh, material_override=sky_mat, cast_shadow=0, extra_cull_margin=16384.0)
    sc.node('World', 'Node3D', '.', unique_name_in_owner='true')
    sc.node('PostLayer', 'CanvasLayer', '.', layer=1)
    sc.node('Lens', 'ColorRect', 'PostLayer', unique_name_in_owner='true', material=lens_mat, anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2, mouse_filter=2)
    sc.node('DoodleLayer', 'CanvasLayer', '.', layer=2)
    sc.node('Doodle', 'TextureRect', 'DoodleLayer', unique_name_in_owner='true', material=add_mat, modulate='Color(1, 1, 1, 0)',
            anchors_preset=15, anchor_left=-0.06, anchor_top=-0.06, anchor_right=1.06, anchor_bottom=1.06, grow_horizontal=2, grow_vertical=2, mouse_filter=2,
            texture=sc.res('Texture2D', 'res://assets/textures/doodles.webp'), expand_mode=1, stretch_mode=6)
    sc.node('FxLayer', 'CanvasLayer', '.', layer=3)
    ov = sc.res('Script', 'res://scripts/ui/overlay.gd')
    sc.node('Overlay0', 'Control', 'FxLayer', unique_name_in_owner='true', anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, mouse_filter=2, script=ov, layer=0)
    sc.node('Overlay1', 'Control', 'FxLayer', unique_name_in_owner='true', material=add_mat, anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, mouse_filter=2, script=ov, layer=1)
    sc.node('Overlay2', 'Control', 'FxLayer', unique_name_in_owner='true', anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0, mouse_filter=2, script=ov, layer=2)
    sc.node('HudLayer', 'CanvasLayer', '.', layer=4)
    sc.node('Hud', None, 'HudLayer', header=f'unique_name_in_owner=true instance={sc.res("PackedScene", "res://scenes/ui/hud.tscn")}')
    sc.node('ScreenLayer', 'CanvasLayer', '.', layer=10)
    for n, f in [('Title', 'title_screen'), ('Pause', 'pause_screen'), ('Over', 'over_screen'), ('Tutdone', 'tutdone_screen')]:
        sc.node(n, None, 'ScreenLayer', header=f'unique_name_in_owner=true instance={sc.res("PackedScene", f"res://scenes/ui/{f}.tscn")}')
    # instanced nodes take unique_name via property lines
    nodes = []
    for (name, typ, parent, props, header) in sc.nodes:
        if 'instance=' in header and 'unique_name_in_owner=true' in header:
            header = header.replace('unique_name_in_owner=true ', '')
            props = dict(props, unique_name_in_owner='true')
        nodes.append((name, typ, parent, props, header))
    sc.nodes = nodes
    sc.write('scenes/main.tscn')


if __name__ == '__main__':
    hud(); title_screen(); pause_screen(); over_screen(); tutdone_screen(); main()
