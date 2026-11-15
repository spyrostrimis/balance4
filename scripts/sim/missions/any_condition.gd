class_name AnyCondition
extends MissionCondition
## True when at least one of its conditions is true. Its reason is that of the
## first one that is true, unless it has a reason of its own.

@export var conditions: Array[MissionCondition] = []


func check(mission: Mission) -> bool:
	for condition in conditions:
		if condition != null and condition.check(mission):
			return true
	return false


func why(mission: Mission) -> StringName:
	if reason != &"":
		return reason
	for condition in conditions:
		if condition != null and condition.check(mission):
			return condition.why(mission)
	return &""
