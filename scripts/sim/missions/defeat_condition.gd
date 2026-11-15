class_name DefeatCondition
extends MissionCondition
## True when a side has nothing left: no units at all, or, with
## `buildings_count`, no buildings and no troops (harvesters do not count).

@export var team := 1
## Count buildings and troops (a base game) rather than every unit.
@export var buildings_count := false


func _init() -> void:
	reason = &"eliminated"


func check(mission: Mission) -> bool:
	if buildings_count:
		return mission.is_beaten(team)
	return mission.world.team_size(team) == 0
