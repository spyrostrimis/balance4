class_name MissionHud
extends Control
## The HUD, after the approved mockup (v12 D): a top bar across the whole
## screen (Objectives and Menu, the mission's name, the Orichalcum, the power
## and the time), the heroes' portraits down the left of the map, a message
## box at the bottom left of the map for what the mission's characters say
## and for hints, the objectives list under the Objectives button, and the
## sidebar: the minimap (a node of MapView), the build menu (BuildPanel) or,
## in a mission without a base, the objective box and the controls, a card
## about what is selected or under the mouse, and the command buttons. Also
## the pause menu and the win or loss screen. It builds its own controls; the
## pictures are made by tools/make_hud.py and the fonts and styles come from
## HudStyle.

signal command_pressed(command: StringName)     # &"attack", &"stop", &"repair" or &"ability_<key>"
signal again_pressed
signal title_pressed
signal resume_pressed
## The Menu button: MapView pauses.
signal menu_pressed
## A hero's portrait was clicked; `twice` for a double click.
signal hero_pressed(unit_id: int, twice: bool)
## Next mission, on the debriefing of a won mission that has one.
signal next_pressed

const TOP := HudStyle.TOP
const MAP_WIDTH := HudStyle.SIDEBAR_X
const SIDE_X := HudStyle.SIDE_X
const SIDE_WIDTH := HudStyle.SIDE_WIDTH
## The top bar's three boxes, as drawn in hud_frame.png.
const CAPS := [Rect2(508, 5, 162, 18), Rect2(678, 5, 134, 18), Rect2(820, 5, 132, 18)]
const PLAQUE := Rect2(226, 4, 268, 20)
## The heroes' portraits: the first one's frame, and how far apart they are.
const HERO_AT := Vector2(10, TOP + 22)
const HERO_SIZE := Vector2(48, 58)
const HERO_STEP := 76.0
const MESSAGE_BOX := Rect2(10, 466, 460, 66)
const DEBRIEFING := Rect2(146, 92, 460, 356)
const CARD := Rect2(SIDE_X, 406, SIDE_WIDTH, 80)
const COMMANDS_Y := 492.0
const COMMANDS_HEIGHT := 40.0
const CONTROLS_HELP := "Left click or drag: select (Shift adds)\nRight click: move, or attack an enemy\nHarvester: right-click rock or refinery\nF, then click: attack-move.  X: stop\nQ or E, then click: hero ability\nCtrl+1..9 stores a group, 1..9 selects\nWASD, arrows, edges: scroll\nO: objectives.  Esc or P: pause"

var _top_left: Label                     # the mission's name, on the plaque
var _cap_icons: Array[TextureRect] = []
var _cap_names: Array[Label] = []
var _cap_values: Array[Label] = []
var _objectives_button: Button
var _menu_button: Button

var _attack: Button
var _stop: Button
## The ability buttons, one per key of the player's heroes' abilities: key -> Button.
var _ability_buttons := {}
## Repair, in place of Attack and Stop while a building is selected.
var _repair: Button

## The objective box (in a mission without a base) and the list of controls under it.
var _objective_panel: Panel
var _objective: Label
var _status: Label
var _bar: HudStyle.Bar
var _forces: Label
var _help: Label

## The card about what is selected or under the mouse.
var _card: Panel
var _card_frame: Panel
var _card_picture: TextureRect
var _card_title: Label
var _card_sub: Label
var _card_health: HudStyle.Bar
var _card_details: Label

## The message box.
var _message_panel: Panel
var _speaker_frame: Panel
var _speaker_picture: TextureRect
var _speaker: Label
var _message_time: Label
var _message_text: Label

## The objectives list, opened with the Objectives button or O.
var _objectives_panel: Panel
var _objective_rows: Array[Control] = []
var _objectives_key := ""

## The heroes' portraits: one dictionary per hero (id, button, frame, bar, key, wait).
var _heroes: Array[Dictionary] = []
var _hero_layer: Control

var _result: Panel
var _result_title: Label
var _result_paper: Panel
var _result_story: Label
var _result_text: Label
var _result_rows: Array[Control] = []
var _again: Button
var _next: Button
var _to_title: Button
var _settings: SettingsPanel
var _pause: Panel
var _resume: Button
## The build menu, shown in missions with a base.
var build_panel: BuildPanel
var _mission: Mission
var _last_hero_click := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_top_bar()
	_hero_layer = Control.new()
	_hero_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_layer)
	_build_message_box()
	_build_objective_box()
	build_panel = BuildPanel.new()
	build_panel.position = Vector2(SIDE_X, 188)
	add_child(build_panel)
	build_panel.visible = false
	_build_card()
	_attack = _command_button("Attack", "swords", &"attack", "Attack-move (F): then click where to go, or what to attack")
	_stop = _command_button("Stop", "stop", &"stop", "Stop (X)")
	_repair = _command_button("Repair", "hammer", &"repair", "Repair the building (R), paid in Orichalcum")
	_repair.visible = false
	_build_objectives_list()
	_build_pause()
	_build_result()


func _build_top_bar() -> void:
	# The top bar and the sidebar themselves are in hud_frame.png (a node of
	# MapView); these stop clicks there from reaching the map.
	for rect: Rect2 in [Rect2(0, 0, 960, TOP), Rect2(MAP_WIDTH, TOP, 960 - MAP_WIDTH, 540 - TOP)]:
		var blocker := Control.new()
		blocker.position = rect.position
		blocker.size = rect.size
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(blocker)
	_objectives_button = HudStyle.button(self, Rect2(48, 5, 88, 18), "navy", "Objectives", "scroll", false, 9)
	_objectives_button.tooltip_text = "The mission's objectives (O)"
	_objectives_button.pressed.connect(toggle_objectives)
	_menu_button = HudStyle.button(self, Rect2(142, 5, 64, 18), "navy", "Menu", "cog", false, 9)
	_menu_button.tooltip_text = "Pause the mission (Esc or P)"
	_menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	_top_left = HudStyle.label(self, PLAQUE, &"serif_bold", 11, HudStyle.INK)
	_top_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_left.clip_text = true
	for cap: Rect2 in CAPS:
		_cap_icons.append(HudStyle.icon_rect(self, cap.position + Vector2(3, 0), "gem"))
		var name_label := HudStyle.label(self, Rect2(cap.position + Vector2(22, 0), Vector2(70, 18)), &"serif_bold", 10,
				HudStyle.GOLD, true)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cap_names.append(name_label)
		var value := HudStyle.label(self, Rect2(cap.position + Vector2(40, 0), Vector2(cap.size.x - 47, 18)),
				&"serif_bold", 11, HudStyle.LIGHT, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cap_values.append(value)


func _build_message_box() -> void:
	var box := MESSAGE_BOX
	_message_panel = HudStyle.panel(self, box, "parchment")
	_speaker_picture = TextureRect.new()
	_speaker_picture.position = Vector2(6, 6)
	_speaker_picture.size = Vector2(44, 54)
	_speaker_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_panel.add_child(_speaker_picture)
	_speaker_frame = HudStyle.panel(_message_panel, Rect2(4, 4, 48, 58), "cameo", false)
	_speaker = HudStyle.label(_message_panel, Rect2(58, 3, 300, 16), &"serif_bold", 11, HudStyle.INK_RED)
	_message_time = HudStyle.label(_message_panel, Rect2(box.size.x - 70, 4, 62, 14), &"sans", 9, HudStyle.INK_DIM)
	_message_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message_text = HudStyle.label(_message_panel, Rect2(58, 19, box.size.x - 66, 44), &"serif", 11, HudStyle.INK)
	_message_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_text.add_theme_constant_override("line_spacing", -2)
	_message_text.max_lines_visible = 3
	_message_panel.visible = false


func _build_objective_box() -> void:
	_objective_panel = HudStyle.panel(self, Rect2(SIDE_X, 188, SIDE_WIDTH, 104), "parchment")
	var title := HudStyle.label(_objective_panel, Rect2(8, 4, 176, 16), &"serif_bold", 12, HudStyle.INK)
	title.text = "Objective"
	_objective = HudStyle.label(_objective_panel, Rect2(8, 21, 176, 40), &"serif", 10, HudStyle.INK)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.add_theme_constant_override("line_spacing", -2)
	_objective.max_lines_visible = 3
	_status = HudStyle.label(_objective_panel, Rect2(8, 62, 176, 14), &"sans", 9, HudStyle.INK)
	_bar = HudStyle.bar(_objective_panel, Rect2(8, 78, 176, 6), HudStyle.PROGRESS)
	_forces = HudStyle.label(_objective_panel, Rect2(8, 86, 176, 14), &"sans", 9, HudStyle.INK_DIM)
	_help = HudStyle.label(self, Rect2(SIDE_X + 2, 298, SIDE_WIDTH - 2, 104), &"sans", 9, HudStyle.LIGHT_DIM, true)
	_help.text = CONTROLS_HELP
	_help.add_theme_constant_override("line_spacing", -1)


func _build_card() -> void:
	_card = HudStyle.panel(self, CARD, "parchment")
	_card_picture = TextureRect.new()
	_card_picture.position = Vector2(6, 9)
	_card_picture.size = Vector2(44, 54)
	_card_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_card_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_picture)
	_card_frame = HudStyle.panel(_card, Rect2(4, 7, 48, 58), "cameo", false)
	_card_title = HudStyle.label(_card, Rect2(56, 3, 132, 16), &"serif_bold", 12, HudStyle.INK)
	_card_title.clip_text = true
	_card_sub = HudStyle.label(_card, Rect2(56, 18, 132, 14), &"serif_italic", 10, HudStyle.INK_DIM)
	_card_sub.clip_text = true
	_card_health = HudStyle.bar(_card, Rect2(56, 34, 128, 6))
	_card_details = HudStyle.label(_card, Rect2(56, 41, 134, 38), &"sans", 9, HudStyle.INK)
	_card_details.add_theme_constant_override("line_spacing", -3)
	_card_details.max_lines_visible = 3
	_card_details.clip_text = true
	_card.visible = false


func _build_objectives_list() -> void:
	_objectives_panel = HudStyle.panel(self, Rect2(44, TOP - 2, 420, 60), "parchment")
	var title := HudStyle.label(_objectives_panel, Rect2(10, 5, 200, 18), &"serif_bold", 13, HudStyle.INK)
	title.text = "Objectives"
	var close := HudStyle.label(_objectives_panel, Rect2(300, 8, 110, 14), &"sans", 9, HudStyle.INK_DIM)
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close.text = "O to close"
	var rule := ColorRect.new()
	rule.color = Color("a88a5a")
	rule.position = Vector2(10, 25)
	rule.size = Vector2(400, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objectives_panel.add_child(rule)
	_objectives_panel.visible = false


func _build_pause() -> void:
	_pause = _dialog(Vector2(440, 150), 170)
	var pause_title := HudStyle.label(_pause, Rect2(0, 14, 440, 40), &"serif_bold", 28, HudStyle.GOLD, true)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.text = "Paused"
	var pause_text := HudStyle.label(_pause, Rect2(20, 60, 400, 20), &"serif", 12, HudStyle.LIGHT, true)
	pause_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_text.text = "Esc or P carries on."
	_resume = _menu_button_on(_pause, Rect2(16, 100, 96, 28), "Resume", resume_pressed)
	var settings := HudStyle.button(_pause, Rect2(120, 100, 96, 28), "navy", "Settings", "", false, 11)
	settings.focus_mode = Control.FOCUS_ALL
	settings.pressed.connect(show_settings)
	_menu_button_on(_pause, Rect2(224, 100, 96, 28), "Restart", again_pressed)
	_menu_button_on(_pause, Rect2(328, 100, 96, 28), "Title screen", title_pressed)
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.position = Vector2(((MAP_WIDTH - SettingsPanel.SIZE.x) / 2.0), 140)
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		if _pause.visible:
			_resume.grab_focus())


## The debriefing: Victory or Defeat, what the mission's story says about it,
## the time and the losses, and the objectives as they ended.
func _build_result() -> void:
	_result = _dialog(DEBRIEFING.size, DEBRIEFING.position.y)
	_result_title = HudStyle.label(_result, Rect2(0, 10, DEBRIEFING.size.x, 40), &"serif_bold", 30, HudStyle.GOLD, true)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_paper = HudStyle.panel(_result, Rect2(16, 54, DEBRIEFING.size.x - 32, DEBRIEFING.size.y - 106), "parchment")
	var width := _result_paper.size.x - 28.0
	_result_story = HudStyle.label(_result_paper, Rect2(14, 8, width, 80), &"serif", 12, HudStyle.INK)
	_result_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_text = HudStyle.label(_result_paper, Rect2(14, 92, width, 34), &"serif_italic", 11, HudStyle.INK_DIM)
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var y := DEBRIEFING.size.y - 42
	_again = _menu_button_on(_result, Rect2(16, y, 130, 30), "Play again", again_pressed)
	_to_title = _menu_button_on(_result, Rect2(154, y, 130, 30), "Title screen", title_pressed)
	_next = _menu_button_on(_result, Rect2(DEBRIEFING.size.x - 146, y, 130, 30), "Next mission", next_pressed)


func _dialog(dialog_size: Vector2, y: float) -> Panel:
	var dialog := HudStyle.panel(self, Rect2(Vector2(((MAP_WIDTH - dialog_size.x) / 2.0), y), dialog_size), "wood_panel")
	dialog.visible = false
	return dialog


## Show the HUD for a mission. Without one (a map on its own) only the frame,
## the card and the list of controls are shown.
func setup(mission: Mission, map_name := "") -> void:
	_mission = mission
	_result.visible = false
	_pause.visible = false
	_settings.visible = false
	_objectives_panel.visible = false
	_objectives_key = ""
	_message_panel.visible = false
	_card.visible = false
	_objectives_button.disabled = mission == null
	_menu_button.disabled = mission == null
	_make_hero_portraits(mission)
	if mission == null:
		_top_left.text = map_name
		_show_build_panel(false)
		_objective_panel.visible = false
		for i in CAPS.size():
			_set_cap(i, "", "", "")
		_make_ability_buttons([])
		set_selected_building(null)
		return
	var def := mission.def
	_top_left.text = top_left_text(def)
	_objective.text = def.objective
	_show_build_panel(def.has_base())
	build_panel.open(Production.BUILDINGS)
	_make_ability_buttons(ability_keys(def))
	set_selected_building(null)
	refresh(mission, "")


## Has the player a base to build up right now (a headquarters)? A mission
## can give one later, e.g. when a convoy arrives.
static func has_base_now(mission: Mission) -> bool:
	return mission.world.production.builder(Mission.PLAYER_TEAM, Production.BUILDINGS) != null


## Show the build menu, or the objective box and the controls in its place.
func _show_build_panel(on: bool) -> void:
	build_panel.visible = on
	_objective_panel.visible = not on and _mission != null
	_help.visible = not on


## Is the list of controls shown (in a mission without a base)?
func is_help_shown() -> bool:
	return _help.visible


## Is the objective box shown (in a mission without a base)?
func is_objective_box_shown() -> bool:
	return _objective_panel.visible


## The objective the player is working on: the last primary objective shown
## that is still open, or else the first one shown.
static func current_objective(mission: Mission) -> String:
	var shown := mission.shown_objectives()
	for i in range(shown.size() - 1, -1, -1):
		if shown[i].primary and mission.objective_state(shown[i].id) == Mission.OPEN:
			return shown[i].text
	return shown[0].text if not shown.is_empty() else ""


## The keys of the active abilities of the heroes the player starts with, in
## the order the heroes are placed, e.g. ["E", "Q"].
static func ability_keys(def: MissionDef) -> Array[String]:
	var keys: Array[String] = []
	for type in def.placed_types(Mission.PLAYER_TEAM):
		var unit_type := type as UnitType
		if unit_type != null and unit_type.is_hero and unit_type.ability != null and not keys.has(unit_type.ability.key):
			keys.append(unit_type.ability.key)
	return keys


## The living hero whose active ability has this key, or null.
static func hero_with_key(heroes: Array[SimUnit], key: String) -> SimUnit:
	for hero in heroes:
		if hero.type.ability != null and hero.type.ability.key == key:
			return hero
	return null


# --- the command buttons -------------------------------------------------------------

func _command_button(text: String, icon_name: String, command: StringName, tip: String) -> Button:
	var b := HudStyle.button(self, Rect2(SIDE_X, COMMANDS_Y, 45, COMMANDS_HEIGHT), "navy", text, icon_name, true, 9)
	b.tooltip_text = tip
	b.pressed.connect(func() -> void: command_pressed.emit(command))
	return b


## One button per ability key after Attack and Stop, sharing the row.
func _make_ability_buttons(keys: Array[String]) -> void:
	for key: String in _ability_buttons:
		(_ability_buttons[key] as Button).queue_free()
	_ability_buttons.clear()
	var heroes: Array[SimUnit] = []
	if _mission != null:
		heroes = _mission.player_heroes()
	for key in keys:
		var hero := hero_with_key(heroes, key)
		var ability: Ability = hero.type.ability if hero != null else null
		var icon_name := "pulse" if ability != null and ability.kind == Ability.Kind.HEAL_AREA else "heal"
		var tip := "%s (%s)" % [ability.display_name, key] if ability != null else key
		if ability != null and ability.description != "":
			tip += ": " + ability.description
		_ability_buttons[key] = _command_button(key, icon_name, StringName("ability_" + key), tip)
	_lay_out_commands()


func _lay_out_commands() -> void:
	var row: Array[Button] = [_attack, _stop]
	for key: String in _ability_buttons:
		row.append(_ability_buttons[key])
	var gap := 4.0
	var width := floorf((SIDE_WIDTH - gap * (row.size() - 1)) / row.size())
	for i in row.size():
		row[i].position = Vector2(SIDE_X + (width + gap) * i, COMMANDS_Y)
		row[i].size = Vector2(width, COMMANDS_HEIGHT)
	_repair.position = _attack.position
	_repair.size = Vector2(width * 2.0 + gap, COMMANDS_HEIGHT)


## Show Repair (for a selected building of the player's) in place of Attack
## and Stop, or put them back with null.
func set_selected_building(building: SimBuilding) -> void:
	var show_repair := building != null
	_repair.visible = show_repair
	_attack.visible = not show_repair
	_stop.visible = not show_repair
	if show_repair:
		var damaged := building.health < building.type.max_health
		_repair.text = "Stop repair" if building.repairing else "Repair"
		_repair.disabled = not damaged and not building.repairing


# --- the heroes' portraits -----------------------------------------------------------

func _make_hero_portraits(mission: Mission) -> void:
	for child in _hero_layer.get_children():
		child.queue_free()
	_heroes.clear()
	if mission == null:
		return
	var at := HERO_AT
	for hero in mission.player_heroes():
		var slot := {"id": hero.id}
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.position = at
		button.size = HERO_SIZE
		button.tooltip_text = "%s: click to select, double click to go there" % hero.type.display_name
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var hero_id := hero.id
		button.pressed.connect(_on_hero_clicked.bind(hero_id))
		_hero_layer.add_child(button)
		var picture := TextureRect.new()
		picture.texture = portrait_of(hero.type)
		picture.position = Vector2(2, 2)
		picture.size = HERO_SIZE - Vector2(4, 4)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(picture)
		slot["frame"] = HudStyle.panel(button, Rect2(Vector2.ZERO, HERO_SIZE), "cameo", false)
		slot["bar"] = HudStyle.bar(_hero_layer, Rect2(at + Vector2(0, HERO_SIZE.y + 4), Vector2(HERO_SIZE.x, 6)))
		var badge := HudStyle.panel(button, Rect2(HERO_SIZE.x - 18, HERO_SIZE.y - 17, 15, 14), "navy", false)
		var key_label := HudStyle.label(badge, Rect2(0, 0, 15, 14), &"sans_bold", 9, HudStyle.LIGHT, true)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_label.text = hero.type.ability.key if hero.type.ability != null else ""
		badge.visible = hero.type.ability != null
		slot["badge"] = badge
		var wait := HudStyle.label(button, Rect2(4, HERO_SIZE.y - 17, 30, 14), &"sans_bold", 9, HudStyle.LIGHT, true)
		wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot["wait"] = wait
		slot["button"] = button
		_heroes.append(slot)
		at.y += HERO_STEP


func _on_hero_clicked(unit_id: int) -> void:
	var now := Time.get_ticks_msec()
	var twice := now - int(_last_hero_click.get(unit_id, -100000)) <= 400
	_last_hero_click[unit_id] = now
	hero_pressed.emit(unit_id, twice)


## The face to show for a unit type: its portrait, or else its first sprite.
static func portrait_of(type: UnitType) -> Texture2D:
	if type.portrait != null:
		return type.portrait
	return picture_of(type)


## A small picture of a building or a unit: a building's sprite, or the first
## sprite of a unit's sheet.
static func picture_of(item: Resource) -> Texture2D:
	if item is BuildingType:
		return (item as BuildingType).sprite
	if item is UnitType:
		var type := item as UnitType
		if type.sprites == null:
			return null
		var atlas := AtlasTexture.new()
		atlas.atlas = type.sprites
		atlas.region = Rect2(Vector2.ZERO, Vector2(type.sprite_size))
		return atlas
	return null


## Which heroes are selected, so their portraits are framed brighter.
func show_selected(ids: Array) -> void:
	for slot in _heroes:
		var on := ids.has(slot["id"])
		(slot["frame"] as Panel).add_theme_stylebox_override("panel", HudStyle.style("cameo_selected" if on else "cameo"))


func _refresh_heroes(mission: Mission) -> void:
	for slot in _heroes:
		var hero := mission.world.get_unit(slot["id"])
		var alive := hero != null and not hero.dead
		(slot["button"] as Control).visible = alive
		(slot["bar"] as Control).visible = alive
		if not alive:
			continue
		var share := float(hero.health) / hero.type.max_health
		(slot["bar"] as HudStyle.Bar).value = share
		(slot["bar"] as HudStyle.Bar).color = HudStyle.health_color(share)
		var ready := ability_ready(hero)
		var badge := slot["badge"] as Panel
		badge.add_theme_stylebox_override("panel", HudStyle.style("navy" if ready else "navy_disabled"))
		var wait := ceili(hero.ability_ticks_left * SimWorld.TICK_SECONDS)
		(slot["wait"] as Label).text = "%d s" % wait if hero.type.ability != null and wait > 0 else ""


# --- refreshing ---------------------------------------------------------------------

## Bring every text and bar up to date. `hint` is the line for the message
## box when no character is talking; `message` is the mission's latest
## message while it is fresh (empty when there is none).
func refresh(mission: Mission, hint: String, message := {}) -> void:
	var def := mission.def
	_refresh_heroes(mission)
	_refresh_message(mission, hint, message)
	if _objectives_panel.visible:
		_refresh_objectives_list(mission)
	var heroes := mission.player_heroes()
	for key: String in _ability_buttons:
		var hero := hero_with_key(heroes, key)
		var button: Button = _ability_buttons[key]
		button.text = ability_label(hero, true)
		button.disabled = not ability_ready(hero)
	var world := mission.world
	if not build_panel.visible and has_base_now(mission):
		_show_build_panel(true)         # a base given during the mission; the menu then stays
	var base := build_panel.visible
	var players := world.team_size(Mission.PLAYER_TEAM)
	var enemies := world.team_size(Mission.ENEMY_TEAM)
	var storage := world.storage_for(Mission.PLAYER_TEAM)
	if storage > 0:
		var stored := world.stored_for(Mission.PLAYER_TEAM)
		_set_cap(0, "gem", "Orichalcum", "%d / %d" % [stored, storage])
		_cap_values[0].add_theme_color_override("font_color", HudStyle.GOLD if stored >= storage else HudStyle.LIGHT)
	else:
		_set_cap(0, "swords", def.player_side, str(players))
	if base:
		_set_cap(1, "bolt", "Power", "%d / %d" % [world.power_used(Mission.PLAYER_TEAM), world.power_made(Mission.PLAYER_TEAM)])
		_cap_values[1].add_theme_color_override("font_color",
				HudStyle.HEALTH_BAD.lightened(0.3) if world.is_low_power(Mission.PLAYER_TEAM) else HudStyle.LIGHT)
		build_panel.refresh(world, Mission.PLAYER_TEAM)
	elif def.practice:
		_set_cap(1, "flag", "Raiders" if def.has_raid() else "Rock", str(enemies) if def.has_raid() else str(world.ore_left()))
	else:
		_set_cap(1, "flag", def.enemy_side, str(enemies))
	_set_cap(2, "glass", "Time", clock(mission.seconds()))
	if def.skirmish:
		_top_left.text = "Skirmish   %s" % skirmish_forces_text(mission)
		return
	if def.practice:
		_status.text = rock_text(world)
		_forces.text = practice_forces_text(mission)
		_bar.value = float(world.stored_for(Mission.PLAYER_TEAM)) / storage if storage > 0 else 0.0
		_bar.color = HudStyle.PROGRESS
		return
	_objective.text = current_objective(mission)
	_forces.text = "%s units: %d    %s units: %d" % [def.player_side, players, def.enemy_side, enemies]
	if not def.has_control():
		_status.text = ""
		_bar.value = 0.0
		return
	_status.text = hold_text(mission)
	var control := mission.control
	_bar.value = control.progress() if control.owner != ControlPoint.NOBODY else 0.0
	_bar.color = def.player_color if control.owner == Mission.PLAYER_TEAM else def.enemy_color


func _set_cap(index: int, icon_name: String, name_text: String, value: String) -> void:
	_cap_icons[index].visible = icon_name != ""
	if icon_name != "":
		_cap_icons[index].texture = HudStyle.icon(icon_name)
	_cap_names[index].text = name_text
	_cap_values[index].text = value


## The top bar's boxes in words, e.g. "Orichalcum 500 / 1000   Power 30 / 30   Time 0:12".
func top_bar_text() -> String:
	var parts := PackedStringArray()
	for i in CAPS.size():
		if _cap_values[i].text != "":
			parts.append("%s %s" % [_cap_names[i].text, _cap_values[i].text])
	return "   ".join(parts)


## The mission's name on the top bar (in a skirmish, the forces).
func top_left_text_shown() -> String:
	return _top_left.text


func _refresh_message(mission: Mission, hint: String, message: Dictionary) -> void:
	if not message.is_empty():
		var picture := message_portrait(mission, message)
		_speaker_picture.texture = picture
		_speaker_picture.visible = picture != null
		_speaker_frame.visible = picture != null
		var left := 58.0 if picture != null else 10.0
		_speaker.position.x = left
		_message_text.position.x = left
		_message_text.size.x = MESSAGE_BOX.size.x - left - 8.0
		_speaker.text = String(message["speaker"]) if String(message["speaker"]) != "" else "Message"
		_speaker.add_theme_color_override("font_color", HudStyle.INK_RED)
		_message_time.text = clock(int(message["tick"]) * SimWorld.TICK_SECONDS)
		_message_text.text = String(message["text"])
		_message_panel.visible = true
		return
	_speaker_picture.visible = false
	_speaker_frame.visible = false
	_speaker.position.x = 10.0
	_message_text.position.x = 10.0
	_message_text.size.x = MESSAGE_BOX.size.x - 18.0
	_speaker.text = "Hint"
	_speaker.add_theme_color_override("font_color", HudStyle.INK_DIM)
	_message_time.text = ""
	_message_text.text = hint
	_message_panel.visible = hint != ""


## The face for a mission message: its own portrait, or else that of a hero of
## the player's with the speaker's name; null if there is none.
static func message_portrait(mission: Mission, message: Dictionary) -> Texture2D:
	var own: Variant = message.get("portrait")
	if own is Texture2D:
		return own
	for type in mission.def.placed_types(Mission.PLAYER_TEAM):
		var unit_type := type as UnitType
		if unit_type != null and unit_type.portrait != null and unit_type.display_name == message["speaker"]:
			return unit_type.portrait
	return null


## What the message box says now ("" when it is hidden).
func message_shown() -> String:
	return _message_text.text if _message_panel.visible else ""


## Who is talking in the message box ("Hint" for a hint).
func speaker_shown() -> String:
	return _speaker.text if _message_panel.visible else ""


# --- the card -------------------------------------------------------------------------

## Show what is selected or under the mouse on the card: `text` as the
## describe_* functions of MapView write it (name, then role, then details),
## with a picture and, if `health` is not negative, a health bar. "" hides it.
func show_info(text: String, picture: Texture2D = null, health := -1.0) -> void:
	_card.visible = text != ""
	if text == "":
		return
	var lines := text.split("\n")
	var left := 56.0 if picture != null else 8.0
	_card_picture.texture = picture
	_card_picture.visible = picture != null
	_card_frame.visible = picture != null
	_card_title.position.x = left
	_card_title.size.x = SIDE_WIDTH - left - 4.0
	_card_title.text = lines[0]
	var rest := Array(lines.slice(1))
	var sub := ""
	if not rest.is_empty() and not String(rest[0]).begins_with("Health"):
		sub = rest.pop_front()
	_card_sub.position.x = left
	_card_sub.size.x = SIDE_WIDTH - left - 4.0
	_card_sub.text = sub
	_card_health.visible = health >= 0.0
	_card_health.position.x = left
	_card_health.size.x = SIDE_WIDTH - left - 8.0
	if health >= 0.0:
		_card_health.value = health
		_card_health.color = HudStyle.health_color(health)
	_card_details.position = Vector2(left, 41.0 if health >= 0.0 else 34.0)
	_card_details.size.x = SIDE_WIDTH - left - 4.0
	_card_details.text = "\n".join(PackedStringArray(rest))


## What the card says (its lines joined), "" when it is hidden.
func info_shown() -> String:
	if not _card.visible:
		return ""
	var parts := PackedStringArray([_card_title.text])
	if _card_sub.text != "":
		parts.append(_card_sub.text)
	if _card_details.text != "":
		parts.append(_card_details.text)
	return "\n".join(parts)


# --- the objectives list ---------------------------------------------------------------

## Open or close the objectives list.
func toggle_objectives() -> void:
	if _mission == null:
		return
	_objectives_panel.visible = not _objectives_panel.visible
	if _objectives_panel.visible:
		_objectives_key = ""
		_refresh_objectives_list(_mission)


func is_objectives_shown() -> bool:
	return _objectives_panel.visible


## The objectives as the list shows them: one line each, e.g. "[done] Bring
## the Prince to the stony ground".
static func objective_lines(mission: Mission) -> PackedStringArray:
	var lines := PackedStringArray()
	for objective in mission.shown_objectives():
		var state := mission.objective_state(objective.id)
		var mark := "open"
		if state == Mission.DONE:
			mark = "done"
		elif state == Mission.FAILED:
			mark = "failed"
		lines.append("[%s] %s%s" % [mark, objective.text, "" if objective.primary else " (optional)"])
	return lines


func _refresh_objectives_list(mission: Mission) -> void:
	var lines := objective_lines(mission)
	var key := "\n".join(lines)
	if key == _objectives_key:
		return
	_objectives_key = key
	for row in _objective_rows:
		row.queue_free()
	_objective_rows.clear()
	var y := 32.0
	for line in lines:
		var mark := line.substr(1, line.find("]") - 1)
		var text := line.substr(line.find("]") + 2)
		var tick := ObjectiveMark.new()
		tick.state = mark
		tick.position = Vector2(10, y + 2)
		tick.size = Vector2(11, 11)
		_objectives_panel.add_child(tick)
		_objective_rows.append(tick)
		var kind := &"serif_bold" if mark == "open" else &"serif"
		var color := HudStyle.INK
		if mark == "done":
			color = HudStyle.INK_DIM
		elif mark == "failed":
			color = HudStyle.INK_RED
		var row := HudStyle.label(_objectives_panel, Rect2(27, y, 384, 16), kind, 10, color)
		row.text = text
		row.clip_text = true
		_objective_rows.append(row)
		y += 17.0
	_objectives_panel.size.y = y + 8.0


## The mark before an objective: an empty box (open), a ticked box (done) or a cross (failed).
class ObjectiveMark extends Control:
	var state := "open"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := Rect2(Vector2(0.5, 0.5), size - Vector2.ONE)
		match state:
			"done":
				draw_rect(box, HudStyle.INK_DIM, false, 1.0)
				draw_polyline(PackedVector2Array([Vector2(2, 5), Vector2(4.5, 8.5), Vector2(10, 1)]), HudStyle.INK_GREEN, 2.0)
			"failed":
				draw_rect(box, HudStyle.INK_RED, false, 1.0)
				draw_line(Vector2(2, 2), Vector2(9, 9), HudStyle.INK_RED, 2.0)
				draw_line(Vector2(9, 2), Vector2(2, 9), HudStyle.INK_RED, 2.0)
			_:
				draw_rect(box, HudStyle.INK, false, 1.0)


# --- pause and result ------------------------------------------------------------------

## Show the debriefing.
func show_result(mission: Mission) -> void:
	_objectives_panel.visible = false
	_settings.visible = false
	var won := mission.player_won()
	_result_title.text = "Victory" if won else "Defeat"
	var story := mission.def.debriefing_won if won else mission.def.debriefing_lost
	_result_story.text = story
	_result_story.visible = story != ""
	_result_text.text = result_text(mission)
	var y := 8.0
	if story != "":
		y += _result_story.get_line_count() * _result_story.get_line_height() + 8.0
	_result_text.position.y = y
	y += _result_text.get_line_count() * _result_text.get_line_height() + 8.0
	for row in _result_rows:
		row.queue_free()
	_result_rows.clear()
	for line in objective_lines(mission):
		if y > _result_paper.size.y - 22.0:
			break
		var mark := ObjectiveMark.new()
		mark.state = line.substr(1, line.find("]") - 1)
		mark.position = Vector2(14, y + 3)
		mark.size = Vector2(11, 11)
		_result_paper.add_child(mark)
		var row := HudStyle.label(_result_paper, Rect2(31, y, _result_paper.size.x - 45, 16), &"serif", 11, HudStyle.INK)
		row.text = line.substr(line.find("]") + 2)
		row.clip_text = true
		_result_rows.append(mark)
		_result_rows.append(row)
		y += 17.0
	# Fit the board to what it says.
	var paper_height := maxf(y + 4.0, 60.0)
	_result_paper.size.y = paper_height
	var height := _result_paper.position.y + paper_height + 54.0
	_result.size.y = height
	_result.position.y = roundf(TOP + (540.0 - TOP - height) / 2.0)
	for b in [_again, _to_title, _next]:
		b.position.y = height - 42.0
	_next.visible = won and mission.def.next_mission != ""
	_result.visible = true
	if _next.visible:
		_next.grab_focus()
	else:
		_again.grab_focus()


func is_result_shown() -> bool:
	return _result.visible


## The words under Victory or Defeat, as shown.
func result_text_shown() -> String:
	return _result_text.text


## Show the pause menu: Resume, Settings, Restart and Title screen.
func show_pause() -> void:
	_pause.visible = true
	_resume.grab_focus()


func hide_pause() -> void:
	_pause.visible = false
	_settings.visible = false


## Show the settings board over the pause menu.
func show_settings() -> void:
	_settings.visible = true


func is_settings_shown() -> bool:
	return _settings.visible


func is_pause_shown() -> bool:
	return _pause.visible


func _menu_button_on(parent: Control, rect: Rect2, text: String, signal_to_send: Signal) -> Button:
	var b := HudStyle.button(parent, rect, "navy", text, "", false, 11)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: signal_to_send.emit())
	return b


# --- words ----------------------------------------------------------------------------

## What the top bar says in the middle: the mission's name.
static func top_left_text(def: MissionDef) -> String:
	if def.skirmish:
		return "Skirmish: %s against %s (computer)" % [def.player_side, def.enemy_side]
	return def.display_name if def.practice else "Mission %d  -  %s" % [def.number, def.display_name]


## The two sides in a skirmish: their buildings and troops, e.g.
## "Blue 4 / 6   Red 3 / 9" (buildings / troops).
static func skirmish_forces_text(mission: Mission) -> String:
	var world := mission.world
	var def := mission.def
	return "%s %d / %d   %s %d / %d" % [
		def.player_side, world.building_count(Mission.PLAYER_TEAM), world.fighter_count(Mission.PLAYER_TEAM),
		def.enemy_side, world.building_count(Mission.ENEMY_TEAM), world.fighter_count(Mission.ENEMY_TEAM)]


## Seconds as minutes and seconds, e.g. 0:42. Part seconds count as a whole one.
static func clock(seconds: float) -> String:
	var whole := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


## The Orichalcum a team has in store and how much it can store, e.g.
## "Orichalcum 350 / 800". "" for a team with no storage at all.
static func store_text(world: SimWorld, team: int) -> String:
	var storage := world.storage_for(team)
	if storage <= 0:
		return ""
	var stored := world.stored_for(team)
	return "Orichalcum %d / %d%s" % [stored, storage, " (full)" if stored >= storage else ""]


## The line under the bar in a practice mission: the player's harvesters
## and, if the mission has a raid, the raiders and what they have taken.
static func practice_forces_text(mission: Mission) -> String:
	var world := mission.world
	var harvesters := 0
	for unit in world.units:
		if unit.team == Mission.PLAYER_TEAM and not unit.dead and unit.type.is_harvester():
			harvesters += 1
	var text := "Harvesters: %d" % harvesters
	if mission.def.has_raid():
		text += "    Raiders: %d" % world.team_size(Mission.ENEMY_TEAM)
		if world.stolen_for(Mission.ENEMY_TEAM) > 0:
			text += "    Taken: %d" % world.stolen_for(Mission.ENEMY_TEAM)
	return text


## One line saying how much Orichalcum is left in the ground.
static func rock_text(world: SimWorld) -> String:
	var left := world.ore_left()
	return "Left in the rock: %d" % left if left > 0 else "The rock has run out"


## One line saying who holds the control area and for how much longer.
static func hold_text(mission: Mission) -> String:
	var control := mission.control
	if control.owner == ControlPoint.NOBODY:
		return "Contested" if control.contested else "Nobody holds the rock"
	var side := mission.def.player_side if control.owner == Mission.PLAYER_TEAM else mission.def.enemy_side
	if control.contested:
		return "Contested: %s's count waits at %s" % [side, clock(control.seconds_left())]
	return "%s holds the rock: %s to go" % [side, clock(control.seconds_left())]


## The words under Victory or Defeat.
static func result_text(mission: Mission) -> String:
	var def := mission.def
	var how := ""
	match [mission.player_won(), mission.win_reason]:
		[true, &"hold"]: how = "You held the Orichalcum rock."
		[true, _]: how = "Every enemy building and soldier is destroyed." if def.skirmish else "Every enemy is destroyed."
		[false, &"hold"]: how = "%s held the Orichalcum rock." % def.enemy_side
		[false, &"hero"]: how = "%s has fallen." % (mission.fallen_hero.display_name if mission.fallen_hero != null else "Your hero")
		[false, _]: how = "Your base and your troops are destroyed." if def.skirmish else "Your force is destroyed."
	if def.skirmish:
		var world := mission.world
		return "%s\nTime %s.  Lost: %d units, %d buildings.\nDestroyed: %d units, %d buildings." % [
			how, clock(mission.seconds()),
			int(world.losses.get(Mission.PLAYER_TEAM, 0)), int(world.buildings_lost.get(Mission.PLAYER_TEAM, 0)),
			int(world.losses.get(Mission.ENEMY_TEAM, 0)), int(world.buildings_lost.get(Mission.ENEMY_TEAM, 0)),
		]
	return "%s\nTime %s.  Units lost: %d.  Enemies destroyed: %d." % [
		how, clock(mission.seconds()),
		int(mission.world.losses.get(Mission.PLAYER_TEAM, 0)),
		int(mission.world.losses.get(Mission.ENEMY_TEAM, 0)),
	]


## Text of an ability button: the ability's name and key, or the seconds
## until it is ready again. `short` gives just the name (or the seconds),
## for the narrow buttons under their icons.
static func ability_label(hero: SimUnit, short := false) -> String:
	if hero == null or hero.type.ability == null:
		return "-"
	var ability := hero.type.ability
	if hero.ability_ticks_left > 0:
		var wait := ceili(hero.ability_ticks_left * SimWorld.TICK_SECONDS)
		return "%d s" % wait if short else "%s %ds" % [ability.display_name, wait]
	return ability.display_name if short else "%s (%s)" % [ability.display_name, ability.key]


static func ability_ready(commander: SimUnit) -> bool:
	return commander != null and commander.type.ability != null and commander.ability_ticks_left == 0
