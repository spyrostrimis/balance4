class_name GiveAction
extends MissionAction
## Put Orichalcum into a side's store, as far as it fits (a supply column
## arrives, a deposit is found).

@export var team := 0
@export var amount := 0


func run(mission: Mission) -> void:
	var world := mission.world
	world.stored[team] = mini(world.stored_for(team) + amount, maxi(world.storage_for(team), world.stored_for(team)))
