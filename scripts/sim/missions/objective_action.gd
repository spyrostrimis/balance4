class_name ObjectiveAction
extends MissionAction
## Show a hidden objective. From then on it is checked.

@export var objective := &""


func run(mission: Mission) -> void:
	mission.show_objective(objective)
