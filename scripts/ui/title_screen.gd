extends Control
## Placeholder title screen. It will be replaced by the real menu later.
##
## Starting the game with "-- --map=forest" or "-- --map=desert" on the command
## line skips this screen and opens that map.

const MILESTONE := "M2 Units"
const MAP_SCENE := "res://scenes/map_view.tscn"
## Map name -> the map file and the unit type of the player's squad on it.
const MAPS := {
	"forest": {"map": "res://data/maps/forest_01.tres", "squad": "res://data/units/blue_infantry.tres"},
	"desert": {"map": "res://data/maps/desert_01.tres", "squad": "res://data/units/red_infantry.tres"},
}
const SQUAD_SIZE := 5

@onready var _status: Label = $Center/Box/Status
@onready var _forest: Button = $Center/Box/Buttons/Forest
@onready var _desert: Button = $Center/Box/Buttons/Desert
@onready var _quit: Button = $Center/Box/Buttons/Quit


func _ready() -> void:
	var version: String = Engine.get_version_info()["string"]
	_status.text = "%s  |  placeholder title screen  |  Godot %s" % [MILESTONE, version]
	_forest.pressed.connect(open_map.bind("forest"))
	_desert.pressed.connect(open_map.bind("desert"))
	_quit.pressed.connect(get_tree().quit)
	_forest.grab_focus()
	var wanted := map_from_args(OS.get_cmdline_user_args())
	if wanted != "":
		open_map.call_deferred(wanted)


## The map named by a "--map=<name>" argument, or "" if there is none or it is unknown.
static func map_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--map="):
			var wanted := arg.trim_prefix("--map=")
			return wanted if MAPS.has(wanted) else ""
	return ""


func open_map(map_name: String) -> void:
	MapView.requested_map = MAPS[map_name]["map"]
	MapView.requested_squad = MAPS[map_name]["squad"]
	MapView.requested_squad_size = SQUAD_SIZE
	get_tree().change_scene_to_file(MAP_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
