class_name ComputerOpponentDef
extends OpponentDef
## The computer opponent of a skirmish (see ComputerOpponent), playing
## against the player.


func create(mission: Mission, team: int) -> RefCounted:
	return ComputerOpponent.new(mission.world, team, Mission.PLAYER_TEAM, mission.start_of(Mission.PLAYER_TEAM))
