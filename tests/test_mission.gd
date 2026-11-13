extends TestCase
## The control point, the win rule, the scripted opponent, Mission 1 from start
## to finish, the hints and the mission HUD.

const FOREST := "res://data/biomes/forest.tres"
const FOREST_MAP := "res://data/maps/forest_01.tres"
const GUARD := "res://data/units/blue_infantry.tres"
const LEGIONARY := "res://data/units/red_infantry.tres"
const MISSIONS := ["res://data/missions/first_claim_blue.tres", "res://data/missions/first_claim_red.tres"]
const MAP_SCENE := "res://scenes/map_view.tscn"
const PLAYER := Mission.PLAYER_TEAM
const ENEMY := Mission.ENEMY_TEAM


func _open(width: int, height: int) -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	var rows := []
	for y in height:
		rows.append(".".repeat(width))
	map.rows = PackedStringArray(rows)
	return SimWorld.new(map)


## A unit type that never attacks, for tests that only care where units stand.
func _bystander() -> UnitType:
	var type := UnitType.new()
	type.max_health = 50
	type.speed = 10.0
	return type


## Walk a unit to a cell and wait until it is there.
func _walk(world: SimWorld, unit: SimUnit, cell: Vector2i) -> void:
	world.order_move([unit.id], cell)
	for i in 400:
		if unit.cell == cell and unit.is_settled():
			return
		world.tick()


func _updates(control: ControlPoint, world: SimWorld, count: int) -> void:
	for i in count:
		control.update(world)


## A short version of Mission 1 on the real forest map: the two sides start
## close together on either side of the rock, with one troop each and no
## commander. `player_damage` and `enemy_damage` decide who wins a fight.
func _short_mission(player_damage: int, enemy_damage: int) -> MissionDef:
	var def := (load(MISSIONS[0]) as MissionDef).duplicate() as MissionDef
	var map := (load(FOREST_MAP) as MapData).duplicate() as MapData
	map.starts = [Vector2i(26, 26), Vector2i(38, 22)] as Array[Vector2i]
	def.map = map
	def.troop_count = 1
	def.player_commander = null
	def.enemy_commander = null
	def.player_troop = (load(GUARD) as UnitType).duplicate()
	def.player_troop.attack_damage = player_damage
	def.enemy_troop = (load(LEGIONARY) as UnitType).duplicate()
	def.enemy_troop.attack_damage = enemy_damage
	def.enemy_delay_seconds = 0.0
	return def


## Play a mission the way its hints teach: attack-move everyone to the rock,
## keep idle units going at the enemy, and have the commander heal the most
## badly wounded soldier whenever the ability is ready.
func _play(mission: Mission, max_seconds := 400) -> void:
	var world := mission.world
	var rally := ScriptedOpponent.rally_cell(world, mission.control, mission.def.map.starts[0])
	for tick in max_seconds * SimWorld.TICKS_PER_SECOND:
		if mission.is_over():
			return
		if tick % SimWorld.TICKS_PER_SECOND == 0:
			var commander := mission.player_commander()
			var idle: Array = []
			var worst: SimUnit = null
			for unit in world.units:
				if unit.team != PLAYER:
					continue
				if unit.order == SimUnit.Order.NONE and unit.target_id == 0 and not mission.control.contains(unit.cell):
					idle.append(unit.id)
				if unit != commander and unit.health <= unit.type.max_health - 30 and (worst == null or unit.health < worst.health):
					worst = unit
			if not idle.is_empty():
				world.order_attack_move(idle, rally)
			if commander != null and worst != null and commander.ability_ticks_left == 0:
				world.order_ability(commander.id, worst.id)
		mission.tick()


# --- the control point -------------------------------------------------------------

func test_control_area_is_round() -> void:
	var control := ControlPoint.new(Vector2(10, 10), 3.0, 1.0)
	check(control.contains(Vector2i(10, 10)), "the cell beside the middle is inside")
	check(control.contains(Vector2i(12, 10)), "a cell whose middle is 2.5 cells away is inside")
	check(not control.contains(Vector2i(13, 10)), "a cell whose middle is 3.5 cells away is not")
	check(not control.contains(Vector2i(12, 12)), "nor is the corner of the square around the circle")
	check_eq(control.hold_ticks_needed, 20, "one second is 20 ticks")


func test_control_point_rules() -> void:
	var world := _open(24, 20)
	var control := ControlPoint.new(Vector2(10, 10), 3.0, 1.0)
	var blue := world.add_unit(_bystander(), PLAYER, Vector2i(20, 2))
	var red := world.add_unit(_bystander(), ENEMY, Vector2i(20, 18))
	_updates(control, world, 5)
	check_eq(control.owner, ControlPoint.NOBODY, "an empty area belongs to nobody")
	check_eq(control.hold_ticks, 0, "and no time counts")

	_walk(world, blue, Vector2i(9, 9))
	_updates(control, world, 10)
	check_eq(control.holder, PLAYER, "blue alone inside holds the area")
	check_eq(control.hold_ticks, 10, "its time counts up")
	check(is_equal_approx(control.progress(), 0.5), "half the hold time has passed")
	check(is_equal_approx(control.seconds_left(), 0.5), "half a second to go")
	check(not control.is_won(), "not won yet")

	_walk(world, red, Vector2i(11, 11))
	_updates(control, world, 30)
	check(control.contested, "with both sides inside the area is contested")
	check_eq(control.holder, ControlPoint.NOBODY, "nobody holds it")
	check_eq(control.owner, PLAYER, "blue's count is kept")
	check_eq(control.hold_ticks, 10, "but waits")
	check(not control.is_won(), "a contested area is never won")

	_walk(world, red, Vector2i(20, 18))
	_updates(control, world, 4)
	check_eq(control.hold_ticks, 14, "when the intruder leaves the count carries on")

	_walk(world, blue, Vector2i(20, 2))
	control.update(world)
	check_eq(control.owner, ControlPoint.NOBODY, "leaving the area empty gives it up")
	check_eq(control.hold_ticks, 0, "and loses the time")

	_walk(world, red, Vector2i(11, 11))
	_updates(control, world, 12)
	check_eq(control.owner, ENEMY, "red can take it")
	_walk(world, blue, Vector2i(9, 9))
	control.update(world)
	_walk(world, red, Vector2i(20, 18))
	control.update(world)
	check_eq(control.owner, PLAYER, "when the area changes hands")
	check_eq(control.hold_ticks, 1, "the new owner starts from zero")
	_updates(control, world, 19)
	check(control.is_won(), "holding it alone for the whole time wins")
	check_eq(control.progress(), 1.0, "progress is complete")


# --- the mission ---------------------------------------------------------------------

func test_mission_definitions() -> void:
	var sides := []
	for path in MISSIONS:
		var def := load(path) as MissionDef
		check(def != null, "%s loads" % path)
		if def == null:
			continue
		sides.append(def.player_side)
		check(def.display_name != "" and def.objective != "", "%s has a name and an objective" % path)
		check_eq(def.troop_count, 4, "four troops a side in %s" % path)
		check(def.player_commander.is_hero and def.enemy_commander.is_hero, "both sides have a commander in %s" % path)
		check(not def.player_troop.is_hero and not def.enemy_troop.is_hero, "troops are not heroes in %s" % path)
		check(def.hold_seconds > 0.0 and def.control_radius > 0.0, "%s has a hold time and a radius" % path)
		check(def.enemy_delay_seconds > 0.0 and def.enemy_wave_seconds > 0.0, "the opponent in %s waits, then comes in two waves" % path)
		check(def.player_side != def.enemy_side, "the sides differ in %s" % path)
		check(def.player_color != def.enemy_color, "and so do their colours")
	check_eq(sides, ["Blue", "Red"], "the player is Blue in the first and Red in the second")
	check_eq((load(MISSIONS[0]) as MissionDef).map.biome.id, &"forest", "Blue plays on the forest map")
	check_eq((load(MISSIONS[1]) as MissionDef).map.biome.id, &"desert", "Red plays on the desert map")


func test_mission_start() -> void:
	for path in MISSIONS:
		var def := load(path) as MissionDef
		var mission := Mission.new(def)
		var world := mission.world
		check_eq(world.team_size(PLAYER), 5, "the player has five units in %s" % path)
		check_eq(world.team_size(ENEMY), 5, "the enemy has five units in %s" % path)
		var heroes := {PLAYER: 0, ENEMY: 0}
		for unit in world.units:
			if unit.type.is_hero:
				heroes[unit.team] += 1
			var start: Vector2i = def.map.starts[unit.team]
			var gap := unit.cell - start
			check(maxi(absi(gap.x), absi(gap.y)) <= 2, "unit %d starts near its side's start" % unit.id)
			check(not mission.control.contains(unit.cell), "nobody starts inside the control area")
		check_eq(heroes, {PLAYER: 1, ENEMY: 1}, "one commander a side")
		check(mission.player_commander() != null and mission.player_commander().type == def.player_commander, "the player's commander is known")
		check_eq(mission.control.center, def.map.control_point, "the control area is centred on the rock")
		check_eq(mission.control.radius, def.control_radius, "with the mission's radius")
		check_eq(mission.control.hold_ticks_needed, roundi(def.hold_seconds * 20), "and hold time")
		check(not mission.is_over(), "the mission is on")
		var rally := mission.opponent.rally
		check(mission.control.contains(rally), "the opponent gathers inside the control area")
		check_eq(world.region_at(rally), world.region_at(def.map.starts[1]), "at a spot it can walk to")
		# The player does not see the enemy at the start.
		for unit in world.units:
			if unit.team == ENEMY:
				check(not world.is_visible_to(unit, PLAYER), "enemy unit %d is hidden at the start" % unit.id)


func test_doing_nothing_loses_to_the_hold_rule() -> void:
	for path in MISSIONS:
		var def := load(path) as MissionDef
		var mission := Mission.new(def)
		for tick in 20 * 300:
			if mission.is_over():
				break
			mission.tick()
		check(mission.is_over(), "%s ends when the player does nothing" % path)
		check_eq(mission.winner, ENEMY, "the opponent wins %s" % path)
		check_eq(mission.win_reason, &"hold", "by holding the rock")
		check(mission.seconds() > def.enemy_delay_seconds + def.hold_seconds, "after its delay and the full hold time")
		check_eq(mission.world.team_size(PLAYER), 5, "without a fight")
		var before := mission.world.tick_count
		mission.tick()
		check_eq(mission.world.tick_count, before, "a finished mission no longer advances")


func test_mission_can_be_won_on_both_maps() -> void:
	for path in MISSIONS:
		var mission := Mission.new(load(path) as MissionDef)
		_play(mission)
		check(mission.is_over(), "%s comes to an end" % path)
		check(mission.player_won(), "playing as the hints teach wins %s (ended by '%s' after %d s, %d of 5 left)" % [
			path, mission.win_reason, int(mission.seconds()), mission.world.team_size(PLAYER)])


func test_eliminating_the_enemy_wins() -> void:
	var mission := Mission.new(_short_mission(1000, 1))
	var ids: Array = []
	for unit in mission.world.units:
		if unit.team == PLAYER:
			ids.append(unit.id)
	mission.world.order_attack_move(ids, mission.def.map.starts[1])
	for tick in 20 * 60:
		if mission.is_over():
			break
		mission.tick()
	check(mission.player_won(), "the player wins")
	check_eq(mission.win_reason, &"eliminated", "by destroying every enemy")
	check_eq(mission.world.team_size(ENEMY), 0, "no enemy is left")


func test_losing_every_unit_loses() -> void:
	var mission := Mission.new(_short_mission(1, 1000))
	for tick in 20 * 120:
		if mission.is_over():
			break
		mission.tick()
	check_eq(mission.winner, ENEMY, "the opponent wins")
	# The opponent reaches the ring first and may win either way; make sure a wiped-out player counts as a loss.
	if mission.win_reason == &"eliminated":
		check_eq(mission.world.team_size(PLAYER), 0, "the player has nothing left")
	var wiped := Mission.new(_short_mission(1, 1000))
	var ids: Array = []
	for unit in wiped.world.units:
		if unit.team == PLAYER:
			ids.append(unit.id)
	wiped.world.order_attack_move(ids, wiped.def.map.starts[1])
	for tick in 20 * 60:
		if wiped.is_over():
			break
		wiped.tick()
	check_eq(wiped.winner, ENEMY, "walking into a stronger enemy loses")
	check_eq(wiped.win_reason, &"eliminated", "by being destroyed")
	check(not wiped.player_won(), "the player did not win")


func test_opponent_waits_then_marches_and_fights() -> void:
	var def := load(MISSIONS[0]) as MissionDef
	var mission := Mission.new(def)
	var delay := roundi(def.enemy_delay_seconds * 20)
	for tick in delay - 1:
		mission.tick()
	for unit in mission.world.units:
		if unit.team == ENEMY:
			check_eq(unit.order, SimUnit.Order.NONE, "enemy unit %d waits out the delay" % unit.id)
	for tick in 5:
		mission.tick()
	var first_wave := 0
	for unit in mission.world.units:
		if unit.team == ENEMY and unit.order == SimUnit.Order.ATTACK_MOVE:
			first_wave += 1
			check(not unit.type.is_hero, "the commander is not in the first wave")
	check_eq(first_wave, 2, "then half of the troops set off with attack-move orders")
	for tick in roundi(def.enemy_wave_seconds * 20):
		mission.tick()
	for unit in mission.world.units:
		if unit.team == ENEMY:
			check(unit.order == SimUnit.Order.ATTACK_MOVE or mission.control.contains(unit.cell),
					"after the wave delay enemy unit %d has set off too" % unit.id)
	for tick in 20 * 25:
		mission.tick()
	var inside := 0
	for unit in mission.world.units:
		if unit.team == ENEMY and mission.control.contains(unit.cell):
			inside += 1
	check_eq(inside, 5, "the whole enemy force reaches the control area")
	check_eq(mission.control.owner, ENEMY, "and its hold time is counting")
	# A player unit that walks into the area is attacked.
	var scout: SimUnit = null
	for unit in mission.world.units:
		if unit.team == PLAYER and not unit.type.is_hero:
			scout = unit
			break
	var rally := ScriptedOpponent.rally_cell(mission.world, mission.control, def.map.starts[0])
	mission.world.order_move([scout.id], rally)
	for tick in 20 * 40:
		if scout.dead or mission.is_over():
			break
		mission.tick()
	check(scout.dead, "a lone intruder in the area is hunted down")


# --- hints and HUD texts -------------------------------------------------------------

func test_hints_follow_what_the_player_has_done() -> void:
	var def := load(MISSIONS[0]) as MissionDef
	var hints := MissionHints.new()
	check_eq(hints.current(), &"select", "first: select")
	check(hints.text(def).contains("select"), "the first hint is about selecting")
	hints.note(&"select")
	check_eq(hints.current(), &"move", "then: move")
	check(hints.text(def).contains("Right-click"), "the second hint is about moving")
	hints.note(&"move")
	check_eq(hints.current(), &"attack", "then: attack")
	check(hints.text(def).contains("Press A"), "the third hint is about attacking")
	hints.note(&"attack")
	check_eq(hints.current(), &"ability", "then: the commander's ability")
	check(hints.text(def).contains("Mend") and hints.text(def).contains("Q"), "the fourth hint names the ability and its key")
	hints.note(&"ability")
	check_eq(hints.current(), &"hold", "last: the control point")
	check(hints.text(def).contains("45 seconds"), "the last hint gives the hold time from the mission data")

	var hasty := MissionHints.new()
	hasty.note(&"attack")
	check_eq(hasty.current(), &"ability", "a player who attacks at once skips the select and move hints")
	var healer := MissionHints.new()
	healer.note(&"ability")
	check_eq(healer.current(), &"select", "using the ability early does not skip the other hints")


func test_hud_texts() -> void:
	check_eq(MissionHud.clock(0.0), "0:00", "zero")
	check_eq(MissionHud.clock(41.2), "0:42", "part seconds round up")
	check_eq(MissionHud.clock(75.0), "1:15", "minutes")
	var mission := Mission.new(load(MISSIONS[0]) as MissionDef)
	check_eq(MissionHud.hold_text(mission), "Nobody holds the rock", "at the start")
	mission.control.owner = PLAYER
	mission.control.holder = PLAYER
	mission.control.hold_ticks = 20 * 15
	check_eq(MissionHud.hold_text(mission), "Blue holds the rock: 0:30 to go", "while the player holds it")
	mission.control.contested = true
	mission.control.holder = ControlPoint.NOBODY
	check(MissionHud.hold_text(mission).begins_with("Contested"), "while it is contested")
	mission.control.owner = ENEMY
	mission.control.contested = false
	check(MissionHud.hold_text(mission).begins_with("Red holds"), "while the enemy holds it")
	var commander := mission.player_commander()
	check_eq(MissionHud.ability_label(commander), "Mend (Q)", "the ability button names the ability and its key")
	check(MissionHud.ability_ready(commander), "and is ready")
	commander.ability_ticks_left = 150
	check_eq(MissionHud.ability_label(commander), "Mend 8s", "while it recharges the button counts down")
	check(not MissionHud.ability_ready(commander), "and is not ready")
	check_eq(MissionHud.ability_label(null), "-", "with no commander there is nothing to press")
	mission.winner = PLAYER
	mission.win_reason = &"hold"
	check(MissionHud.result_text(mission).contains("You held"), "result text for a win by holding")
	mission.winner = ENEMY
	mission.win_reason = &"eliminated"
	check(MissionHud.result_text(mission).contains("destroyed"), "result text for a loss by elimination")


# --- the mission in the game scene ---------------------------------------------------

## The map scene running a mission. The caller frees it.
func _view(def: MissionDef = null) -> MapView:
	MapView.requested_mission = MISSIONS[0]
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	if def != null:
		view.show_mission(def)
	return view


func _body(unit: SimUnit) -> Vector2:
	return UnitsView.feet_position(unit) + UnitsView.BODY


func _select_all(view: MapView) -> void:
	var ids: Array = []
	for unit in view.world.units:
		if unit.team == PLAYER:
			ids.append(unit.id)
	view.selection.set_ids(ids)


func _key(view: MapView, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	view._unhandled_input(event)


func _click(view: MapView, map_point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = map_point - view.camera.position
	view._unhandled_input(event)
	if button == MOUSE_BUTTON_LEFT:
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.pressed = false
		release.position = event.position
		view._unhandled_input(release)


## A soldier of the player's, and a free cell right next to it.
func _soldier(view: MapView) -> SimUnit:
	for unit in view.world.units:
		if unit.team == PLAYER and not unit.type.is_hero:
			return unit
	return null


func test_scene_starts_the_mission() -> void:
	var view := _view()
	check(view.mission != null, "the scene is running a mission")
	check_eq(view.world.units.size(), 10, "both forces are on the map")
	check(view.hud.visible, "the mission HUD is shown")
	check(not view.hud.is_result_shown(), "the result screen is not")
	check(view.control_view.visible and view.control_view.control == view.mission.control, "the control area is drawn")
	check(view.camera.get_view_rect().has_point(_body(view.mission.player_commander())), "the camera shows the commander")
	check(view.hint_text().contains("select"), "the first hint is shown")
	view._process(0.06)
	check_eq(view.world.tick_count, 1, "the scene runs the mission's clock")
	_select_all(view)
	check(MapView.describe_selection(view.world, view.selection).contains("Field Commander"), "the commander is listed in the selection")
	view.selection.set_ids([view.mission.player_commander_id])
	var text := MapView.describe_selection(view.world, view.selection)
	check(text.contains("Attack 16") and text.contains("Mend: ready"), "a single unit shows its attack and its ability")
	view.free()


func test_right_click_attacks_an_enemy_or_moves() -> void:
	var view := _view()
	var soldier := _soldier(view)
	var near := view.world.nearest_free_cell(soldier.cell + Vector2i(3, -3), view.world.region_at(soldier.cell))
	var enemy := view.world.add_unit(load(LEGIONARY), ENEMY, near)
	_select_all(view)
	_click(view, _body(enemy), MOUSE_BUTTON_RIGHT)
	check_eq(soldier.order, SimUnit.Order.ATTACK, "a right click on an enemy is an attack order")
	check_eq(soldier.order_target, enemy.id, "on that enemy")
	check_eq(view.hints.current(), &"ability", "the hints move on to the ability")
	_click(view, _body(soldier) + Vector2(64, 96), MOUSE_BUTTON_RIGHT)
	check_eq(soldier.order, SimUnit.Order.MOVE, "a right click on the ground is a move order")
	# Enemies on ground the player has not explored cannot be picked.
	var hidden: SimUnit = null
	for unit in view.world.units:
		if unit.team == ENEMY and unit != enemy:
			hidden = unit
			break
	check(UnitsView.enemy_at_point(view.world, _body(hidden), PLAYER) == null, "an enemy under the shroud cannot be clicked")
	check(UnitsView.enemy_at_point(view.world, _body(enemy), PLAYER) == enemy, "a visible one can")
	check(UnitsView.enemy_at_point(view.world, _body(soldier), PLAYER) == null, "the player's own units are not enemies")
	view.free()


func test_attack_move_key() -> void:
	var view := _view()
	var soldier := _soldier(view)
	_key(view, KEY_A)
	check_eq(view.mode, MapView.Mode.NORMAL, "A does nothing with no units selected")
	_select_all(view)
	_key(view, KEY_A)
	check_eq(view.mode, MapView.Mode.ATTACK_MOVE, "A waits for a click")
	check(view.hint_text().begins_with("Attack-move"), "and the hint box says so")
	_click(view, _body(soldier) + Vector2(96, 0), MOUSE_BUTTON_RIGHT)
	check_eq(view.mode, MapView.Mode.NORMAL, "a right click cancels")
	check_eq(soldier.order, SimUnit.Order.NONE, "without giving an order")
	_key(view, KEY_A)
	_click(view, _body(soldier) + Vector2(96, 64))
	check_eq(soldier.order, SimUnit.Order.ATTACK_MOVE, "A then a left click is an attack-move order")
	check_eq(view.mode, MapView.Mode.NORMAL, "and the next click selects again")
	check_eq(view.selection.ids.size(), 5, "the click that gave the order did not change the selection")
	_key(view, KEY_S)
	check_eq(soldier.order, SimUnit.Order.NONE, "S stops the selected units")
	# Esc leaves the mode instead of leaving the mission.
	_key(view, KEY_A)
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	view._unhandled_input(escape)
	check_eq(view.mode, MapView.Mode.NORMAL, "Esc cancels the mode")
	check(view.is_inside_tree() and view.mission != null, "and the mission goes on")
	view.free()


func test_ability_key() -> void:
	var view := _view()
	var soldier := _soldier(view)
	var commander := view.mission.player_commander()
	_key(view, KEY_Q)
	check_eq(view.mode, MapView.Mode.ABILITY, "Q waits for a click, with nothing selected")
	_click(view, _body(soldier))
	check_eq(view.mode, MapView.Mode.ABILITY, "a click on a healthy unit keeps waiting")
	check(view.hint_text().begins_with("Mend"), "and the hint box still asks for a unit")
	check_eq(commander.order, SimUnit.Order.NONE, "no order is given")
	soldier.health = 10
	_click(view, _body(soldier))
	check_eq(view.mode, MapView.Mode.NORMAL, "a click on a wounded unit uses the ability")
	check_eq(commander.order, SimUnit.Order.ABILITY, "the commander is told to heal")
	check_eq(commander.order_target, soldier.id, "that unit")
	for i in 40:
		view._process(0.05)
	check_eq(soldier.health, 50, "and does")
	_key(view, KEY_Q)
	check_eq(view.mode, MapView.Mode.NORMAL, "while it recharges Q does nothing")
	check(view.hint_text().contains("not ready"), "and the hint box says why")
	view.hud.command_pressed.emit(&"attack")
	check(view.hint_text().contains("Select"), "the Attack button asks for a selection first")
	_select_all(view)
	view.hud.command_pressed.emit(&"attack")
	check_eq(view.mode, MapView.Mode.ATTACK_MOVE, "the Attack button does what A does")
	view.free()


func test_dead_units_leave_the_selection() -> void:
	var view := _view()
	var soldier := _soldier(view)
	var executioner := (load(LEGIONARY) as UnitType).duplicate() as UnitType
	executioner.attack_damage = 1000
	executioner.max_health = 100000
	view.selection.set_ids([soldier.id, view.mission.player_commander_id])
	view.press_group_key(2, true)
	view.world.add_unit(executioner, ENEMY, view.world.nearest_free_cell(soldier.cell + Vector2i(1, 0), 0))
	for i in 200:
		if soldier.dead:
			break
		view._process(0.06)
	check(soldier.dead, "the soldier is killed")
	view._process(0.06)
	check(not view.selection.has(soldier.id), "and leaves the selection")
	check(not view.selection.groups[2].has(soldier.id), "and its control group")
	view.free()


func test_win_screen_and_restart() -> void:
	var view := _view(_short_mission(1000, 1))
	check_eq(view.world.units.size(), 2, "the short mission has one unit a side")
	_select_all(view)
	view.order_attack_move_to(MapData.cell_center(view.map.starts[1]))
	for i in 20 * 60:
		if view.is_over():
			break
		view._process(0.05)
	check(view.is_over() and view.mission.player_won(), "the mission is won")
	view._process(0.05)
	check(view.hud.is_result_shown(), "the result screen is shown")
	var soldier: SimUnit = view.world.units[0]
	var ticks := view.world.tick_count
	var order_before := soldier.order
	view.order_move_to(MapData.cell_center(view.map.starts[0]))
	_key(view, KEY_A)
	view._process(0.2)
	check_eq(soldier.order, order_before, "orders are ignored once the mission is over")
	check_eq(view.mode, MapView.Mode.NORMAL, "and so are the command keys")
	check_eq(view.world.tick_count, ticks, "the simulation stands still")
	view.hud.again_pressed.emit()
	check(not view.is_over(), "Play again starts the mission afresh")
	check(not view.hud.is_result_shown(), "and hides the result screen")
	check_eq(view.world.units.size(), 2, "with both forces back")
	check_eq(view.world.tick_count, 0, "from the beginning")
	view.free()


func test_loss_screen() -> void:
	var view := _view(_short_mission(1, 1000))
	_select_all(view)
	view.order_attack_move_to(MapData.cell_center(view.map.starts[1]))
	for i in 20 * 60:
		if view.is_over():
			break
		view._process(0.05)
	view._process(0.05)
	check(view.is_over() and not view.mission.player_won(), "the mission is lost")
	check(view.hud.is_result_shown(), "the result screen is shown")
	check(view.selection.is_empty(), "the dead unit is no longer selected")
	view.free()
