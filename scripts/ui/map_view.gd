class_name MapView
extends Node2D
## The in-game screen: the map, the units, the shroud, the camera, the sidebar
## with the minimap and, when a mission is being played, the mission HUD. It
## runs the simulation at a fixed pace and turns mouse and keyboard input into
## selections and orders.
##
## Controls: left click selects a unit, dragging selects every unit in the box
## (hold Shift to add to the selection). Right click sends the selected units
## to that spot, or at the enemy under the mouse. A then left click is
## attack-move; S stops; Q then left click on one of your units uses the
## commander's ability on it. Ctrl+1..9 stores the selection as a group, 1..9
## selects the group again and pressing the number twice jumps the camera to it.

## What a left click on the map does.
enum Mode {
	## Select.
	NORMAL,
	## Give an attack-move order (after A or the Attack button).
	ATTACK_MOVE,
	## Pick the unit for the commander's ability (after Q or its button).
	ABILITY,
}

const SCREEN_SIZE := Vector2(960, 540)
const SIDEBAR_WIDTH := 212.0
const TITLE_SCENE := "res://scenes/main.tscn"
## Moving the mouse less than this (in pixels) between press and release is a click, not a drag.
const CLICK_SLOP := 4.0
## Two presses of a group number within this many seconds jump the camera to the group.
const DOUBLE_TAP_SECONDS := 0.4
## The simulation never runs more than this many ticks in one frame (after a long stall it slows down instead).
const MAX_TICKS_PER_FRAME := 5
## How long a message such as "Mend is not ready yet" stays in the hint box.
const MESSAGE_SECONDS := 2.5

## The mission to play when this scene starts (a MissionDef file), or "" to
## just show `requested_map`. Set it before changing to this scene.
static var requested_mission := ""
## The map to show when this scene starts and no mission is requested.
static var requested_map := "res://data/maps/forest_01.tres"
## The unit type of the player's squad on that map, or "" for an empty map.
static var requested_squad := "res://data/units/blue_infantry.tres"
## How many units the squad has.
static var requested_squad_size := 5

var map: MapData
var world: SimWorld
## The mission being played, or null when the map is shown on its own.
var mission: Mission
var hints: MissionHints
var selection := Selection.new()
var mode := Mode.NORMAL

var _tick_time := 0.0
var _dragging := false
var _drag_start_screen := Vector2.ZERO
var _drag_start_map := Vector2.ZERO
var _last_group := 0
var _last_group_time := -10.0
var _clock := 0.0
var _message := ""
var _message_left := 0.0
var _seen_removed := 0
var _result_shown := false

@onready var terrain: TerrainView = $Terrain
@onready var control_view: ControlView = $ControlArea
@onready var units_view: UnitsView = $Units
@onready var shroud_view: ShroudView = $Shroud
@onready var camera: MapCamera = $Camera
@onready var minimap: Minimap = $Hud/Sidebar/Minimap
@onready var drag_box: DragBox = $Hud/DragBox
@onready var hud: MissionHud = $Hud/MissionHud
@onready var _map_name: Label = $Hud/Sidebar/MapName
@onready var _info: Label = $Hud/Sidebar/Info


func _ready() -> void:
	hud.command_pressed.connect(_on_command)
	hud.again_pressed.connect(restart_mission)
	hud.title_pressed.connect(back_to_title)
	if requested_mission != "":
		var def := load(requested_mission) as MissionDef
		if def == null:
			push_error("Could not load mission: %s" % requested_mission)
			return
		show_mission(def)
		return
	var loaded := load(requested_map) as MapData
	if loaded == null:
		push_error("Could not load map: %s" % requested_map)
		return
	var squad: UnitType = null
	if requested_squad != "":
		squad = load(requested_squad) as UnitType
	show_map(loaded, squad, requested_squad_size)


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## Show a map on its own and, if a unit type is given, put the player's squad at the map's first start position.
func show_map(p_map: MapData, squad: UnitType = null, squad_size := 0) -> void:
	mission = null
	hints = null
	var new_world := SimWorld.new(p_map)
	var focus := Vector2(p_map.get_pixel_size()) / 2.0
	if squad != null and squad_size > 0:
		var start := p_map.starts[0] if not p_map.starts.is_empty() else p_map.get_size() / 2
		for unit in spawn_squad(new_world, squad, SimWorld.PLAYER_TEAM, start, squad_size):
			unit.facing = SimWorld.facing_toward(p_map.get_size() / 2 - start)
		focus = MapData.cell_center(start)
	_attach(p_map, new_world, focus)
	var size := map.get_size()
	_map_name.text = "%s  %dx%d" % [map.display_name, size.x, size.y]


## Start a mission: its map, both forces, the control point and the scripted opponent.
func show_mission(def: MissionDef) -> void:
	mission = Mission.new(def)
	hints = MissionHints.new()
	var focus := Vector2(def.map.get_pixel_size()) / 2.0
	var commander := mission.player_commander()
	if commander != null:
		focus = MapData.cell_center(commander.cell)
	elif not def.map.starts.is_empty():
		focus = MapData.cell_center(def.map.starts[0])
	_attach(def.map, mission.world, focus)
	_map_name.text = "%d: %s" % [def.number, def.display_name]


## Start the current mission again from the beginning.
func restart_mission() -> void:
	if mission != null:
		show_mission(mission.def)


func back_to_title() -> void:
	requested_mission = ""
	get_tree().change_scene_to_file(TITLE_SCENE)


## Has the mission been won or lost? Always false when no mission is being played.
func is_over() -> bool:
	return mission != null and mission.is_over()


func _attach(p_map: MapData, p_world: SimWorld, focus: Vector2) -> void:
	map = p_map
	for problem in map.problems():
		push_warning("Map '%s': %s" % [map.display_name, problem])
	world = p_world
	selection = Selection.new()
	selection.changed.connect(_on_selection_changed)
	set_mode(Mode.NORMAL)
	_tick_time = 0.0
	_dragging = false
	_message_left = 0.0
	_seen_removed = world.removed_count
	_result_shown = false
	drag_box.hide_rect()
	terrain.show_map(map)
	units_view.setup(world, selection)
	shroud_view.setup(world.shroud_for(SimWorld.PLAYER_TEAM))
	var view_size := Vector2(SCREEN_SIZE.x - SIDEBAR_WIDTH, SCREEN_SIZE.y)
	camera.setup(Vector2(map.get_pixel_size()), view_size, SCREEN_SIZE)
	camera.center_on(focus)
	minimap.setup(map, camera, world)
	var colors := {}
	if mission != null:
		colors = {Mission.PLAYER_TEAM: mission.def.player_color, Mission.ENEMY_TEAM: mission.def.enemy_color}
	control_view.setup(mission.control if mission != null else null, colors)
	minimap.show_control(mission.control if mission != null else null, colors)
	hud.setup(mission)
	_info.text = ""


## Put `count` units of one type on the free cells nearest to a cell.
static func spawn_squad(p_world: SimWorld, type: UnitType, team: int, near: Vector2i, count: int) -> Array[SimUnit]:
	return p_world.add_group(type, team, near, count)


# --- the simulation clock ------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	_message_left = maxf(0.0, _message_left - delta)
	if not is_over():
		_tick_time += delta
		var ticks := 0
		while _tick_time >= SimWorld.TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
			if mission != null:
				mission.tick()
			else:
				world.tick()
			_tick_time -= SimWorld.TICK_SECONDS
			ticks += 1
		if ticks == MAX_TICKS_PER_FRAME:
			_tick_time = 0.0
		units_view.alpha = _tick_time / SimWorld.TICK_SECONDS
	if world.removed_count != _seen_removed:
		_seen_removed = world.removed_count
		selection.prune(world)
	shroud_view.refresh()

	var mouse := get_viewport().get_mouse_position()
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if mouse.distance_to(_drag_start_screen) >= CLICK_SLOP:
				drag_box.show_rect(Rect2(_drag_start_map - camera.position, mouse - (_drag_start_map - camera.position)))
		else:
			_finish_drag(mouse, Input.is_key_pressed(KEY_SHIFT))
	_update_info(mouse)
	if mission != null:
		if mission.player_commander() == null:
			hints.note(&"ability")          # nobody left to use it
		hud.refresh(mission, hint_text())
		if mission.is_over() and not _result_shown:
			_show_result()


func _show_result() -> void:
	_result_shown = true
	set_mode(Mode.NORMAL)
	_dragging = false
	drag_box.hide_rect()
	hud.show_result(mission)


# --- input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event.is_action_pressed("ui_cancel"):
		if mode != Mode.NORMAL:
			set_mode(Mode.NORMAL)
		else:
			back_to_title()
		return
	if is_over():
		return
	var button := event as InputEventMouseButton
	if button != null and in_map_area(button.position):
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				if mode != Mode.NORMAL:
					command_click(screen_to_map(button.position))
				else:
					_dragging = true
					_drag_start_screen = button.position
					_drag_start_map = screen_to_map(button.position)
			elif _dragging:
				_finish_drag(button.position, button.shift_pressed)
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			if mode != Mode.NORMAL:
				set_mode(Mode.NORMAL)
			else:
				order_at(screen_to_map(button.position))
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		press_group_key(key.keycode - KEY_0, key.ctrl_pressed)
	elif key.keycode == KEY_A:
		begin_attack_move()
	elif key.keycode == KEY_S:
		order_stop()
	elif key.keycode == KEY_Q:
		begin_ability()


func _on_command(command: StringName) -> void:
	if is_over():
		return
	match command:
		&"attack": begin_attack_move()
		&"stop": order_stop()
		&"ability": begin_ability()


func _on_selection_changed() -> void:
	if hints != null and not selection.is_empty():
		hints.note(&"select")


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


# --- orders ------------------------------------------------------------------------

## Switch what a left click on the map does.
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	Input.set_default_cursor_shape(Input.CURSOR_ARROW if mode == Mode.NORMAL else Input.CURSOR_CROSS)


## A right click on the map: attack the enemy there, or walk there if there is none.
func order_at(map_point: Vector2) -> void:
	if selection.is_empty() or is_over():
		return
	var enemy := UnitsView.enemy_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
	if enemy != null:
		order_attack_unit(enemy.id)
	else:
		order_move_to(map_point)


## Send the selected units to a point on the map. They ignore enemies on the way.
func order_move_to(map_point: Vector2) -> void:
	if selection.is_empty() or is_over():
		return
	var cell := MapData.cell_at_pixel(map_point)
	if not map.in_bounds(cell):
		return
	world.order_move(selection.ids, cell)
	units_view.add_move_marker(map_point)
	if hints != null:
		hints.note(&"move")


## Send the selected units to a point on the map, fighting what they meet on the way.
func order_attack_move_to(map_point: Vector2) -> void:
	if selection.is_empty() or is_over():
		return
	var cell := MapData.cell_at_pixel(map_point)
	if not map.in_bounds(cell):
		return
	world.order_attack_move(selection.ids, cell)
	units_view.add_attack_move_marker(map_point)
	if hints != null:
		hints.note(&"attack")


## Send the selected units after one enemy unit.
func order_attack_unit(unit_id: int) -> void:
	if selection.is_empty() or is_over() or world.get_unit(unit_id) == null:
		return
	world.order_attack(selection.ids, unit_id)
	units_view.add_target_marker(unit_id)
	if hints != null:
		hints.note(&"attack")


## Stop the selected units where they are.
func order_stop() -> void:
	if not is_over():
		world.order_stop(selection.ids)


## A or the Attack button: the next left click on the map is an attack-move order.
func begin_attack_move() -> void:
	if is_over():
		return
	if selection.is_empty():
		say("Select some units first.")
		return
	set_mode(Mode.ATTACK_MOVE)


## Q or the ability button: the next left click picks the unit the commander's ability is used on.
func begin_ability() -> void:
	if is_over():
		return
	var hero := ability_unit()
	if hero == null:
		say("You have no commander to do that.")
		return
	if hero.ability_ticks_left > 0:
		say("%s is not ready yet." % hero.type.ability.display_name)
		return
	set_mode(Mode.ABILITY)


## A left click on the map after A or Q.
func command_click(map_point: Vector2) -> void:
	match mode:
		Mode.ATTACK_MOVE:
			var enemy := UnitsView.enemy_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
			if enemy != null:
				order_attack_unit(enemy.id)
			else:
				order_attack_move_to(map_point)
			set_mode(Mode.NORMAL)
		Mode.ABILITY:
			var target := UnitsView.unit_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
			if target == null:
				say("Pick one of your own units.")
			elif use_ability_on(target.id):
				set_mode(Mode.NORMAL)


## Have the commander use its ability on a unit. Returns false, and tells the player why, if it cannot.
func use_ability_on(unit_id: int) -> bool:
	var hero := ability_unit()
	if hero == null or is_over():
		return false
	var problem := world.ability_problem(hero.id, unit_id)
	if problem != "":
		say(problem + ".")
		return false
	world.order_ability(hero.id, unit_id)
	units_view.add_target_marker(unit_id, true)
	if hints != null:
		hints.note(&"ability")
	return true


## The unit whose ability Q triggers: the player's commander in a mission,
## otherwise the first selected hero. Null if there is none.
func ability_unit() -> SimUnit:
	if mission != null:
		return mission.player_commander()
	for id in selection.ids:
		var unit := world.get_unit(id)
		if unit != null and unit.type.ability != null:
			return unit
	return null


## Show a short message in the hint box.
func say(message: String) -> void:
	_message = message
	_message_left = MESSAGE_SECONDS


## What the hint box shows now: what the next click does, a recent message, or the mission's hint.
func hint_text() -> String:
	match mode:
		Mode.ATTACK_MOVE:
			return "Attack-move: left-click where to go, or an enemy to attack. Right-click cancels."
		Mode.ABILITY:
			var hero := ability_unit()
			var ability_name := hero.type.ability.display_name if hero != null else "Ability"
			return "%s: left-click one of your wounded units. Right-click cancels." % ability_name
	if _message_left > 0.0:
		return _message
	return hints.text(mission.def) if hints != null and mission != null else ""


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

## What the sidebar says about one unit.
static func describe_unit(unit: SimUnit) -> String:
	var type := unit.type
	var text := "%s\n%s\nHealth %d / %d" % [type.display_name, type.role, unit.health, type.max_health]
	if type.attack_damage > 0:
		text += "\nAttack %d   Range %d" % [type.attack_damage, type.attack_range]
	if type.ability != null:
		var wait := ceili(unit.ability_ticks_left * SimWorld.TICK_SECONDS)
		text += "\n%s: %s" % [type.ability.display_name, "ready" if wait == 0 else "%d s" % wait]
	return text


## What the sidebar says about the current selection. "" if nothing is selected.
static func describe_selection(p_world: SimWorld, p_selection: Selection) -> String:
	if p_selection.is_empty():
		return ""
	if p_selection.ids.size() == 1:
		var unit := p_world.get_unit(p_selection.ids[0])
		return describe_unit(unit) if unit != null else ""
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
		var point := screen_to_map(mouse)
		var cell := MapData.cell_at_pixel(point)
		var enemy := UnitsView.enemy_at_point(world, point, SimWorld.PLAYER_TEAM, units_view.alpha)
		if enemy != null:
			text = describe_unit(enemy)
		elif world.shroud_for(SimWorld.PLAYER_TEAM).is_explored(cell):
			text = describe_cell(map, cell)
		elif map.in_bounds(cell):
			text = "Cell %d, %d\nUnexplored" % [cell.x, cell.y]
	if text != _info.text:
		_info.text = text
