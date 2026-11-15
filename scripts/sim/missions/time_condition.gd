class_name TimeCondition
extends MissionCondition
## True once the mission has run for `seconds`.

@export var seconds := 0.0


func check(mission: Mission) -> bool:
	return mission.seconds() >= seconds - SimWorld.TICK_SECONDS * 0.5
