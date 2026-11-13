class_name Mission
extends RefCounted
## A mission being played: the world, the control point, the scripted opponent
## and the rule that decides who has won.

const PLAYER_TEAM := SimWorld.PLAYER_TEAM
const ENEMY_TEAM := 1
const NOBODY := -1

var def: MissionDef
var world: SimWorld
var control: ControlPoint
var opponent: ScriptedOpponent
## Id of the player's commander. It stays the same after the commander dies.
var player_commander_id := 0
## The team that has won, or NOBODY while the mission is being played.
var winner := NOBODY
## How it was won: &"hold" (held the control area) or &"eliminated" (the other
## side has no units left).
var win_reason := &""


func _init(p_def: MissionDef) -> void:
	def = p_def
	var map := def.map
	world = SimWorld.new(map)
	var center := map.control_point if map.has_control_point() else Vector2(map.get_size()) / 2.0
	control = ControlPoint.new(center, def.control_radius, def.hold_seconds)
	var starts := map.starts
	var player_start := starts[0] if starts.size() > 0 else Vector2i.ZERO
	var enemy_start := starts[1] if starts.size() > 1 else map.get_size() - Vector2i.ONE
	var commander := _spawn(PLAYER_TEAM, player_start, def.player_commander, def.player_troop)
	player_commander_id = commander.id if commander != null else 0
	_spawn(ENEMY_TEAM, enemy_start, def.enemy_commander, def.enemy_troop)
	opponent = ScriptedOpponent.new(world, control, ENEMY_TEAM, enemy_start, def.enemy_delay_seconds)
	# The second wave is the commander and the second half of the troops.
	var troops := 0
	for unit in world.units:
		if unit.team != ENEMY_TEAM:
			continue
		if not unit.type.is_hero:
			troops += 1
		if def.enemy_wave_seconds > 0.0 and (unit.type.is_hero or troops > (def.troop_count + 1) / 2):
			opponent.hold_back(unit.id, def.enemy_wave_seconds)


## Put one side on the map: the commander on the start cell, the troops around
## it, everyone facing the control point. Returns the commander.
func _spawn(team: int, start: Vector2i, commander_type: UnitType, troop_type: UnitType) -> SimUnit:
	var group: Array[SimUnit] = []
	if commander_type != null:
		group.append_array(world.add_group(commander_type, team, start, 1))
	if troop_type != null:
		group.append_array(world.add_group(troop_type, team, start, def.troop_count))
	for unit in group:
		unit.facing = SimWorld.facing_toward(Vector2i(control.center) - unit.cell)
	return group[0] if commander_type != null and not group.is_empty() else null


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
