class_name TitleScreen
extends Control
## The title screen: Play (the story missions, each with a briefing first),
## Practice (the trials and the skirmish), Settings and Quit, over a slow pan
## across Mission 2's map. It builds its own controls (see HudStyle).
##
## Starting the game with "-- --map=<name>" on the command line skips this
## screen (and the briefing) and starts the mission of that name: forest or
## desert for Mission 1, mission-2 for Mission 2 (as Blue), harvest-forest or
## harvest-desert for the harvest trial, raid-forest or raid-desert for the
## raid trial, base-forest or base-desert for the base trial, skirmish-forest
## or skirmish-desert for a skirmish against the computer, hero-forest for
## the hero trial.

const MILESTONE := "M7 Vertical slice (in progress)"
const MAP_SCENE := "res://scenes/map_view.tscn"
## Name -> the mission started by it. Mission 1 is played as Blue on the
## forest map and as Red on the desert map. The harvest trial is a practice
## mission on the same maps: a refinery, two harvesters and no opponent. The
## raid trial adds three soldiers for the player and three raiders. The base
## trial starts with a headquarters, a refinery and one harvester, and lets
## the player build. A skirmish gives both sides that base, three soldiers,
## and the enemy to the computer.
const MISSIONS := {
	"forest": "res://data/missions/first_claim_blue.tres",
	"desert": "res://data/missions/first_claim_red.tres",
	"mission-2": "res://data/missions/holding_the_claim_blue.tres",
	"harvest-forest": "res://data/missions/harvest_trial_blue.tres",
	"harvest-desert": "res://data/missions/harvest_trial_red.tres",
	"raid-forest": "res://data/missions/raid_trial_blue.tres",
	"raid-desert": "res://data/missions/raid_trial_red.tres",
	"base-forest": "res://data/missions/base_trial_blue.tres",
	"base-desert": "res://data/missions/base_trial_red.tres",
	"skirmish-forest": "res://data/missions/skirmish_blue.tres",
	"skirmish-desert": "res://data/missions/skirmish_red.tres",
	"hero-forest": "res://data/missions/hero_trial_blue.tres",
}
## The Play page: the story missions, in order.
const STORY := ["forest", "desert", "mission-2"]
## The Practice page: the trials and the skirmishes, in pairs.
const PRACTICE := ["harvest-forest", "harvest-desert", "raid-forest", "raid-desert", "base-forest", "base-desert",
		"skirmish-forest", "skirmish-desert", "hero-forest"]
## The map shown behind the menu, and how fast it pans (map pixels per second).
const BACKDROP := "res://data/missions/holding_the_claim_blue.tres"
const PAN_SPEED := 9.0

var _pages := {}
var _page := ""
var _mission_buttons := {}
var _settings: SettingsPanel
var _backdrop: Node2D
var _pan_from := Vector2.ZERO
var _pan_to := Vector2.ZERO
var _pan := 0.0
var _pan_direction := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.035, 0.02, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var title := HudStyle.label(self, Rect2(0, 46, 960, 70), &"serif_bold", 60, HudStyle.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.text = "Balance"
	var tagline := HudStyle.label(self, Rect2(0, 120, 960, 20), &"serif_italic", 14, HudStyle.LIGHT, true)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.text = "Every faction claims to seek Balance. Each defines it differently."
	var version: String = Engine.get_version_info()["string"]
	var status := HudStyle.label(self, Rect2(12, 518, 936, 14), &"sans", 9, HudStyle.LIGHT_DIM, true)
	status.text = "%s  |  Godot %s  |  all names and numbers are provisional" % [MILESTONE, version]

	_build_main_page()
	_build_play_page()
	_build_practice_page()
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.position = Vector2((960 - SettingsPanel.SIZE.x) / 2.0, 172)
	_settings.visible = false
	_settings.closed.connect(show_page.bind("main"))
	show_page("main")
	var wanted := map_from_args(OS.get_cmdline_user_args())
	if wanted != "":
		open_map.call_deferred(wanted)


## The map behind the menu: Mission 2's map with its forces, panning slowly
## from Blue's side to Red's and back.
func _build_backdrop() -> void:
	var def := load(BACKDROP) as MissionDef
	if def == null:
		return
	var mission := Mission.new(def)
	_backdrop = Node2D.new()
	add_child(_backdrop)
	var terrain := TerrainView.new()
	_backdrop.add_child(terrain)
	terrain.show_map(def.map)
	var buildings := BuildingsView.new()
	_backdrop.add_child(buildings)
	buildings.setup(mission.world, Selection.new())
	var units := UnitsView.new()
	_backdrop.add_child(units)
	units.setup(mission.world, Selection.new())
	var map_size := Vector2(def.map.get_pixel_size())
	_pan_from = -Vector2(0, map_size.y - 540)
	_pan_to = -Vector2(map_size.x - 960, 0)
	_backdrop.position = _pan_from


func _process(delta: float) -> void:
	if _backdrop == null:
		return
	var length := _pan_from.distance_to(_pan_to)
	_pan = clampf(_pan + _pan_direction * PAN_SPEED * delta / maxf(length, 1.0), 0.0, 1.0)
	if _pan <= 0.0 or _pan >= 1.0:
		_pan_direction = -_pan_direction
	_backdrop.position = _pan_from.lerp(_pan_to, smoothstep(0.0, 1.0, _pan)).round()


func _page_panel(page: String, width: float, height: float) -> Panel:
	var panel := HudStyle.panel(self, Rect2((960 - width) / 2.0, 172, width, height), "wood_panel")
	_pages[page] = panel
	return panel


func _page_button(panel: Control, rect: Rect2, text: String, kind := "navy") -> Button:
	var b := HudStyle.button(panel, rect, kind, text, "", false, 12)
	b.focus_mode = Control.FOCUS_ALL
	return b


func _build_main_page() -> void:
	var panel := _page_panel("main", 300, 212)
	var entries := [["Play", show_page.bind("play")], ["Practice", show_page.bind("practice")],
			["Settings", show_page.bind("settings")], ["Quit", quit]]
	for i in entries.size():
		var b := _page_button(panel, Rect2(30, 20 + i * 44, 240, 34), entries[i][0], "wood" if i == 3 else "navy")
		b.pressed.connect(entries[i][1])
		b.name = entries[i][0]


func _build_play_page() -> void:
	var panel := _page_panel("play", 420, 76 + STORY.size() * 44 + 50)
	_page_heading(panel, "Play")
	for i in STORY.size():
		var key: String = STORY[i]
		var b := _page_button(panel, Rect2(30, 52 + i * 44, 360, 34), mission_label(key))
		b.pressed.connect(open_map.bind(key, true))
		_mission_buttons[key] = b
	var back := _page_button(panel, Rect2(150, panel.size.y - 50, 120, 30), "Back", "wood")
	back.pressed.connect(show_page.bind("main"))


func _build_practice_page() -> void:
	var rows := ceili(PRACTICE.size() / 2.0)
	var panel := _page_panel("practice", 560, 76 + rows * 40 + 50)
	_page_heading(panel, "Practice")
	for i in PRACTICE.size():
		var key: String = PRACTICE[i]
		var b := _page_button(panel, Rect2(24 + (i % 2) * 260, 52 + (i / 2) * 40, 252, 32), mission_label(key))
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(open_map.bind(key))
		_mission_buttons[key] = b
	var back := _page_button(panel, Rect2(220, panel.size.y - 50, 120, 30), "Back", "wood")
	back.pressed.connect(show_page.bind("main"))


func _page_heading(panel: Control, text: String) -> void:
	var heading := HudStyle.label(panel, Rect2(0, 12, panel.size.x, 30), &"serif_bold", 20, HudStyle.GOLD, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.text = text


## What a mission's button says, e.g. "Mission 2: Holding the Claim (Blue)"
## or "Raid trial (Red, desert)".
static func mission_label(key: String) -> String:
	var def := load(MISSIONS[key]) as MissionDef
	if def == null:
		return key
	var place := "forest" if key.ends_with("forest") or key in ["forest", "mission-2"] else "desert"
	if def.kind == MissionDef.Kind.STORY:
		return "Mission %d: %s  (%s)" % [def.number, def.display_name, def.player_side]
	if def.skirmish:
		return "Skirmish  (%s, %s)" % [def.player_side, place]
	return "%s  (%s, %s)" % [def.display_name, def.player_side, place]


## Show one page of the menu: "main", "play", "practice" or "settings".
func show_page(page: String) -> void:
	_page = page
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page
	_settings.visible = page == "settings"
	if _pages.has(page):
		for child in (_pages[page] as Control).get_children():
			if child is Button:
				(child as Button).grab_focus()
				break


func current_page() -> String:
	return _page


## The button that starts a mission (a key of MISSIONS), or null.
func mission_button(key: String) -> Button:
	return _mission_buttons.get(key)


## The mission named by a "--map=<name>" argument, or "" if there is none or it is unknown.
static func map_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--map="):
			var wanted := arg.trim_prefix("--map=")
			return wanted if MISSIONS.has(wanted) else ""
	return ""


## Start the mission with this name (a key of MISSIONS); with `briefed`, show
## its briefing first.
func open_map(map_name: String, briefed := false) -> void:
	if briefed:
		BriefingScreen.open(get_tree(), MISSIONS[map_name])
		return
	MapView.requested_mission = MISSIONS[map_name]
	get_tree().change_scene_to_file(MAP_SCENE)


func quit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _page == "main":
			quit()
		elif _page != "settings":       # the settings board handles its own Esc
			show_page("main")
		get_viewport().set_input_as_handled()
