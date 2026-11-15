class_name OpponentDef
extends Resource
## Who plays a side that is not the player's (see MissionSide.opponent). Each
## kind makes the object that plays the side; that object has a tick()
## method, which the mission calls before every tick of the world.


func create(_mission: Mission, _team: int) -> RefCounted:
	return null
