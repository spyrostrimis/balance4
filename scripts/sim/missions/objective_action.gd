class_name ObjectiveAction
extends MissionAction
## Show a hidden objective. From then on it is checked. Unless told not to,
## the player is also told about it in a message.

@export var objective := &""
@export var announce := true


func run(mission: Mission) -> void:
	mission.show_objective(objective)
	var item := mission.def.get_objective(objective)
	if announce and item != null:
		mission.add_message("New objective", item.text)
