class_name SoundEvent
extends Resource
## One thing the game can sound: its name, the files it plays (one picked at
## random each time), how loud, how much the pitch may vary, which audio bus,
## and how soon it may sound again. Listed in a SoundBank.

## The event's name, e.g. &"shot" or &"music_menu". The code plays events by name.
@export var id: StringName
@export var streams: Array[AudioStream] = []
@export var volume_db := 0.0
## How far the pitch may go up or down each time, e.g. 0.08 for 8%.
@export_range(0.0, 0.5) var pitch_variation := 0.0
## &"Effects" or &"Music".
@export var bus := &"Effects"
## The shortest time between two plays of this event, in seconds (more are skipped).
@export var min_gap := 0.05
