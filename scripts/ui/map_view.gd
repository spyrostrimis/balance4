class_name MapView
extends Node2D
## The in-game screen: the map, the units, the shroud, the camera and the
## sidebar with the minimap. It runs the simulation at a fixed pace and turns
## mouse and keyboard input into selections and orders.
##
## Controls: left click selects a unit, dragging selects every unit in the box
## (hold Shift to add to the selection), right click sends the selected units
## to that spot. Ctrl+1..9 stores the selection as a group, 1..9 selects the
## group again and pressing the number twice jumps the camera to it.

const SCREEN_SIZE := Vector2(960, 540)
const SIDEBAR_WIDTH := 212.0
const TITLE_SCENE := "res://scenes/main.tscn"
## Moving the mouse less than this (in pixels) between press and release is a click, not a drag.
const CLICK_SLOP := 4.0
## Two presses of a group number within this many seconds jump the camera to the group.
const DOUBLE_TAP_SECONDS := 0.4
## The simulation never runs more than this many ticks in one frame (after a long stall it slows down instead).
const MAX_TICKS_PER_FRAME := 5

## The map to show when this scene starts. Set it before changing to this scene.
static var requested_map := "res://data/maps/forest_01.tres"
## The unit type of the player's squad, or "" for an empty map.
static var requested_squad := "res://data/units/blue_infantry.tres"
## How many units the squad has.
static var requested_squad_size := 5

var map: MapData
var world: SimWorld
var selection := Selection.new()

var _tick_time := 0.0
var _dragging := false
var _drag_start_screen := Vector2.ZERO
var _drag_start_map := Vector2.ZERO
var _last_group := 0
var _last_group_time := -10.0
var _clock := 0.0

@onready var terrain: TerrainView = $Terrain
@onready var units_view: UnitsView = $Units
@onready var shroud_view: ShroudView = $Shroud
@onready var camera: MapCamera = $Camera
@onready var minimap: Minimap = $Hud/Sidebar/Minimap
@onready var drag_box: DragBox = $Hud/DragBox
@onready var _map_name: Label = $Hud/Sidebar/MapName
@onready var _info: Label = $Hud/Sidebar/Info


func _ready() -> void:
	var loaded := load(requested_map) as MapData
	if loaded == null:
		push_error("Could not load map: %s" % requested_map)
		return
	var squad: UnitType = null
	if requested_squad != "":
		squad = load(requested_squad) as UnitType
	show_map(loaded, squad, requested_squad_size)


## Show a map and, if a unit type is given, put the player's squad at the map's first start position.
func show_map(p_map: MapData, squad: UnitType = null, squad_size := 0) -> void:
	map = p_map
	for problem in map.problems():
		push_warning("Map '%s': %s" % [map.display_name, problem])
	world = SimWorld.new(map)
	selection = Selection.new()
	_tick_time = 0.0
	_dragging = false
	terrain.show_map(map)

	var focus := Vector2(map.get_pixel_size()) / 2.0
	if squad != null and squad_size > 0:
		var start := map.starts[0] if not map.starts.is_empty() else map.get_size() / 2
		for unit in spawn_squad(world, squad, SimWorld.PLAYER_TEAM, start, squad_size):
			unit.facing = SimWorld.facing_for(map.get_size() / 2 - start)
		focus = MapData.cell_center(start)

	units_view.setup(world, selection)
	shroud_view.setup(world.shroud_for(SimWorld.PLAYER_TEAM))
	var view_size := Vector2(SCREEN_SIZE.x - SIDEBAR_WIDTH, SCREEN_SIZE.y)
	camera.setup(Vector2(map.get_pixel_size()), view_size, SCREEN_SIZE)
	camera.center_on(focus)
	minimap.setup(map, camera, world)
	var size := map.get_size()
	_map_name.text = "%s  %dx%d" % [map.display_name, size.x, size.y]
	_info.text = ""


## Put `count` units of one type on the free cells nearest to a cell.
static func spawn_squad(p_world: SimWorld, type: UnitType, team: int, near: Vector2i, count: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	var region := p_world.region_at(p_world.nearest_free_cell(near, 0))
	for i in count:
		var cell := p_world.nearest_free_cell(near, region)
		if cell == SimWorld.NO_CELL:
			break
		out.append(p_world.add_unit(type, team, cell))
	return out


# --- the simulation clock ------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	_tick_time += delta
	var ticks := 0
	while _tick_time >= SimWorld.TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		world.tick()
		_tick_time -= SimWorld.TICK_SECONDS
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_tick_time = 0.0
	units_view.alpha = _tick_time / SimWorld.TICK_SECONDS
	shroud_view.refresh()

	var mouse := get_viewport().get_mouse_position()
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if mouse.distance_to(_drag_start_screen) >= CLICK_SLOP:
				drag_box.show_rect(Rect2(_drag_start_map - camera.position, mouse - (_drag_start_map - camera.position)))
		else:
			_finish_drag(mouse, Input.is_key_pressed(KEY_SHIFT))
	_update_info(mouse)


# --- input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(TITLE_SCENE)
		return
	var button := event as InputEventMouseButton
	if button != null and in_map_area(button.position):
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_drag_start_screen = button.position
				_drag_start_map = screen_to_map(button.position)
			elif _dragging:
				_finish_drag(button.position, button.shift_pressed)
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			order_move_to(screen_to_map(button.position))
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		press_group_key(key.keycode - KEY_0, key.ctrl_pressed)


## Is this screen position over the map (not the sidebar)?
static func in_map_area(screen_point: Vector2) -> bool:
	return screen_point.x >= 0 and screen_point.y >= 0 \
			and screen_point.x < SCREEN_SIZE.x - SIDEBAR_WIDTH and screen_point.y < SCREEN_SIZE.y


func screen_to_map(screen_point: Vector2) -> Vector2:
	return camera.position + screen_point


func _finish_drag(screen_point: Vector2, add: bool) -> void:
	_dragging = false
	drag_box.hide_rect()
	if screen_point.distance_to(_drag_start_screen) < CLICK_SLOP:
		click_select(screen_to_map(screen_point), add)
	else:
		box_select(Rect2(_drag_start_map, screen_to_map(screen_point) - _drag_start_map), add)


## A click on the map: select the unit there. With `add`, add it to or take it out of the selection.
func click_select(map_point: Vector2, add := false) -> void:
	var unit := UnitsView.unit_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
	if unit == null:
		if not add:
			selection.clear()
	elif add:
		selection.toggle(unit.id)
	else:
		selection.set_ids([unit.id])


## A drag on the map: select every unit in the box. With `add`, keep what was selected before.
func box_select(map_rect: Rect2, add := false) -> void:
	var ids := UnitsView.units_in_rect(world, map_rect, SimWorld.PLAYER_TEAM, units_view.alpha)
	if add:
		selection.add_ids(ids)
	else:
		selection.set_ids(ids)


## Send the selected units to a point on the map.
func order_move_to(map_point: Vector2) -> void:
	if selection.is_empty():
		return
	var cell := MapData.cell_at_pixel(map_point)
	if not map.in_bounds(cell):
		return
	world.order_move(selection.ids, cell)
	units_view.add_move_marker(map_point)


## A number key: with Ctrl store the selection as that group, without select the
## group, and on a second quick press move the camera to it.
func press_group_key(number: int, store: bool) -> void:
	if store:
		selection.assign_group(number)
		return
	if not selection.recall_group(number):
		return
	if number == _last_group and _clock - _last_group_time <= DOUBLE_TAP_SECONDS:
		camera.center_on(selection_center())
	_last_group = number
	_last_group_time = _clock


## The middle of the selected units, in map pixels.
func selection_center() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for id in selection.ids:
		var unit := world.get_unit(id)
		if unit != null:
			sum += UnitsView.feet_position(unit)
			count += 1
	return sum / count if count > 0 else camera.position + camera.view_size / 2.0


# --- sidebar text --------------------------------------------------------------------

## What the sidebar says about the current selection. "" if nothing is selected.
static func describe_selection(p_world: SimWorld, p_selection: Selection) -> String:
	if p_selection.is_empty():
		return ""
	if p_selection.ids.size() == 1:
		var unit := p_world.get_unit(p_selection.ids[0])
		if unit == null:
			return ""
		return "%s\n%s\nHealth %d / %d" % [unit.type.display_name, unit.type.role, unit.health, unit.type.max_health]
	var names := {}
	for id in p_selection.ids:
		var unit := p_world.get_unit(id)
		if unit != null:
			names[unit.type.display_name] = names.get(unit.type.display_name, 0) + 1
	var lines := PackedStringArray(["%d units selected" % p_selection.ids.size()])
	for unit_name in names:
		lines.append("%d x %s" % [names[unit_name], unit_name])
	return "\n".join(lines)


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


func _update_info(mouse: Vector2) -> void:
	var text := describe_selection(world, selection)
	if text == "" and in_map_area(mouse):
		var cell := MapData.cell_at_pixel(screen_to_map(mouse))
		if world.shroud_for(SimWorld.PLAYER_TEAM).is_explored(cell):
			text = describe_cell(map, cell)
		elif map.in_bounds(cell):
			text = "Cell %d, %d\nUnexplored" % [cell.x, cell.y]
	if text != _info.text:
		_info.text = text
