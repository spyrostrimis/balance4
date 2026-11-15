class_name AllCondition
extends MissionCondition
## True when every one of its conditions is true.

@export var conditions: Array[MissionCondition] = []


func check(mission: Mission) -> bool:
	for condition in conditions:
		if condition == null or not condition.check(mission):
			return false
	return true
