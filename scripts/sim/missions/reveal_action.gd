class_name RevealAction
extends MissionAction
## Lift the shroud for a side around a cell.

@export var team := 0
@export var cell := Vector2i.ZERO
@export var radius := 5


func run(mission: Mission) -> void:
	mission.world.shroud_for(team).reveal_circle(cell, radius)
