class_name ObjectiveCondition
extends MissionCondition
## True once an objective is done (or, with `failed`, has failed).

@export var objective := &""
@export var failed := false


func check(mission: Mission) -> bool:
	return mission.objective_state(objective) == (Mission.FAILED if failed else Mission.DONE)
