class_name SoundBank
extends Resource
## Which sounds the game's events play (data/sounds/sound_bank.tres, made by
## tools/make_sounds.py). Replacing a sound is a matter of pointing an event
## at another file here; no code changes.

@export var events: Array[SoundEvent] = []


## The event with this name, or null.
func get_event(id: StringName) -> SoundEvent:
	for event in events:
		if event.id == id:
			return event
	return null
