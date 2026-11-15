class_name MissionCondition
extends Resource
## Something that is true or not at a moment of a mission. Objectives,
## triggers and hints use conditions to decide when they are done or fire.
## Conditions are data shared by every playing of a mission, so they keep no
## state of their own: everything they need is in the Mission.

## What to report as the reason when this decides the outcome of a mission,
## e.g. &"hold" or &"eliminated" (the result screen words it).
@export var reason := &""


func check(_mission: Mission) -> bool:
	return false


## The reason to report when this is true (for AnyCondition: the reason of
## the condition that is true).
func why(_mission: Mission) -> StringName:
	return reason
