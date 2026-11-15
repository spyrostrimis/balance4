class_name RushOpponentDef
extends OpponentDef
## The opponent of Mission 1 (see ScriptedOpponent): after a delay it sends
## its force to the control area, in two waves.

## Seconds before it sets off.
@export var delay_seconds := 20.0
## The second wave (its heroes and the second half of its troops) follows
## this many seconds later. 0 sends everyone at once.
@export var wave_seconds := 8.0


func create(mission: Mission, team: int) -> RefCounted:
	var world := mission.world
	var opponent := ScriptedOpponent.new(world, mission.control, team, mission.start_of(team), delay_seconds)
	if wave_seconds <= 0.0:
		return opponent
	var troops := 0
	for unit in world.units:
		if unit.team == team and not unit.type.is_hero:
			troops += 1
	var seen := 0
	for unit in world.units:
		if unit.team != team:
			continue
		if not unit.type.is_hero:
			seen += 1
		if unit.type.is_hero or seen > (troops + 1) / 2:
			opponent.hold_back(unit.id, wave_seconds)
	return opponent
