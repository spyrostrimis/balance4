class_name Mission
extends RefCounted
## A mission being played: the world, the opponents, the control area, the
## objectives and the triggers, all set up from a MissionDef.
##
## Each tick the opponents think, the world advances, the control area is
## updated, then the rules are checked: losing any of the player's heroes
## loses the mission (a rule of every mission; enemy heroes count only if
## an objective says so), a failed primary objective loses it, and every
## primary objective done wins it. Then the triggers fire.
## A mission without primary objectives that can be done (a practice mission)
## goes on until the player leaves it.

const PLAYER_TEAM := SimWorld.PLAYER_TEAM
const ENEMY_TEAM := 1
const NOBODY := -1

## What has become of an objective.
const HIDDEN := &"hidden"
const OPEN := &"open"
const DONE := &"done"
const FAILED := &"failed"

var def: MissionDef
var world: SimWorld
## The control area. Every mission has one, but it means something only if
## the mission's objectives use it (see MissionDef.has_control()).
var control: ControlPoint
## Whatever plays each side that is not the player's: team -> its opponent
## object (ScriptedOpponent, Raiders, ComputerOpponent).
var opponents := {}
## Id of the player's commander (first hero). It stays the same after the commander dies.
var player_commander_id := 0
## Ids of the first headquarters and refinery placed for each side, or 0.
var player_refinery_id := 0
var player_headquarters_id := 0
var enemy_headquarters_id := 0
var enemy_refinery_id := 0
## The team that has won, or NOBODY while the mission is being played.
var winner := NOBODY
## Why: &"hold" (held the control area), &"eliminated" (the other side has
## nothing left), &"hero" (the player lost a hero), or whatever an
## objective's condition or an EndAction says.
var win_reason := &""
## The hero whose death lost the mission, or null.
var fallen_hero: UnitType
## What the mission has said to the player, oldest first: each a Dictionary
## with "speaker", "text" and "tick".
var messages: Array[Dictionary] = []

## Objective id -> HIDDEN, OPEN, DONE or FAILED.
var _objectives := {}
## Trigger index -> the tick at which it fires (its condition has been met), or -1 once fired.
var _pending := {}
## Things the player has done in the game screen (see note()).
var _done := {}
## Tag -> the units ([&"unit", id]) and buildings ([&"building", id]) placed under it.
var _tagged := {}
## Ids of the player's heroes, with their types.
var _heroes := {}


func _init(p_def: MissionDef) -> void:
	def = p_def
	var map := def.map
	world = SimWorld.new(map)
	if def.ore_richness > 1:
		for deposit in world.deposits:
			deposit.multiply(def.ore_richness)
	var center := map.control_point if map.has_control_point() else Vector2(map.get_size()) / 2.0
	control = ControlPoint.new(center, def.control_radius, maxf(def.hold_seconds, 1.0))
	place(def.forces)
	for team in def.sides.size():
		var side := def.sides[team]
		world.stored[team] = mini(side.orichalcum, world.storage_for(team))
		if side.knows_deposits:
			for deposit in world.deposits:
				for cell in deposit.cells:
					world.shroud_for(team).reveal_circle(cell, 2)
	for team in def.sides.size():
		var side := def.sides[team]
		if side.opponent != null:
			var opponent := side.opponent.create(self, team)
			if opponent != null:
				opponents[team] = opponent
	for item in def.objectives:
		_objectives[item.id] = HIDDEN if item.hidden else OPEN


## The cell a side starts at.
func start_of(team: int) -> Vector2i:
	var starts := def.map.starts
	var index := def.sides[team].start if team < def.sides.size() else team
	if index < starts.size():
		return starts[index]
	return Vector2i.ZERO if team == PLAYER_TEAM else def.map.get_size() - Vector2i.ONE


## Put units and buildings on the map: the buildings first, on the building
## ground nearest to where they are placed, then the units, each group on the
## free cells nearest to its spot, facing the control area.
func place(placements: Array[Placement]) -> void:
	for placement in placements:
		if placement.is_building():
			var type := placement.type as BuildingType
			var site := world.nearest_build_site(type, _spot(placement))
			if site == SimWorld.NO_CELL:
				push_warning("Mission '%s': no room for %s" % [def.id, type.id])
				continue
			var building := world.add_building(type, placement.team, site)
			_remember(placement.tag, &"building", building.id)
			_note_building(building)
	for placement in placements:
		if placement.is_building() or placement.type == null:
			continue
		for unit in world.add_group(placement.type as UnitType, placement.team, _spot(placement), placement.count):
			unit.facing = SimWorld.facing_toward(Vector2i(control.center) - unit.cell)
			_remember(placement.tag, &"unit", unit.id)
			if unit.team == PLAYER_TEAM and unit.type.is_hero:
				_heroes[unit.id] = unit.type
				if player_commander_id == 0:
					player_commander_id = unit.id


func _spot(placement: Placement) -> Vector2i:
	match placement.at:
		Placement.At.CELL:
			return placement.cell
		Placement.At.REFINERY:
			var refinery := world.get_building(player_refinery_id if placement.team == PLAYER_TEAM else enemy_refinery_id)
			if refinery != null:
				return refinery.cell + Vector2i(refinery.type.footprint.x / 2, refinery.type.footprint.y)
	return start_of(placement.team)


func _note_building(building: SimBuilding) -> void:
	var player := building.team == PLAYER_TEAM
	if building.type.is_refinery:
		if player and player_refinery_id == 0:
			player_refinery_id = building.id
		elif not player and enemy_refinery_id == 0:
			enemy_refinery_id = building.id
	if not building.type.builds.is_empty():
		if player and player_headquarters_id == 0:
			player_headquarters_id = building.id
		elif not player and enemy_headquarters_id == 0:
			enemy_headquarters_id = building.id


func _remember(tag: StringName, kind: StringName, id: int) -> void:
	if tag == &"":
		return
	if not _tagged.has(tag):
		_tagged[tag] = []
	_tagged[tag].append([kind, id])


## How many of the units and buildings placed under a tag are still there.
func tagged_left(tag: StringName) -> int:
	var left := 0
	for entry in _tagged.get(tag, []):
		if (world.get_unit(entry[1]) if entry[0] == &"unit" else world.get_building(entry[1])) != null:
			left += 1
	return left


## The living units placed under a tag.
func tagged_units(tag: StringName) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for entry in _tagged.get(tag, []):
		if entry[0] == &"unit":
			var unit := world.get_unit(entry[1])
			if unit != null:
				out.append(unit)
	return out


## Has a side lost a base game: no buildings and no troops left?
func is_beaten(team: int) -> bool:
	return world.building_count(team) == 0 and world.fighter_count(team) == 0


func is_over() -> bool:
	return winner != NOBODY


func player_won() -> bool:
	return winner == PLAYER_TEAM


## The player's commander, or null once it is dead.
func player_commander() -> SimUnit:
	return world.get_unit(player_commander_id)


## The opponent playing a team, or null.
func opponent_of(team: int) -> RefCounted:
	return opponents.get(team)


## The opponent of Mission 1, or null.
var opponent: ScriptedOpponent:
	get: return opponent_of(ENEMY_TEAM) as ScriptedOpponent
## The computer opponent of a skirmish, or null.
var computer: ComputerOpponent:
	get: return opponent_of(ENEMY_TEAM) as ComputerOpponent
## The raiders of a practice mission, or null.
var raiders: Raiders:
	get: return opponent_of(ENEMY_TEAM) as Raiders


## Tell the mission the player has done something in the game screen:
## &"select", &"move", &"attack", &"ability", &"harvest", &"build", &"place",
## &"train" or &"repair". Hints and EventConditions use this.
func note(what: StringName) -> void:
	_done[what] = true
	# Whoever gives an order has selected; whoever attacks knows how to move.
	if what == &"attack":
		_done[&"move"] = true
	if what == &"attack" or what == &"move" or what == &"harvest":
		_done[&"select"] = true


func has_done(what: StringName) -> bool:
	return _done.has(what)


func add_message(speaker: String, text: String, portrait: Texture2D = null) -> void:
	messages.append({"speaker": speaker, "text": text, "tick": world.tick_count, "portrait": portrait})


## HIDDEN, OPEN, DONE or FAILED; &"" for an objective the mission has not got.
func objective_state(objective_id: StringName) -> StringName:
	return _objectives.get(objective_id, &"")


## The objectives the player can see, in order.
func shown_objectives() -> Array[Objective]:
	var out: Array[Objective] = []
	for item in def.objectives:
		if _objectives.get(item.id) != HIDDEN:
			out.append(item)
	return out


func show_objective(objective_id: StringName) -> void:
	if _objectives.get(objective_id) == HIDDEN:
		_objectives[objective_id] = OPEN


## End the mission: `team` has won.
func finish(team: int, reason: StringName) -> void:
	if is_over():
		return
	winner = team
	win_reason = reason


## Advance the mission by one simulation tick. Does nothing once it is over.
func tick() -> void:
	if is_over():
		return
	for team in opponents:
		opponents[team].tick()
	world.tick()
	if def.has_control():
		control.update(world)
	_check_heroes()
	if is_over():
		return
	_check_objectives()
	if not is_over():
		_fire_triggers()


## The player's heroes that are still alive.
func player_heroes() -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for id in _heroes:
		var hero := world.get_unit(id)
		if hero != null:
			out.append(hero)
	return out


## Losing any hero loses the mission.
func _check_heroes() -> void:
	for id in _heroes:
		if world.get_unit(id) == null:
			fallen_hero = _heroes[id]
			finish(ENEMY_TEAM, &"hero")
			return


## Check the open objectives. A primary one that fails loses the mission at
## once; when the last primary one is done the mission is won, for the reason
## of that one.
func _check_objectives() -> void:
	var primaries := 0
	var primaries_done := 0
	var last_reason := &""
	for item in def.objectives:
		if _objectives[item.id] == OPEN:
			if item.failed_when != null and item.failed_when.check(self):
				_objectives[item.id] = FAILED
				if item.primary:
					finish(ENEMY_TEAM, item.failed_when.why(self))
					return
			elif item.done_when != null and item.done_when.check(self):
				_objectives[item.id] = DONE
				if item.primary:
					last_reason = item.done_when.why(self)
		if item.primary:
			primaries += 1
			if _objectives[item.id] == DONE:
				primaries_done += 1
	if primaries > 0 and primaries_done == primaries:
		finish(PLAYER_TEAM, last_reason)


func _fire_triggers() -> void:
	for i in def.triggers.size():
		var at: int = _pending.get(i, 0)
		if at < 0:
			continue                    # fired
		var trigger := def.triggers[i]
		if not _pending.has(i):
			if trigger.when != null and not trigger.when.check(self):
				continue
			at = world.tick_count + roundi(trigger.delay_seconds * SimWorld.TICKS_PER_SECOND)
			_pending[i] = at
		if world.tick_count >= at:
			_pending[i] = -1
			for action in trigger.actions:
				if action != null:
					action.run(self)
			if is_over():
				return


## Seconds played so far.
func seconds() -> float:
	return world.tick_count * SimWorld.TICK_SECONDS
