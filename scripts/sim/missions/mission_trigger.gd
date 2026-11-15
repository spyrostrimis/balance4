class_name MissionTrigger
extends Resource
## When something happens in a mission, do something: show a message, send
## reinforcements, show an objective, end the mission. A trigger fires once.

@export var id := &""
## Fires once this is true. Null: at the start.
@export var when: MissionCondition
## Seconds to wait after `when` first becomes true before firing.
@export var delay_seconds := 0.0
@export var actions: Array[MissionAction] = []
