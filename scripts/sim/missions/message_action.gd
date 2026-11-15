class_name MessageAction
extends MissionAction
## Show a message to the player, e.g. a line from a character.

## Who says it, e.g. "Field Commander". Empty for a plain message.
@export var speaker := ""
@export_multiline var text := ""
## The speaker's face in the message box. Without one, the HUD uses the
## portrait of a hero of the player's whose name is the speaker's, if any.
@export var portrait: Texture2D


func run(mission: Mission) -> void:
	mission.add_message(speaker, text, portrait)
