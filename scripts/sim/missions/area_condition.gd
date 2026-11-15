class_name AreaCondition
extends MissionCondition
## True while a side has at least `count` units within `radius` cells of a
## cell (measured from the middle of `cell` to the middle of each unit's cell).

@export var team := 0
@export var cell := Vector2i.ZERO
@export var radius := 3.0
@export var count := 1


func check(mission: Mission) -> bool:
	var found := 0
	for unit in mission.world.units:
		if unit.team == team and not unit.dead \
				and Vector2(unit.cell - cell).length_squared() <= radius * radius:
			found += 1
			if found >= count:
				return true
	return false
