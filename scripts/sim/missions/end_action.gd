class_name EndAction
extends MissionAction
## End the mission: `winner` wins, for `reason` (worded on the result screen).

@export var winner := 0
@export var reason := &""


func run(mission: Mission) -> void:
	mission.finish(winner, reason)
