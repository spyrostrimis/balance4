class_name EventCondition
extends MissionCondition
## True once the player has done something in the game screen: &"select",
## &"move", &"attack", &"ability", &"harvest", &"build", &"place" or &"train"
## (see Mission.note()).

@export var event := &""


func check(mission: Mission) -> bool:
	return mission.has_done(event)
