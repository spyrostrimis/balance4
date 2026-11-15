class_name RaidersDef
extends OpponentDef
## Raiders (see Raiders): after a delay they go for the other side's
## harvesters and take what is in their trailers.

@export var delay_seconds := 45.0


func create(mission: Mission, team: int) -> RefCounted:
	return Raiders.new(mission.world, team, delay_seconds)
