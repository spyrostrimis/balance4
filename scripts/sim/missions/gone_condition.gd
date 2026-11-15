class_name GoneCondition
extends MissionCondition
## True once everything a mission placed under a tag (see Placement.tag) has
## been destroyed: its units dead and its buildings gone.

@export var tag := &""


func _init() -> void:
	reason = &"eliminated"


func check(mission: Mission) -> bool:
	return mission.tagged_left(tag) == 0
