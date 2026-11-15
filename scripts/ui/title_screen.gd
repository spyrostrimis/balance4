extends Control
## Placeholder title screen. It will be replaced by the real menu later.
##
## Starting the game with "-- --map=<name>" on the command line skips this
## screen and starts the mission of that name: forest or desert for Mission 1,
## harvest-forest or harvest-desert for the harvest trial, raid-forest or
## raid-desert for the raid trial.

const MILESTONE := "M4 Economy"
const MAP_SCENE := "res://scenes/map_view.tscn"
## Name -> the mission started by it. Mission 1 is played as Blue on the
## forest map and as Red on the desert map. The harvest trial is a practice
## mission on the same maps: a refinery, two harvesters and no opponent. The
## raid trial adds three soldiers for the player and three raiders.
const MISSIONS := {
	"forest": "res://data/missions/first_claim_blue.tres",
	"desert": "res://data/missions/first_claim_red.tres",
	"harvest-forest": "res://data/missions/harvest_trial_blue.tres",
	"harvest-desert": "res://data/missions/harvest_trial_red.tres",
	"raid-forest": "res://data/missions/raid_trial_blue.tres",
	"raid-desert": "res://data/missions/raid_trial_red.tres",
}

@onready var _status: Label = $Center/Box/Status
@onready var _forest: Button = $Center/Box/Buttons/Forest
@onready var _desert: Button = $Center/Box/Buttons/Desert
@onready var _quit: Button = $Center/Box/Buttons/Quit
@onready var _harvest_forest: Button = $Center/Box/Trials/HarvestForest
@onready var _harvest_desert: Button = $Center/Box/Trials/HarvestDesert
@onready var _raid_forest: Button = $Center/Box/Raids/RaidForest
@onready var _raid_desert: Button = $Center/Box/Raids/RaidDesert


func _ready() -> void:
	var version: String = Engine.get_version_info()["string"]
	_status.text = "%s  |  placeholder title screen  |  Godot %s" % [MILESTONE, version]
	_forest.pressed.connect(open_map.bind("forest"))
	_desert.pressed.connect(open_map.bind("desert"))
	_harvest_forest.pressed.connect(open_map.bind("harvest-forest"))
	_harvest_desert.pressed.connect(open_map.bind("harvest-desert"))
	_raid_forest.pressed.connect(open_map.bind("raid-forest"))
	_raid_desert.pressed.connect(open_map.bind("raid-desert"))
	_quit.pressed.connect(get_tree().quit)
	_forest.grab_focus()
	var wanted := map_from_args(OS.get_cmdline_user_args())
	if wanted != "":
		open_map.call_deferred(wanted)


## The mission named by a "--map=<name>" argument, or "" if there is none or it is unknown.
static func map_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--map="):
			var wanted := arg.trim_prefix("--map=")
			return wanted if MISSIONS.has(wanted) else ""
	return ""


## Start the mission with this name (a key of MISSIONS).
func open_map(map_name: String) -> void:
	MapView.requested_mission = MISSIONS[map_name]
	get_tree().change_scene_to_file(MAP_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
