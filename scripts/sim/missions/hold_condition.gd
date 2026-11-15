class_name HoldCondition
extends MissionCondition
## True when a side has held the mission's control area for its whole hold
## time (see ControlPoint).

@export var team := 0


func _init() -> void:
	reason = &"hold"


func check(mission: Mission) -> bool:
	return mission.control.is_won() and mission.control.owner == team
