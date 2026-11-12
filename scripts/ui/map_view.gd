class_name MapView
extends Node2D
## The in-game screen: the map, the camera and the sidebar with the minimap.

const SCREEN_SIZE := Vector2(960, 540)
const SIDEBAR_WIDTH := 212.0
const TITLE_SCENE := "res://scenes/main.tscn"

## The map to show when this scene starts. Set it before changing to this scene.
static var requested_map := "res://data/maps/forest_01.tres"

var map: MapData

@onready var terrain: TerrainView = $Terrain
@onready var camera: MapCamera = $Camera
@onready var minimap: Minimap = $Hud/Sidebar/Minimap
@onready var _map_name: Label = $Hud/Sidebar/MapName
@onready var _info: Label = $Hud/Sidebar/Info


func _ready() -> void:
	var loaded := load(requested_map) as MapData
	if loaded == null:
		push_error("Could not load map: %s" % requested_map)
		return
	show_map(loaded)


func show_map(p_map: MapData) -> void:
	map = p_map
	for problem in map.problems():
		push_warning("Map '%s': %s" % [map.display_name, problem])
	terrain.show_map(map)
	var view_size := Vector2(SCREEN_SIZE.x - SIDEBAR_WIDTH, SCREEN_SIZE.y)
	camera.setup(Vector2(map.get_pixel_size()), view_size, SCREEN_SIZE)
	camera.center_on(Vector2(map.get_pixel_size()) / 2.0)
	minimap.setup(map, camera)
	var size := map.get_size()
	_map_name.text = "%s  %dx%d" % [map.display_name, size.x, size.y]
	_info.text = ""


## What the sidebar says about a cell: its position, terrain and what it allows.
static func describe_cell(p_map: MapData, cell: Vector2i) -> String:
	var t := p_map.terrain_at(cell)
	if t == null:
		return ""
	return "Cell %d, %d\n%s\n%s\n%s" % [
		cell.x, cell.y, t.display_name,
		"Passable" if t.walkable else "Impassable",
		"Can build here" if t.buildable else "Cannot build here",
	]


func _process(_delta: float) -> void:
	if map == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var text := ""
	if mouse.x < SCREEN_SIZE.x - SIDEBAR_WIDTH:
		text = describe_cell(map, MapData.cell_at_pixel(camera.position + mouse))
	if text != _info.text:
		_info.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(TITLE_SCENE)
