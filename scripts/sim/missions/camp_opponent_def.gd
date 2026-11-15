class_name CampOpponentDef
extends OpponentDef
## A camp that holds its ground: the computer opponent (see ComputerOpponent)
## harvests, trains troops and tanks in the buildings it has, defends them,
## and repairs them, but never attacks and builds nothing new unless it has a
## headquarters. Attacks on the player come from the mission's triggers.

## How many fighters it keeps at most.
@export var army_limit := 8


func create(mission: Mission, team: int) -> RefCounted:
	var opponent := ComputerOpponent.new(mission.world, team, Mission.PLAYER_TEAM, mission.start_of(Mission.PLAYER_TEAM))
	opponent.attacks = false
	opponent.army_limit = army_limit
	return opponent
