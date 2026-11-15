class_name StoreCondition
extends MissionCondition
## True while a side has at least `amount` Orichalcum in store.

@export var team := 0
@export var amount := 0


func check(mission: Mission) -> bool:
	return mission.world.stored_for(team) >= amount
