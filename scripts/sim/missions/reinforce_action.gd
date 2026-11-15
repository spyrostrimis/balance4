class_name ReinforceAction
extends MissionAction
## Put more units or buildings on the map.

@export var placements: Array[Placement] = []


func run(mission: Mission) -> void:
	mission.place(placements)
