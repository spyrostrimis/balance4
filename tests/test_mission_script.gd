extends TestCase
## Missions as data: sides, placed forces, objectives, triggers, conditions,
## actions and hints (scripts/sim/missions/), and every mission file.

const FOREST := "res://data/biomes/forest.tres"
const GUARD := "res://data/units/blue_infantry.tres"
const LEGIONARY := "res://data/units/red_infantry.tres"
const COMMANDER := "res://data/units/blue_commander.tres"
const BLUE_HQ := "res://data/buildings/blue_headquarters.tres"
const BLUE_REFINERY := "res://data/buildings/blue_refinery.tres"
const RED_REFINERY := "res://data/buildings/red_refinery.tres"
const MISSION_DIR := "res://data/missions"
const PLAYER := Mission.PLAYER_TEAM
const ENEMY := Mission.ENEMY_TEAM


## An open 30x20 map of grass with stone along the top rows to build on; the
## sides start at opposite corners.
func _map() -> MapData:
	var map := MapData.new()
	map.biome = load(FOREST)
	var rows := []
	for y in 20:
		rows.append(("s" if y < 4 else ".").repeat(30))
	map.rows = PackedStringArray(rows)
	map.starts = [Vector2i(3, 10), Vector2i(26, 10)] as Array[Vector2i]
	return map


func _side(name: String) -> MissionSide:
	var side := MissionSide.new()
	side.name = name
	side.start = 0 if name == "Blue" else 1
	return side


func _put(team: int, path: String, count := 1, at := Placement.At.START, cell := Vector2i.ZERO, tag := &"") -> Placement:
	var placement := Placement.new()
	placement.team = team
	placement.type = load(path)
	placement.count = count
	placement.at = at
	placement.cell = cell
	placement.tag = tag
	return placement


## A mission on the open map with a guard for each side and nothing else.
func _def() -> MissionDef:
	var def := MissionDef.new()
	def.id = &"test"
	def.map = _map()
	def.sides.assign([_side("Blue"), _side("Red")])
	def.forces.assign([_put(PLAYER, GUARD), _put(ENEMY, LEGIONARY)])
	return def


func _objective(id: StringName, done: MissionCondition, failed: MissionCondition = null, primary := true, hidden := false) -> Objective:
	var objective := Objective.new()
	objective.id = id
	objective.text = String(id)
	objective.done_when = done
	objective.failed_when = failed
	objective.primary = primary
	objective.hidden = hidden
	return objective


func _trigger(when: MissionCondition, actions: Array, delay := 0.0) -> MissionTrigger:
	var trigger := MissionTrigger.new()
	trigger.when = when
	trigger.delay_seconds = delay
	trigger.actions.assign(actions)
	return trigger


func _time(seconds: float) -> TimeCondition:
	var condition := TimeCondition.new()
	condition.seconds = seconds
	return condition


func _store(amount: int) -> StoreCondition:
	var condition := StoreCondition.new()
	condition.amount = amount
	return condition


func _message(text: String) -> MessageAction:
	var action := MessageAction.new()
	action.speaker = "Scout"
	action.text = text
	return action


func _ticks(mission: Mission, seconds: float) -> void:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		mission.tick()


# --- every mission file ----------------------------------------------------------------

func test_every_mission_file_is_sound() -> void:
	var count := 0
	for file in DirAccess.get_files_at(MISSION_DIR):
		if not file.ends_with(".tres"):
			continue
		count += 1
		var def := load("%s/%s" % [MISSION_DIR, file]) as MissionDef
		check(def != null, "%s loads" % file)
		if def == null:
			continue
		check(def.problems().is_empty(), "%s has no problems: %s" % [file, def.problems()])
		check(def.objective != "", "%s says what to do" % file)
		check(def.hints != null and not def.hints.hints.is_empty(), "%s has hints" % file)
		check(def.hints.hints.back().done_when == null, "and its last hint stays up")
		check(def.sides[PLAYER].opponent == null, "the player's side in %s is not played by the computer" % file)
		var mission := Mission.new(def)
		check(mission.world.team_size(PLAYER) > 0, "%s puts the player's units on the map" % file)
	check_eq(count, 10, "all ten missions are checked")


func test_problems_are_reported() -> void:
	var def := _def()
	check(def.problems().is_empty(), "a sound mission has none")
	def.objectives.assign([_objective(&"same", null), _objective(&"same", null)])
	def.forces.append(_put(5, GUARD))
	def.sides[1].start = 7
	var problems := def.problems()
	check_eq(problems.size(), 3, "a repeated objective id, a side that does not exist and a missing start: %s" % problems)


# --- sides and placed forces -----------------------------------------------------------

func test_placed_forces() -> void:
	var def := _def()
	def.sides[PLAYER].orichalcum = 5000
	def.forces.assign([
		_put(PLAYER, BLUE_REFINERY),
		_put(PLAYER, BLUE_HQ),
		_put(PLAYER, COMMANDER, 1, Placement.At.START, Vector2i.ZERO, &"heroes"),
		_put(PLAYER, GUARD, 3, Placement.At.CELL, Vector2i(15, 15), &"squad"),
		_put(ENEMY, LEGIONARY, 2, Placement.At.CELL, Vector2i(25, 15), &"squad"),
	])
	var mission := Mission.new(def)
	var world := mission.world
	check_eq(world.building_count(PLAYER), 2, "the buildings are on the map")
	var refinery := world.get_building(mission.player_refinery_id)
	var hq := world.get_building(mission.player_headquarters_id)
	check(refinery != null and refinery.type.is_refinery, "the refinery is known")
	check(hq != null and not hq.type.builds.is_empty(), "and so is the headquarters")
	check(refinery.cell.y < 4 and hq.cell.y < 4, "both stand on the building ground")
	check_eq(world.stored_for(PLAYER), world.storage_for(PLAYER), "the store is filled only as far as it fits")
	check(mission.player_commander() != null and mission.player_commander().type.is_hero, "the first hero is the player's commander")
	var squad := mission.tagged_units(&"squad")
	check_eq(squad.size(), 5, "units placed under one tag are found together, from both sides")
	for unit in squad:
		var spot := Vector2i(15, 15) if unit.team == PLAYER else Vector2i(25, 15)
		check(maxi(absi(unit.cell.x - spot.x), absi(unit.cell.y - spot.y)) <= 2, "unit %d stands near its cell" % unit.id)
	check_eq(mission.tagged_left(&"heroes"), 1, "the commander is counted under its tag")
	check_eq(mission.tagged_left(&"nothing"), 0, "an unknown tag has nothing")
	world.destroy_building(hq)
	check_eq(world.building_count(PLAYER), 1, "a building can be destroyed")


func test_a_side_that_knows_the_rock_sees_it() -> void:
	var def := load("res://data/missions/harvest_trial_blue.tres") as MissionDef
	var mission := Mission.new(def)
	var cell := mission.world.deposits[0].cells[0]
	check(mission.world.shroud_for(PLAYER).is_explored(cell), "the player sees the rock in a practice mission")
	var claim := Mission.new(load("res://data/missions/first_claim_blue.tres"))
	check(not claim.world.shroud_for(PLAYER).is_explored(claim.world.deposits[0].cells[0]), "but not in Mission 1")


# --- objectives ----------------------------------------------------------------------

func test_every_primary_objective_done_wins() -> void:
	var def := _def()
	var later := _objective(&"later", _time(2.0), null, true, true)
	def.objectives.assign([_objective(&"first", _time(1.0)), later, _objective(&"extra", null, null, false)])
	var reveal := ObjectiveAction.new()
	reveal.objective = &"later"
	def.triggers.assign([_trigger(_time(3.0), [reveal])])
	var mission := Mission.new(def)
	check_eq(mission.shown_objectives().size(), 2, "a hidden objective is not shown")
	check_eq(def.objective, "first", "the HUD line is the first primary objective shown at the start")
	_ticks(mission, 1.5)
	check_eq(mission.objective_state(&"first"), Mission.DONE, "an objective is done when its condition is")
	check(not mission.is_over(), "one primary objective is not enough")
	_ticks(mission, 1.0)
	check_eq(mission.objective_state(&"later"), Mission.HIDDEN, "a hidden objective is not checked")
	_ticks(mission, 0.6)
	check(mission.is_over(), "once it is shown and done, every primary objective is done")
	check(mission.player_won(), "and the player wins")
	check_eq(mission.objective_state(&"extra"), Mission.OPEN, "a secondary objective does not have to be done")


func test_a_failed_primary_objective_loses() -> void:
	var def := _def()
	var gone := GoneCondition.new()
	gone.tag = &"vip"
	def.forces.append(_put(PLAYER, COMMANDER, 1, Placement.At.START, Vector2i.ZERO, &"vip"))
	def.objectives.assign([_objective(&"protect", null, gone), _objective(&"side", null, _time(0.5), false)])
	var mission := Mission.new(def)
	_ticks(mission, 1.0)
	check_eq(mission.objective_state(&"side"), Mission.FAILED, "a secondary objective can fail")
	check(not mission.is_over(), "without losing the mission")
	var vip := mission.tagged_units(&"vip")[0]
	vip.health = 0
	mission.world._kill(vip)
	mission.tick()
	check(mission.is_over() and not mission.player_won(), "losing what had to be protected loses")
	check_eq(mission.win_reason, &"eliminated", "for the reason of the condition")
	var before := mission.world.tick_count
	mission.tick()
	check_eq(mission.world.tick_count, before, "the mission stands still once it is over")


func test_a_mission_without_objectives_never_ends() -> void:
	var mission := Mission.new(load("res://data/missions/harvest_trial_blue.tres"))
	_ticks(mission, 30.0)
	check(not mission.is_over(), "a practice mission goes on")


# --- triggers and actions --------------------------------------------------------------

func test_triggers_fire_once_after_their_delay() -> void:
	var def := _def()
	def.triggers.assign([_trigger(_time(1.0), [_message("Movement to the east.")], 2.0), _trigger(null, [_message("Hello.")])])
	var mission := Mission.new(def)
	mission.tick()
	check_eq(mission.messages.size(), 1, "a trigger without a condition fires at once")
	check_eq(mission.messages[0]["text"], "Hello.", "with its message")
	_ticks(mission, 2.5)
	check_eq(mission.messages.size(), 1, "the other waits for its condition and then its delay")
	_ticks(mission, 1.0)
	check_eq(mission.messages.size(), 2, "and then fires")
	check_eq(mission.messages[1]["speaker"], "Scout", "with who says it")
	_ticks(mission, 5.0)
	check_eq(mission.messages.size(), 2, "only once")


func test_reinforcements_reveal_and_send() -> void:
	var def := _def()
	var reinforce := ReinforceAction.new()
	reinforce.placements.assign([_put(ENEMY, LEGIONARY, 3, Placement.At.CELL, Vector2i(26, 18), &"wave")])
	var send := SendAction.new()
	send.team = ENEMY
	send.tag = &"wave"
	send.cell = Vector2i(3, 18)
	var reveal := RevealAction.new()
	reveal.team = PLAYER
	reveal.cell = Vector2i(26, 18)
	reveal.radius = 3
	def.triggers.assign([_trigger(_time(1.0), [reinforce, send, reveal])])
	var mission := Mission.new(def)
	check_eq(mission.world.team_size(ENEMY), 1, "nothing has arrived yet")
	_ticks(mission, 1.1)
	check_eq(mission.world.team_size(ENEMY), 4, "the reinforcements arrive")
	var wave := mission.tagged_units(&"wave")
	check_eq(wave.size(), 3, "under their tag")
	for unit in wave:
		check_eq(unit.order, SimUnit.Order.ATTACK_MOVE, "unit %d is sent with attack-move" % unit.id)
	check(mission.world.shroud_for(PLAYER).is_explored(Vector2i(26, 18)), "the player is shown where they came from")


func test_end_action_and_store_condition() -> void:
	var def := _def()
	def.sides[PLAYER].orichalcum = 300
	def.forces.append(_put(PLAYER, BLUE_REFINERY))
	var end := EndAction.new()
	end.winner = ENEMY
	end.reason = &"too_rich"
	def.triggers.assign([_trigger(_store(200), [end])])
	var mission := Mission.new(def)
	mission.tick()
	check(mission.is_over() and mission.winner == ENEMY, "an EndAction ends the mission")
	check_eq(mission.win_reason, &"too_rich", "for its reason")


# --- conditions ----------------------------------------------------------------------

func test_conditions() -> void:
	var def := _def()
	def.forces.append(_put(ENEMY, RED_REFINERY, 1, Placement.At.CELL, Vector2i(20, 1), &"camp"))
	def.objectives.assign([_objective(&"a", null), _objective(&"b", _time(0.0))])
	var mission := Mission.new(def)
	mission.tick()
	var area := AreaCondition.new()
	area.team = PLAYER
	area.cell = Vector2i(3, 10)
	area.radius = 2.0
	check(area.check(mission), "the player's guard is in the area around its start")
	area.count = 2
	check(not area.check(mission), "but not two units")
	var building := BuildingCondition.new()
	building.team = ENEMY
	building.type = load(RED_REFINERY)
	check(building.check(mission), "the enemy has a refinery")
	building.count = 2
	check(not building.check(mission), "but not two")
	var gone := GoneCondition.new()
	gone.tag = &"camp"
	check(not gone.check(mission), "the camp stands")
	mission.world.destroy_building(mission.world.get_building(mission.enemy_refinery_id))
	check(gone.check(mission), "and then is gone")
	var done := ObjectiveCondition.new()
	done.objective = &"b"
	check(done.check(mission), "objective b is done")
	done.objective = &"a"
	check(not done.check(mission), "objective a is not")
	var event := EventCondition.new()
	event.event = &"move"
	check(not event.check(mission), "the player has not moved anything")
	mission.note(&"attack")
	check(event.check(mission) and mission.has_done(&"select"), "attacking counts as moving and selecting")
	var both := AllCondition.new()
	both.conditions.assign([gone, event])
	check(both.check(mission), "all of two true conditions")
	both.conditions.append(_time(999.0))
	check(not both.check(mission), "but not with a false one")
	var either := AnyCondition.new()
	var hold := HoldCondition.new()
	either.conditions.assign([_time(999.0), gone, hold])
	check(either.check(mission), "any of them")
	check_eq(either.why(mission), &"eliminated", "with the reason of the first that is true")
	var defeat := DefeatCondition.new()
	defeat.team = ENEMY
	check(not defeat.check(mission), "the enemy still has its guard")
	defeat.buildings_count = true
	check(not defeat.check(mission), "and in a base game a troop is enough")


# --- hints -----------------------------------------------------------------------------

func test_hints_fill_in_the_mission_values() -> void:
	var mission := Mission.new(load("res://data/missions/skirmish_red.tres"))
	check_eq(MissionHints.fill("{player} against {enemy}, {storage}", mission), "Red against Blue, 1000",
			"the sides' names and what the player can store")
	var claim := Mission.new(load("res://data/missions/first_claim_blue.tres"))
	check_eq(MissionHints.fill("{ability} for {hold_seconds} s", claim), "Mend for 45 s", "the ability and the hold time")
	var hints := MissionHints.new(claim)
	claim.note(&"attack")
	check_eq(hints.current(), &"ability", "the hints follow what the player has done")
	var commander := claim.player_commander()
	commander.health = 0
	claim.world._kill(commander)
	check_eq(hints.current(), &"hold", "a dead commander's ability is not taught")
	var none := Mission.new(_def())
	check_eq(MissionHints.new(none).text(), "", "a mission without hints shows none")
