class_name MissionHints
extends RefCounted
## The hints shown at the bottom of the map. They teach one thing at a time
## and move on once the player has done what a hint describes.
##
## Mission 1 teaches, in this order: selecting, moving, attacking, the
## commander's ability, and finally the control point. A practice mission (the
## harvest trial) teaches selecting a harvester and sending it to the rock,
## and then explains what the harvesters do on their own.

const STEPS: Array[StringName] = [&"select", &"move", &"attack", &"ability"]
## The step shown once the others are done.
const LAST := &"hold"
const PRACTICE_STEPS: Array[StringName] = [&"select", &"harvest"]
const PRACTICE_LAST := &"watch"

## Is this a practice mission?
var practice := false

var _done := {}


func _init(p_practice := false) -> void:
	practice = p_practice


## Tell the hints the player has done something: &"select", &"move",
## &"attack", &"ability" or &"harvest".
func note(what: StringName) -> void:
	_done[what] = true
	# Whoever gives an order has selected; whoever attacks knows how to move.
	if what == &"attack":
		_done[&"move"] = true
	if what == &"attack" or what == &"move" or what == &"harvest":
		_done[&"select"] = true


## The step the player is on.
func current() -> StringName:
	for step in (PRACTICE_STEPS if practice else STEPS):
		if not _done.has(step):
			return step
	return PRACTICE_LAST if practice else LAST


## The hint to show now.
func text(def: MissionDef) -> String:
	if practice:
		return _practice_text(def)
	var ability: Ability = def.player_commander.ability if def.player_commander != null else null
	match current():
		&"select":
			return "Drag a box around your troops with the left mouse button to select them."
		&"move":
			return "Right-click the ground to send them there. The Orichalcum rock is in the middle of the map, inside the ring on the minimap."
		&"attack":
			return "Press A, then left-click the ground: your troops walk there and fight whatever they meet. Right-click an enemy to attack that one."
		&"ability":
			if ability != null:
				return "Your commander can help a wounded soldier. Press Q or the %s button, then left-click the soldier." % ability.display_name
	return "Keep your troops inside the ring around the rock, with no enemy inside, for %d seconds. Or destroy every enemy." % roundi(def.hold_seconds)


func _practice_text(def: MissionDef) -> String:
	match current():
		&"select":
			return "Your harvesters are the trucks beside the refinery. Left-click one, or drag a box around both."
		&"harvest":
			return "Right-click the Orichalcum rock in the middle of the map (the gold patch on the minimap). The harvesters drive there and start work."
	var storage := def.player_refinery.storage if def.player_refinery != null else 0
	return "The harvesters now work on their own: dig, drive back, unload, return. The refinery stores up to %d; what does not fit is lost. The rock runs out." % storage
