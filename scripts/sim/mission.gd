class_name Mission
extends RefCounted
## A mission being played: the world, the control point, the scripted opponent
## and the rule that decides who has won. A practice mission (see MissionDef)
## has no control point to hold and no winner: it is just the world, ticking,
## with raiders in it if the mission has enemy troops. In a skirmish both
## sides have a base, the enemy is the computer opponent, and the side that
## loses all its buildings and troops has lost.

const PLAYER_TEAM := SimWorld.PLAYER_TEAM
const ENEMY_TEAM := 1
const NOBODY := -1

var def: MissionDef
var world: SimWorld
var control: ControlPoint
var opponent: ScriptedOpponent
## The enemy of a skirmish, otherwise null.
var computer: ComputerOpponent
## The enemy of a practice mission with a raid, otherwise null.
var raiders: Raiders
## Id of the player's commander. It stays the same after the commander dies.
var player_commander_id := 0
## Id of the player's refinery, or 0 if the mission gives none.
var player_refinery_id := 0
## Id of the player's headquarters, or 0 if the mission gives none.
var player_headquarters_id := 0
## Ids of the enemy's headquarters and refinery, or 0.
var enemy_headquarters_id := 0
var enemy_refinery_id := 0
## The team that has won, or NOBODY while the mission is being played.
var winner := NOBODY
## How it was won: &"hold" (held the control area) or &"eliminated" (the other
## side has no units left; in a skirmish, no buildings and no troops).
var win_reason := &""


func _init(p_def: MissionDef) -> void:
	def = p_def
	var map := def.map
	world = SimWorld.new(map)
	if def.ore_richness > 1:
		for deposit in world.deposits:
			deposit.multiply(def.ore_richness)
	var center := map.control_point if map.has_control_point() else Vector2(map.get_size()) / 2.0
	control = ControlPoint.new(center, def.control_radius, def.hold_seconds)
	var starts := map.starts
	var player_start := starts[0] if starts.size() > 0 else Vector2i.ZERO
	var enemy_start := starts[1] if starts.size() > 1 else map.get_size() - Vector2i.ONE
	# The buildings go down first, so that nobody is put where they will stand.
	var player_base := _set_up_base(PLAYER_TEAM, player_start, def.player_headquarters, def.player_refinery, def.start_orichalcum)
	player_headquarters_id = player_base[0]
	player_refinery_id = player_base[1]
	if def.skirmish:
		var enemy_base := _set_up_base(ENEMY_TEAM, enemy_start, def.enemy_headquarters, def.enemy_refinery, def.enemy_start_orichalcum)
		enemy_headquarters_id = enemy_base[0]
		enemy_refinery_id = enemy_base[1]
	var commander := _spawn(PLAYER_TEAM, player_start, def.player_commander, def.player_troop, def.troop_count)
	player_commander_id = commander.id if commander != null else 0
	if def.practice or def.skirmish:
		# Nothing is hidden in a practice mission that the player is sent to: the rock is on the map from the start.
		# In a skirmish both sides know where it is.
		for deposit in world.deposits:
			for cell in deposit.cells:
				world.shroud_for(PLAYER_TEAM).reveal_circle(cell, 2)
				if def.skirmish:
					world.shroud_for(ENEMY_TEAM).reveal_circle(cell, 2)
	_add_harvesters(PLAYER_TEAM, player_start, player_refinery_id, def.player_harvester, def.harvester_count)
	if def.skirmish:
		_add_harvesters(ENEMY_TEAM, enemy_start, enemy_refinery_id, def.enemy_harvester, def.enemy_harvester_count)
	_spawn(ENEMY_TEAM, enemy_start, def.enemy_commander, def.enemy_troop, def.enemy_troops())
	if def.has_raid():
		raiders = Raiders.new(world, ENEMY_TEAM, def.enemy_delay_seconds)
	if def.skirmish:
		computer = ComputerOpponent.new(world, ENEMY_TEAM, PLAYER_TEAM, player_start)
		return
	opponent = ScriptedOpponent.new(world, control, ENEMY_TEAM, enemy_start, def.enemy_delay_seconds)
	# The second wave is the commander and the second half of the troops.
	var troops := 0
	for unit in world.units:
		if unit.team != ENEMY_TEAM:
			continue
		if not unit.type.is_hero:
			troops += 1
		if def.enemy_wave_seconds > 0.0 and (unit.type.is_hero or troops > (def.enemy_troops() + 1) / 2):
			opponent.hold_back(unit.id, def.enemy_wave_seconds)


## Put a side's headquarters and refinery on the building ground nearest to
## its start, and fill its store. Returns their ids (0 for one it has not got).
func _set_up_base(team: int, start: Vector2i, headquarters: BuildingType, refinery: BuildingType, orichalcum: int) -> Array[int]:
	var ids: Array[int] = [0, 0]
	for i in 2:
		var type := headquarters if i == 0 else refinery
		if type == null:
			continue
		var site := world.nearest_build_site(type, start)
		if site != SimWorld.NO_CELL:
			ids[i] = world.add_building(type, team, site).id
	world.stored[team] = mini(orichalcum, world.storage_for(team))
	return ids


## Put a side's harvesters beside its refinery, facing the control point.
func _add_harvesters(team: int, start: Vector2i, refinery_id: int, type: UnitType, count: int) -> void:
	if type == null or count <= 0:
		return
	var refinery := world.get_building(refinery_id)
	var beside := start
	if refinery != null:
		beside = refinery.cell + Vector2i(refinery.type.footprint.x / 2, refinery.type.footprint.y)
	for unit in world.add_group(type, team, beside, count):
		unit.facing = SimWorld.facing_toward(Vector2i(control.center) - unit.cell)


## Put one side on the map: the commander on the start cell, the troops around
## it, everyone facing the control point. Returns the commander.
func _spawn(team: int, start: Vector2i, commander_type: UnitType, troop_type: UnitType, troops: int) -> SimUnit:
	var group: Array[SimUnit] = []
	if commander_type != null:
		group.append_array(world.add_group(commander_type, team, start, 1))
	if troop_type != null:
		group.append_array(world.add_group(troop_type, team, start, troops))
	for unit in group:
		unit.facing = SimWorld.facing_toward(Vector2i(control.center) - unit.cell)
	return group[0] if commander_type != null and not group.is_empty() else null


## Has a side lost a skirmish: no buildings and no troops left?
func is_beaten(team: int) -> bool:
	return world.building_count(team) == 0 and world.fighter_count(team) == 0


func is_over() -> bool:
	return winner != NOBODY


func player_won() -> bool:
	return winner == PLAYER_TEAM


## The player's commander, or null once it is dead.
func player_commander() -> SimUnit:
	return world.get_unit(player_commander_id)


## Advance the mission by one simulation tick. Does nothing once it is over.
func tick() -> void:
	if is_over():
		return
	if def.practice:
		if raiders != null:
			raiders.tick()
		world.tick()
		return
	if def.skirmish:
		computer.tick()
		world.tick()
		var player_out := is_beaten(PLAYER_TEAM)
		if player_out:
			_finish(ENEMY_TEAM, &"eliminated")
		elif is_beaten(ENEMY_TEAM):
			_finish(PLAYER_TEAM, &"eliminated")
		return
	opponent.tick()
	world.tick()
	control.update(world)
	var players := world.team_size(PLAYER_TEAM)
	var enemies := world.team_size(ENEMY_TEAM)
	if enemies == 0 and players > 0:
		_finish(PLAYER_TEAM, &"eliminated")
	elif players == 0:
		_finish(ENEMY_TEAM, &"eliminated")
	elif control.is_won():
		_finish(control.owner, &"hold")


func _finish(team: int, reason: StringName) -> void:
	winner = team
	win_reason = reason


## Seconds played so far.
func seconds() -> float:
	return world.tick_count * SimWorld.TICK_SECONDS
