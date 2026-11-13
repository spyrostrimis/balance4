class_name MissionHud
extends Control
## The mission parts of the HUD: a bar along the top of the map, a hint box,
## the command buttons, the objective with the hold progress, and the win or
## loss screen. It builds its own controls. It is functional only; the HUD art
## will be redone later.

signal command_pressed(command: StringName)     # &"attack", &"stop" or &"ability"
signal again_pressed
signal title_pressed

const GOLD := Color(0.91, 0.72, 0.29)
const TEXT := Color(0.78, 0.76, 0.68)
const DIM := Color(0.5, 0.52, 0.47)
const PANEL := Color(0.05, 0.05, 0.045, 0.84)
const BAR_BACK := Color(0.16, 0.15, 0.13)
## Width of the map part of the screen, and where the sidebar's contents start.
const MAP_WIDTH := 748.0
const SIDE_X := 759.0
const SIDE_WIDTH := 192.0

var _top_left: Label
var _top_right: Label
var _hint: Label
var _attack: Button
var _stop: Button
var _ability: Button
var _objective: Label
var _status: Label
var _bar: ColorRect
var _forces: Label
var _result: Panel
var _result_title: Label
var _result_text: Label
var _again: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_panel(Rect2(0, 0, MAP_WIDTH, 20))
	_top_left = _label(Rect2(8, 1, 360, 18), 12, GOLD)
	_top_right = _label(Rect2(368, 1, 372, 18), 12, TEXT)
	_top_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_panel(Rect2(8, 486, 520, 46))
	_hint = _label(Rect2(16, 489, 504, 40), 11, TEXT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_attack = _button(Rect2(SIDE_X, 290, 62, 22), "Attack (A)", &"attack")
	_stop = _button(Rect2(SIDE_X + 65, 290, 62, 22), "Stop (S)", &"stop")
	_ability = _button(Rect2(SIDE_X + 130, 290, 62, 22), "", &"ability")

	_label(Rect2(SIDE_X, 318, SIDE_WIDTH, 16), 12, GOLD).text = "Objective"
	_objective = _label(Rect2(SIDE_X, 334, SIDE_WIDTH, 34), 11, TEXT)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = _label(Rect2(SIDE_X, 370, SIDE_WIDTH, 16), 11, GOLD)
	var back := ColorRect.new()
	back.color = BAR_BACK
	back.position = Vector2(SIDE_X, 389)
	back.size = Vector2(SIDE_WIDTH, 8)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_bar = ColorRect.new()
	_bar.position = Vector2(SIDE_X + 1, 390)
	_bar.size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_forces = _label(Rect2(SIDE_X, 399, SIDE_WIDTH, 16), 11, DIM)

	_result = _panel(Rect2((MAP_WIDTH - 360) / 2.0, 170, 360, 180), Color(0.06, 0.06, 0.05, 0.95))
	_result.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_title = _label(Rect2(0, 18, 360, 50), 36, GOLD, _result)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_text = _label(Rect2(20, 72, 320, 50), 12, TEXT, _result)
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_again = Button.new()
	_again.text = "Play again"
	_again.position = Vector2(50, 134)
	_again.size = Vector2(120, 30)
	_again.pressed.connect(func() -> void: again_pressed.emit())
	_result.add_child(_again)
	var to_title := Button.new()
	to_title.text = "Title screen"
	to_title.position = Vector2(190, 134)
	to_title.size = Vector2(120, 30)
	to_title.pressed.connect(func() -> void: title_pressed.emit())
	_result.add_child(to_title)
	_result.visible = false
	visible = false


## Show the HUD for a mission, or hide it if there is none.
func setup(mission: Mission) -> void:
	visible = mission != null
	_result.visible = false
	if mission == null:
		return
	var def := mission.def
	_top_left.text = "Mission %d: %s" % [def.number, def.display_name]
	_objective.text = def.objective
	refresh(mission, "")


## Bring every text and bar up to date. `hint` is the line for the hint box.
func refresh(mission: Mission, hint: String) -> void:
	var def := mission.def
	var players := mission.world.team_size(Mission.PLAYER_TEAM)
	var enemies := mission.world.team_size(Mission.ENEMY_TEAM)
	_top_right.text = "%s %d   %s %d   Time %s" % [def.player_side, players, def.enemy_side, enemies, clock(mission.seconds())]
	_hint.text = hint
	_status.text = hold_text(mission)
	_forces.text = "%s units: %d    %s units: %d" % [def.player_side, players, def.enemy_side, enemies]
	var control := mission.control
	_bar.size.x = roundf((SIDE_WIDTH - 2.0) * (control.progress() if control.owner != ControlPoint.NOBODY else 0.0))
	_bar.color = def.player_color if control.owner == Mission.PLAYER_TEAM else def.enemy_color
	_ability.text = ability_label(mission.player_commander())
	_ability.disabled = not ability_ready(mission.player_commander())


## Show the win or loss screen.
func show_result(mission: Mission) -> void:
	_result_title.text = "VICTORY" if mission.player_won() else "DEFEAT"
	_result_text.text = result_text(mission)
	_result.visible = true
	_again.grab_focus()


func is_result_shown() -> bool:
	return _result.visible


## Seconds as minutes and seconds, e.g. 0:42. Part seconds count as a whole one.
static func clock(seconds: float) -> String:
	var whole := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


## One line saying who holds the control area and for how much longer.
static func hold_text(mission: Mission) -> String:
	var control := mission.control
	if control.owner == ControlPoint.NOBODY:
		return "Contested" if control.contested else "Nobody holds the rock"
	var side := mission.def.player_side if control.owner == Mission.PLAYER_TEAM else mission.def.enemy_side
	if control.contested:
		return "Contested: %s's count waits at %s" % [side, clock(control.seconds_left())]
	return "%s holds the rock: %s to go" % [side, clock(control.seconds_left())]


## The words under VICTORY or DEFEAT.
static func result_text(mission: Mission) -> String:
	var def := mission.def
	var how := ""
	match [mission.player_won(), mission.win_reason]:
		[true, &"hold"]: how = "You held the Orichalcum rock."
		[true, _]: how = "Every enemy is destroyed."
		[false, &"hold"]: how = "%s held the Orichalcum rock." % def.enemy_side
		[false, _]: how = "Your force is destroyed."
	return "%s\nTime %s.  Units lost: %d.  Enemies destroyed: %d." % [
		how, clock(mission.seconds()),
		int(mission.world.losses.get(Mission.PLAYER_TEAM, 0)),
		int(mission.world.losses.get(Mission.ENEMY_TEAM, 0)),
	]


## Text of the ability button: its name and key, or the seconds until it is ready again.
static func ability_label(commander: SimUnit) -> String:
	if commander == null or commander.type.ability == null:
		return "-"
	var ability := commander.type.ability
	if commander.ability_ticks_left > 0:
		return "%s %ds" % [ability.display_name, ceili(commander.ability_ticks_left * SimWorld.TICK_SECONDS)]
	return "%s (Q)" % ability.display_name


static func ability_ready(commander: SimUnit) -> bool:
	return commander != null and commander.type.ability != null and commander.ability_ticks_left == 0


func _panel(rect: Rect2, color := PANEL) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.42, 0.34, 0.2)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel


func _label(rect: Rect2, font_size: int, color: Color, parent: Control = null) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = false
	(parent if parent != null else self).add_child(label)
	return label


func _button(rect: Rect2, text: String, command: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 10)
	var shades := {"normal": Color(0.17, 0.15, 0.12), "hover": Color(0.25, 0.21, 0.15),
			"pressed": Color(0.33, 0.27, 0.17), "disabled": Color(0.1, 0.095, 0.085)}
	for state: String in shades:
		var style := StyleBoxFlat.new()
		style.bg_color = shades[state]
		style.border_color = Color(0.42, 0.34, 0.2)
		style.set_border_width_all(1)
		style.set_content_margin_all(2)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func() -> void: command_pressed.emit(command))
	add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button
