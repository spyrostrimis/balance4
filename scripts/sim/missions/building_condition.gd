class_name BuildingCondition
extends MissionCondition
## True while a side has at least `count` buildings of a type (any type if
## none is given).

@export var team := 0
@export var type: BuildingType
@export var count := 1


func check(mission: Mission) -> bool:
	var found := 0
	for building in mission.world.buildings:
		if building.team == team and (type == null or building.type == type):
			found += 1
	return found >= count
