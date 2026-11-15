class_name SendAction
extends MissionAction
## Send a side's units somewhere with an attack-move order: the units placed
## under a tag, or, with no tag, every unit of the side that can fight.

@export var team := 1
@export var tag := &""
@export var cell := Vector2i.ZERO


func run(mission: Mission) -> void:
	var ids: Array = []
	for unit in mission.tagged_units(tag) if tag != &"" else mission.world.units:
		if unit.team == team and not unit.dead and unit.type.attack_damage > 0 and not unit.type.is_harvester():
			ids.append(unit.id)
	if not ids.is_empty():
		mission.world.order_attack_move(ids, cell)
