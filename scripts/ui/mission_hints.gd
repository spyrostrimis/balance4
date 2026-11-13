class_name MissionHints
extends RefCounted
## The hints of Mission 1. They teach one thing at a time, in this order:
## selecting, moving, attacking, the commander's ability, and finally the
## control point. A hint goes away once the player has done what it describes.

const STEPS: Array[StringName] = [&"select", &"move", &"attack", &"ability"]
## The step shown once the others are done.
const LAST := &"hold"

var _done := {}


## Tell the hints the player has done something: &"select", &"move",
## &"attack" or &"ability".
func note(what: StringName) -> void:
	_done[what] = true
	# Whoever gives an order has selected; whoever attacks knows how to move.
	if what == &"attack":
		_done[&"move"] = true
	if what == &"attack" or what == &"move":
		_done[&"select"] = true


## The step the player is on.
func current() -> StringName:
	for step in STEPS:
		if not _done.has(step):
			return step
	return LAST


## The hint to show now.
func text(def: MissionDef) -> String:
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
