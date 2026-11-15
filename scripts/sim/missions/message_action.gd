class_name MessageAction
extends MissionAction
## Show a message to the player, e.g. a line from a character.

## Who says it, e.g. "Field Commander". Empty for a plain message.
@export var speaker := ""
@export_multiline var text := ""


func run(mission: Mission) -> void:
	mission.add_message(speaker, text)
