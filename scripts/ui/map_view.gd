class_name MapView
extends Node2D
## The in-game screen: the map, the units, the shroud, the camera, the sidebar
## with the minimap and, when a mission is being played, the mission HUD. It
## runs the simulation at a fixed pace and turns mouse and keyboard input into
## selections and orders.
##
## Controls: left click selects a unit, dragging selects every unit in the box
## (hold Shift to add to the selection). Right click sends the selected units
## to that spot, or at the enemy unit or building under the mouse; harvesters right-clicked onto
## the Orichalcum rock start harvesting, and onto their refinery unload; units sent to a trailer
## whose harvester is destroyed take the Orichalcum in it. F then left click is
## attack-move; X stops; Q then left click on one of your units uses the
## commander's ability on it. Ctrl+1..9 stores the selection as a group, 1..9
## selects the group again and pressing the number twice jumps the camera to it.
## WASD, the arrow keys, the screen edges and the middle mouse button scroll
## the map (see MapCamera). In a mission with a base the build menu in the
## sidebar queues buildings and units; a finished building is placed with a
## left click on the map. Esc or P pauses a mission and shows the pause menu.

## What a left click on the map does.
enum Mode {
	## Select.
	NORMAL,
	## Give an attack-move order (after F or the Attack button).
	ATTACK_MOVE,
	## Pick the unit for the commander's ability (after Q or its button).
	ABILITY,
	## Put the finished building on the map.
	PLACE,
}

const SCREEN_SIZE := Vector2(960, 540)
## The sidebar's width and the top bar's height (see HudStyle): the map is shown in the rest.
const SIDEBAR_WIDTH := 960.0 - HudStyle.SIDEBAR_X
const MAP_TOP := HudStyle.TOP
const TITLE_SCENE := "res://scenes/main.tscn"
## Moving the mouse less than this (in pixels) between press and release is a click, not a drag.
const CLICK_SLOP := 4.0
## Two presses of a group number within this many seconds jump the camera to the group.
const DOUBLE_TAP_SECONDS := 0.4
## The simulation never runs more than this many ticks in one frame (after a long stall it slows down instead).
const MAX_TICKS_PER_FRAME := 5
## How long a message such as "Mend is not ready yet" stays in the hint box.
const MESSAGE_SECONDS := 2.5
## How long a mission's message (see Mission.messages) stays in the hint box, in game seconds.
const MISSION_MESSAGE_SECONDS := 8.0

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
## Is the mission paused (Esc or P)? See set_paused().
var paused := false
## The key of the ability waiting for its target (Mode.ABILITY).
var _ability_key := "Q"
## What the card shows, so it is only rebuilt when that changes.
var _shown_info := ""

@onready var terrain: TerrainView = $Terrain
@onready var deposit_view: DepositView = $Deposits
@onready var control_view: ControlView = $ControlArea
@onready var buildings_view: BuildingsView = $Buildings
@onready var units_view: UnitsView = $Units
@onready var shroud_view: ShroudView = $Shroud
@onready var camera: MapCamera = $Camera
@onready var minimap: Minimap = $Hud/Minimap
@onready var drag_box: DragBox = $Hud/DragBox
@onready var hud: MissionHud = $Hud/MissionHud

## Shows where the building being placed would stand. Made in _ready().
var placement_view: PlacementView


func _ready() -> void:
	# Keep the mouse inside the window, so pushing it against a screen edge scrolls instead of leaving.
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	hud.command_pressed.connect(_on_command)
	hud.again_pressed.connect(restart_mission)
	hud.title_pressed.connect(back_to_title)
	hud.resume_pressed.connect(set_paused.bind(false))
	hud.menu_pressed.connect(set_paused.bind(true))
	hud.hero_pressed.connect(_on_hero_pressed)
	hud.build_panel.build_pressed.connect(queue_build)
	hud.build_panel.cancel_pressed.connect(cancel_build)
	hud.build_panel.place_pressed.connect(begin_placement)
	placement_view = PlacementView.new()
	add_child(placement_view)
	move_child(placement_view, shroud_view.get_index() + 1)
	placement_view.stop()
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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


## Start a mission: its map, both forces, the control point and the scripted opponent.
func show_mission(def: MissionDef) -> void:
	mission = Mission.new(def)
	hints = MissionHints.new(mission)
	var focus := Vector2(def.map.get_pixel_size()) / 2.0
	var commander := mission.player_commander()
	var refinery := mission.world.get_building(mission.player_refinery_id)
	if commander != null:
		focus = MapData.cell_center(commander.cell)
	elif refinery != null:
		focus = refinery.center() * MapData.CELL_SIZE
	elif not def.map.starts.is_empty():
		focus = MapData.cell_center(def.map.starts[0])
	_attach(def.map, mission.world, focus)


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


## Is the game standing still, because the mission is over or paused? No
## orders are taken then.
func is_halted() -> bool:
	return paused or is_over()


## Pause or carry on with the mission. Paused, the simulation stands still,
## no orders are taken and the pause menu is shown. Only a mission that is
## being played can be paused.
func set_paused(on: bool) -> void:
	on = on and mission != null and not is_over()
	if on == paused:
		return
	paused = on
	camera.set_process(not paused)
	if paused:
		set_mode(Mode.NORMAL)
		_dragging = false
		drag_box.hide_rect()
		hud.show_pause()
	else:
		hud.hide_pause()


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
	paused = false
	camera.set_process(true)
	drag_box.hide_rect()
	terrain.show_map(map)
	deposit_view.setup(world)
	buildings_view.setup(world, selection)
	units_view.setup(world, selection)
	shroud_view.setup(world.shroud_for(SimWorld.PLAYER_TEAM))
	var view_size := Vector2(SCREEN_SIZE.x - SIDEBAR_WIDTH, SCREEN_SIZE.y - MAP_TOP)
	camera.offset = Vector2(0, -MAP_TOP)      # the map starts under the top bar
	camera.setup(Vector2(map.get_pixel_size()), view_size, SCREEN_SIZE)
	camera.center_on(focus)
	minimap.setup(map, camera, world)
	var colors := {}
	var control: ControlPoint = null        # nothing to hold in a practice mission or a skirmish
	if mission != null and mission.def.has_control():
		colors = {Mission.PLAYER_TEAM: mission.def.player_color, Mission.ENEMY_TEAM: mission.def.enemy_color}
		control = mission.control
	control_view.setup(control, colors)
	minimap.show_control(control, colors)
	var size := map.get_size()
	hud.setup(mission, "%s  %dx%d" % [map.display_name, size.x, size.y])
	_shown_info = "-"


## Put `count` units of one type on the free cells nearest to a cell.
static func spawn_squad(p_world: SimWorld, type: UnitType, team: int, near: Vector2i, count: int) -> Array[SimUnit]:
	return p_world.add_group(type, team, near, count)


# --- the simulation clock ------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	_message_left = maxf(0.0, _message_left - delta)
	if not is_halted():
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
	deposit_view.refresh()

	var mouse := get_viewport().get_mouse_position()
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if mouse.distance_to(_drag_start_screen) >= CLICK_SLOP:
				drag_box.show_rect(Rect2(map_to_screen(_drag_start_map), mouse - map_to_screen(_drag_start_map)))
		else:
			_finish_drag(mouse, Input.is_key_pressed(KEY_SHIFT))
	_update_info(mouse)
	if mode == Mode.PLACE:
		var ready := world.production.ready_building(SimWorld.PLAYER_TEAM)
		if ready == null or is_over():
			set_mode(Mode.NORMAL)
		elif in_map_area(mouse):
			placement_view.show_at(world, ready, screen_to_map(mouse))
		else:
			placement_view.stop()
	if mission != null:
		var chosen := world.get_building(selection.building_id) if selection.building_id != 0 else null
		hud.set_selected_building(chosen if chosen != null and chosen.team == SimWorld.PLAYER_TEAM else null)
		var prompt := prompt_text()
		if prompt != "":
			hud.refresh(mission, prompt)
		else:
			hud.refresh(mission, hints.text() if hints != null else "", fresh_message())
		hud.show_selected(selection.ids)
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
	# Esc first leaves attack-move, the ability or placing. Otherwise, in a
	# mission being played, it pauses (and Esc again carries on); on the
	# result screen, or with no mission, it goes back to the title screen.
	if event.is_action_pressed("ui_cancel"):
		if mode != Mode.NORMAL:
			set_mode(Mode.NORMAL)
		elif mission != null and not is_over():
			set_paused(not paused)
		else:
			back_to_title()
		return
	var pause_key := event as InputEventKey
	if pause_key != null and pause_key.pressed and not pause_key.echo and pause_key.keycode == KEY_P:
		set_paused(not paused)
		return
	if is_halted():
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
	elif key.keycode == KEY_F:
		begin_attack_move()
	elif key.keycode == KEY_X:
		order_stop()
	elif key.keycode == KEY_Q:
		begin_ability("Q")
	elif key.keycode == KEY_E:
		begin_ability("E")
	elif key.keycode == KEY_R:
		toggle_repair()
	elif key.keycode == KEY_O:
		hud.toggle_objectives()


func _on_command(command: StringName) -> void:
	if is_halted():
		return
	match command:
		&"attack": begin_attack_move()
		&"stop": order_stop()
		&"ability": begin_ability("Q")
		&"repair": toggle_repair()
		_:
			if String(command).begins_with("ability_"):
				begin_ability(String(command).trim_prefix("ability_"))


func _on_selection_changed() -> void:
	if hints != null and not selection.ids.is_empty():
		hints.note(&"select")


## Is this screen position over the map (not the top bar or the sidebar)?
static func in_map_area(screen_point: Vector2) -> bool:
	return screen_point.x >= 0 and screen_point.y >= MAP_TOP \
			and screen_point.x < SCREEN_SIZE.x - SIDEBAR_WIDTH and screen_point.y < SCREEN_SIZE.y


func screen_to_map(screen_point: Vector2) -> Vector2:
	return camera.position + screen_point - Vector2(0, MAP_TOP)


func map_to_screen(map_point: Vector2) -> Vector2:
	return map_point - camera.position + Vector2(0, MAP_TOP)


## A hero's portrait was clicked: select the hero, and on a double click go there.
func _on_hero_pressed(unit_id: int, twice: bool) -> void:
	if is_halted():
		return
	var hero := world.get_unit(unit_id)
	if hero == null:
		return
	selection.set_ids([unit_id])
	if twice:
		camera.center_on(UnitsView.feet_position(hero))


func _finish_drag(screen_point: Vector2, add: bool) -> void:
	_dragging = false
	drag_box.hide_rect()
	if screen_point.distance_to(_drag_start_screen) < CLICK_SLOP:
		click_select(screen_to_map(screen_point), add)
	else:
		box_select(Rect2(_drag_start_map, screen_to_map(screen_point) - _drag_start_map), add)


## A click on the map: select the unit there, or else the player's building
## there. With `add`, add the unit to or take it out of the selection.
func click_select(map_point: Vector2, add := false) -> void:
	var unit := UnitsView.unit_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
	if unit == null:
		var building := BuildingsView.building_at_point(world, map_point, SimWorld.PLAYER_TEAM)
		if building != null and building.team == SimWorld.PLAYER_TEAM and not add:
			selection.set_building(building.id)
		elif not add:
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
	if mode != Mode.PLACE and placement_view != null:
		placement_view.stop()


## A right click on the map: attack the enemy unit or building there, or
## walk there if there is none. Selected harvesters start work if the click is
## on a deposit, and go to unload if it is on their side's refinery.
func order_at(map_point: Vector2) -> void:
	if selection.ids.is_empty() or is_halted():
		return
	var enemy := UnitsView.enemy_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
	if enemy != null:
		order_attack_unit(enemy.id)
		return
	var site := enemy_building_at(map_point)
	if site != null and not _selected_others().is_empty():
		order_attack_building(site.id)
		return
	var cell := MapData.cell_at_pixel(map_point)
	if not selected_harvesters().is_empty() and world.shroud_for(SimWorld.PLAYER_TEAM).is_explored(cell):
		if world.deposit_at(cell) != null:
			order_harvest_at(map_point)
			return
		var building := world.building_at(cell)
		if building != null and building.team == SimWorld.PLAYER_TEAM and building.type.is_refinery:
			order_unload_at(map_point)
			return
	order_move_to(map_point)


## Ids of the selected units that are harvesters.
func selected_harvesters() -> Array[int]:
	var out: Array[int] = []
	for id in selection.ids:
		var unit := world.get_unit(id)
		if unit != null and unit.type.is_harvester():
			out.append(id)
	return out


## Ids of the selected units that are not harvesters.
func _selected_others() -> Array[int]:
	var out: Array[int] = []
	for id in selection.ids:
		var unit := world.get_unit(id)
		if unit != null and not unit.type.is_harvester():
			out.append(id)
	return out


## Send the selected harvesters to work the deposit at a point on the map.
## Other selected units walk there. Returns false if no harvester set off.
func order_harvest_at(map_point: Vector2) -> bool:
	var harvesters := selected_harvesters()
	var cell := MapData.cell_at_pixel(map_point)
	var deposit := world.deposit_at(cell)
	if harvesters.is_empty() or deposit == null or is_halted():
		return false
	if deposit.is_empty():
		say("That rock has no Orichalcum left.")
		return false
	world.order_harvest(harvesters, cell)
	world.order_move(_selected_others(), cell)
	units_view.add_harvest_marker(map_point)
	if hints != null:
		hints.note(&"harvest")
	return true


## Send the selected harvesters to unload at the player's refinery at a point
## on the map. Other selected units walk there. Returns false if none set off.
func order_unload_at(map_point: Vector2) -> bool:
	var harvesters := selected_harvesters()
	var cell := MapData.cell_at_pixel(map_point)
	var building := world.building_at(cell)
	if harvesters.is_empty() or building == null or is_halted():
		return false
	if not world.order_unload(harvesters, building.id):
		return false
	world.order_move(_selected_others(), cell)
	units_view.add_harvest_marker(map_point)
	return true


## Send the selected units to a point on the map. They ignore enemies on the way.
func order_move_to(map_point: Vector2) -> void:
	if selection.ids.is_empty() or is_halted():
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
	if selection.ids.is_empty() or is_halted():
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
	if selection.ids.is_empty() or is_halted() or world.get_unit(unit_id) == null:
		return
	world.order_attack(selection.ids, unit_id)
	units_view.add_target_marker(unit_id)
	if hints != null:
		hints.note(&"attack")


## Send the selected units to attack an enemy building. Harvesters do not
## attack buildings: they stay where they are.
func order_attack_building(building_id: int) -> void:
	var building := world.get_building(building_id)
	if selection.ids.is_empty() or is_halted() or building == null or building.team == SimWorld.PLAYER_TEAM:
		return
	world.order_attack(selection.ids, building_id)
	buildings_view.mark(building_id)
	if hints != null:
		hints.note(&"attack")


## The enemy building under a point on the map that the player has seen, or null.
func enemy_building_at(map_point: Vector2) -> SimBuilding:
	var building := BuildingsView.building_at_point(world, map_point, SimWorld.PLAYER_TEAM)
	return building if building != null and building.team != SimWorld.PLAYER_TEAM else null


## Stop the selected units where they are.
func order_stop() -> void:
	if not is_halted():
		world.order_stop(selection.ids)


## F or the Attack button: the next left click on the map is an attack-move order.
func begin_attack_move() -> void:
	if is_halted():
		return
	if selection.ids.is_empty():
		say("Select some units first.")
		return
	set_mode(Mode.ATTACK_MOVE)


## An ability key (Q, E) or its button. An ability used on one unit waits for
## the left click that picks the unit; one used around the hero is used at once.
func begin_ability(key := "Q") -> void:
	if is_halted():
		return
	var hero := ability_unit(key)
	if hero == null:
		say("You have no hero who can do that.")
		return
	var ability := hero.type.ability
	if hero.ability_ticks_left > 0:
		say("%s is not ready yet." % ability.display_name)
		return
	if not ability.needs_target():
		use_ability_on(hero.id, key)
		return
	_ability_key = key
	set_mode(Mode.ABILITY)


## A left click on the map after F or Q.
func command_click(map_point: Vector2) -> void:
	match mode:
		Mode.ATTACK_MOVE:
			var enemy := UnitsView.enemy_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
			var site := enemy_building_at(map_point)
			if enemy != null:
				order_attack_unit(enemy.id)
			elif site != null:
				order_attack_building(site.id)
			else:
				order_attack_move_to(map_point)
			set_mode(Mode.NORMAL)
		Mode.ABILITY:
			var target := UnitsView.unit_at_point(world, map_point, SimWorld.PLAYER_TEAM, units_view.alpha)
			if target == null:
				say("Pick one of your own units.")
			elif use_ability_on(target.id):
				set_mode(Mode.NORMAL)
		Mode.PLACE:
			place_at(map_point)


# --- building ------------------------------------------------------------------------

## A click in the build menu: add a building or a unit to a queue of the
## player's. Clicking the building that is ready to be placed starts placing
## it instead. Returns false, and tells the player why, if it cannot be queued.
func queue_build(key: StringName, item: Resource) -> bool:
	if world == null or is_halted():
		return false
	var production := world.production
	if key == Production.BUILDINGS and production.ready_building(SimWorld.PLAYER_TEAM) == item:
		begin_placement()
		return true
	var problem := production.problem(SimWorld.PLAYER_TEAM, key, item)
	if problem != "":
		say(problem + ".")
		return false
	production.queue(SimWorld.PLAYER_TEAM, key, item)
	if hints != null:
		hints.note(&"build" if key == Production.BUILDINGS else &"train")
	return true


## Cancel in the build menu: take the last item out of a queue of the
## player's. What was paid for it comes back.
func cancel_build(key: StringName) -> void:
	if world == null or is_halted():
		return
	world.production.cancel(SimWorld.PLAYER_TEAM, key)
	if mode == Mode.PLACE and world.production.ready_building(SimWorld.PLAYER_TEAM) == null:
		set_mode(Mode.NORMAL)


## The next left click on the map puts the finished building there.
func begin_placement() -> void:
	if world == null or is_halted():
		return
	if world.production.ready_building(SimWorld.PLAYER_TEAM) == null:
		say("No building is ready to be placed.")
		return
	set_mode(Mode.PLACE)


## Put the finished building on the map with its middle at a point. Returns
## false, and tells the player why, if it cannot stand there.
func place_at(map_point: Vector2) -> bool:
	var production := world.production
	var type := production.ready_building(SimWorld.PLAYER_TEAM)
	if type == null or is_halted():
		return false
	var cell := PlacementView.cell_for(type, map_point)
	if production.place(SimWorld.PLAYER_TEAM, cell) == null:
		say("It cannot stand there. Buildings need free building ground under every cell.")
		return false
	set_mode(Mode.NORMAL)
	if hints != null:
		hints.note(&"place")
	return true


## Have the hero whose ability has this key use it on a unit (for an ability
## used around the hero, on the hero itself). Returns false, and tells the
## player why, if it cannot.
func use_ability_on(unit_id: int, key := "") -> bool:
	var hero := ability_unit(key if key != "" else _ability_key)
	if hero == null or is_halted():
		return false
	var problem := world.ability_problem(hero.id, unit_id)
	if problem != "":
		say(problem + ".")
		return false
	world.order_ability(hero.id, unit_id)
	if hero.type.ability.needs_target():
		units_view.add_target_marker(unit_id, true)
	if hints != null:
		hints.note(&"ability")
	return true


## The hero whose active ability has this key: in a mission, the player's
## living hero with it; otherwise the first selected one. Null if there is none.
func ability_unit(key := "Q") -> SimUnit:
	var candidates: Array[SimUnit] = []
	if mission != null:
		candidates = mission.player_heroes()
	else:
		for id in selection.ids:
			var unit := world.get_unit(id)
			if unit != null:
				candidates.append(unit)
	for unit in candidates:
		if unit.type.ability != null and unit.type.ability.key == key:
			return unit
	return null


## R or the Repair button: start or stop repairing the selected building.
func toggle_repair() -> void:
	if is_halted() or selection.building_id == 0:
		return
	var building := world.get_building(selection.building_id)
	if building == null or building.team != SimWorld.PLAYER_TEAM:
		return
	if not building.repairing and building.health >= building.type.max_health:
		say("The %s is not damaged." % building.type.display_name)
		return
	if not building.repairing and world.stored_for(SimWorld.PLAYER_TEAM) <= 0:
		say("Repairs cost Orichalcum, and the store is empty.")
	world.order_repair(building.id, not building.repairing)
	if hints != null and building.repairing:
		hints.note(&"repair")


## Show a short message in the hint box.
func say(message: String) -> void:
	_message = message
	_message_left = MESSAGE_SECONDS


## What the message box shows now: what the next click does, a recent
## message, the mission's latest message while it is fresh, or the hint.
func hint_text() -> String:
	var prompt := prompt_text()
	if prompt != "":
		return prompt
	var said := mission_message_text()
	if said != "":
		return said
	return hints.text() if hints != null and mission != null else ""


## What the next click does, or a short message such as "Mend is not ready
## yet" while it is recent; "" otherwise.
func prompt_text() -> String:
	match mode:
		Mode.ATTACK_MOVE:
			return "Attack-move: left-click where to go, or an enemy unit or building to attack. Right-click cancels."
		Mode.ABILITY:
			var hero := ability_unit()
			var ability_name := hero.type.ability.display_name if hero != null else "Ability"
			return "%s: left-click one of your wounded units. Right-click cancels." % ability_name
		Mode.PLACE:
			if _message_left > 0.0:
				return _message     # why the last click did not place it
			var ready := world.production.ready_building(SimWorld.PLAYER_TEAM)
			var ready_name := ready.display_name if ready != null else "building"
			return "Placing the %s: left-click building ground where every square is green. Right-click cancels." % ready_name
	if _message_left > 0.0:
		return _message
	return ""


## The mission's latest message while it is fresh (MISSION_MESSAGE_SECONDS),
## or an empty dictionary. See Mission.messages.
func fresh_message() -> Dictionary:
	if mission == null or mission.messages.is_empty():
		return {}
	var last: Dictionary = mission.messages.back()
	if mission.world.tick_count - int(last["tick"]) > roundi(MISSION_MESSAGE_SECONDS * SimWorld.TICKS_PER_SECOND):
		return {}
	return last


## The mission's latest message while it is fresh, in words, e.g. "Field
## Commander: They are coming.", or "".
func mission_message_text() -> String:
	var last := fresh_message()
	if last.is_empty():
		return ""
	return "%s: %s" % [last["speaker"], last["text"]] if last["speaker"] != "" else String(last["text"])


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
static func describe_unit(unit: SimUnit, p_world: SimWorld = null) -> String:
	var type := unit.type
	var text := "%s\n%s\nHealth %d / %d" % [type.display_name, type.role, unit.health, type.max_health]
	if type.is_harvester():
		text += "\nRobot: attack %d, armour %d%%" % [type.attack_damage, type.robot_armor]
	elif type.attack_damage > 0:
		text += "\nAttack %d   Range %d" % [type.attack_damage, type.attack_range]
	if type.ability != null:
		var wait := ceili(unit.ability_ticks_left * SimWorld.TICK_SECONDS)
		text += "\n%s (%s): %s" % [type.ability.display_name, type.ability.key, "ready" if wait == 0 else "%d s" % wait]
	if type.passive != null:
		text += "\n%s (always on)" % type.passive.display_name
	if p_world != null and p_world.haste_of(unit) > 1.0:
		text += "\nEncouraged: %d%% faster" % roundi((p_world.haste_of(unit) - 1.0) * 100.0)
	if type.is_harvester():
		text += "\nCargo %d / %d" % [unit.cargo, type.cargo_capacity]
		if unit.trailer_id != 0:
			text += "   Pack %d / %d" % [unit.pack, type.pack_capacity]
		text += "\n" + job_text(unit, p_world)
	return text


## What a harvester is doing, in words. With the world given it can tell a
## harvester that is unloading from one that waits at a full store.
static func job_text(unit: SimUnit, p_world: SimWorld = null) -> String:
	if unit.leaving:
		return "Going back to its trailer"
	match unit.job:
		SimUnit.Job.TO_DEPOSIT: return "Driving to the rock"
		SimUnit.Job.DEPLOY: return "Unfolding"
		SimUnit.Job.TO_ROCK: return "Walking to the rock"
		SimUnit.Job.EXTRACT: return "Digging"
		SimUnit.Job.TO_TRAILER: return "Carrying its pack to the trailer"
		SimUnit.Job.LOAD: return "Filling the trailer"
		SimUnit.Job.PACK: return "Folding up"
		SimUnit.Job.TO_REFINERY: return "Taking its load to the refinery" if unit.refinery_id != 0 else "No refinery to unload at"
		SimUnit.Job.UNLOAD:
			return "Waiting: the store is full" if p_world != null and p_world.is_waiting_for_room(unit) else "Unloading"
		SimUnit.Job.GUARD: return "Guarding its trailer"
	return "Waiting for orders" if unit.order == SimUnit.Order.NONE else "On its way"


## What the sidebar says about a trailer standing on its own.
static func describe_trailer(p_world: SimWorld, trailer: SimTrailer) -> String:
	var text := "Trailer\n%s\nCargo %d / %d" % [trailer.type.role, p_world.trailer_cargo(trailer), trailer.type.cargo_capacity]
	if not trailer.is_orphan():
		return text + "\nCannot be attacked"
	if trailer.team == SimWorld.PLAYER_TEAM:
		return text + "\nIts harvester is destroyed.\nAn enemy that reaches it\ntakes the Orichalcum."
	return text + "\nIts harvester is destroyed.\nSend a unit up to it to\ntake the Orichalcum."


## What the sidebar says about a building.
static func describe_building(p_world: SimWorld, building: SimBuilding) -> String:
	var type := building.type
	var text := "%s\n%s\nHealth %d / %d" % [type.display_name, type.role, building.health, type.max_health]
	if type.storage > 0:
		text += "\nStores up to %d" % type.storage
		text += "\nIn store: %d" % p_world.stored_for(building.team)
	if type.power > 0:
		text += "\nMakes %d power" % type.power
	elif type.power < 0:
		text += "\nUses %d power" % -type.power
	if not type.builds.is_empty():
		text += "\nConstructs buildings"
	for unit_type: UnitType in type.produces:
		text += "\nProduces: %s" % unit_type.display_name
	return text


## What the sidebar says about a selected building of the player's: what
## describe_building() says, and what repairing it costs.
static func describe_own_building(p_world: SimWorld, building: SimBuilding) -> String:
	var lines := describe_building(p_world, building).split("\n")
	var repair := ""
	if building.repairing:
		repair = "Repairing: %d Orichalcum to go" % SimWorld.repair_cost(building)
	elif building.health < building.type.max_health:
		repair = "Repair (R): %d Orichalcum" % SimWorld.repair_cost(building)
	if repair != "":
		lines.insert(3, repair)         # under the health, where the sidebar has room for it
	return "\n".join(lines)


## What the sidebar says about a cell of the world: the building on it, or
## its terrain, with the Orichalcum in it if it is part of a deposit.
static func describe_spot(p_world: SimWorld, cell: Vector2i) -> String:
	var building := p_world.building_at(cell)
	if building != null:
		return describe_building(p_world, building)
	var trailer := p_world.trailer_at(cell)
	if trailer != null:
		return describe_trailer(p_world, trailer)
	var text := describe_cell(p_world.map, cell)
	var deposit := p_world.deposit_at(cell)
	if deposit != null:
		text += "\nOrichalcum here: %d\nIn the whole rock: %d" % [deposit.left_at(cell), deposit.amount]
	return text


## What the sidebar says about the current selection. "" if nothing is selected.
static func describe_selection(p_world: SimWorld, p_selection: Selection) -> String:
	if p_selection.building_id != 0:
		var building := p_world.get_building(p_selection.building_id)
		return describe_own_building(p_world, building) if building != null else ""
	if p_selection.ids.is_empty():
		return ""
	if p_selection.ids.size() == 1:
		var unit := p_world.get_unit(p_selection.ids[0])
		return describe_unit(unit, p_world) if unit != null else ""
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
			text = describe_unit(enemy, world)
		elif world.shroud_for(SimWorld.PLAYER_TEAM).is_explored(cell):
			text = describe_spot(world, cell)
		elif map.in_bounds(cell):
			text = "Cell %d, %d\nUnexplored" % [cell.x, cell.y]
	if text == _shown_info:
		return
	_shown_info = text
	var picture: Texture2D = null
	var health := -1.0
	var thing: Variant = _info_subject(mouse)
	if thing is SimUnit:
		var unit := thing as SimUnit
		picture = MissionHud.portrait_of(unit.type)
		health = float(unit.health) / unit.type.max_health
	elif thing is SimBuilding:
		var building := thing as SimBuilding
		picture = building.type.sprite
		health = float(building.health) / building.type.max_health
	hud.show_info(text, picture, health)


## The unit or building the card is about: the one selected, or the enemy or
## building under the mouse; null for anything else.
func _info_subject(mouse: Vector2) -> Variant:
	if selection.building_id != 0:
		return world.get_building(selection.building_id)
	if selection.ids.size() == 1:
		return world.get_unit(selection.ids[0])
	if not selection.ids.is_empty() or not in_map_area(mouse):
		return null
	var point := screen_to_map(mouse)
	var enemy := UnitsView.enemy_at_point(world, point, SimWorld.PLAYER_TEAM, units_view.alpha)
	if enemy != null:
		return enemy
	if world.shroud_for(SimWorld.PLAYER_TEAM).is_explored(MapData.cell_at_pixel(point)):
		return world.building_at(MapData.cell_at_pixel(point))
	return null
