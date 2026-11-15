class_name MissionHints
extends RefCounted
## The hints shown at the bottom of the map. They teach one thing at a time
## and move on once the player has done what a hint describes.
##
## Mission 1 teaches, in this order: selecting, moving, attacking, the
## commander's ability, and finally the control point. A practice mission (the
## harvest trial, the raid trial) teaches selecting a harvester and sending it
## to the rock, and then explains what the harvesters do on their own and, if
## raiders are coming, what to do about them.

const STEPS: Array[StringName] = [&"select", &"move", &"attack", &"ability"]
## The step shown once the others are done.
const LAST := &"hold"
const PRACTICE_STEPS: Array[StringName] = [&"select", &"harvest"]
const PRACTICE_LAST := &"watch"
## A practice mission with a base goes on to teach building: queue a
## building, place it, and produce a unit.
const BASE_STEPS: Array[StringName] = [&"select", &"harvest", &"build", &"place", &"train"]
const BASE_LAST := &"power"

## Is this a practice mission?
var practice := false
## Does the player have a base to build up in it?
var base := false

var _done := {}


func _init(p_practice := false, p_base := false) -> void:
	practice = p_practice
	base = p_base


## Tell the hints the player has done something: &"select", &"move",
## &"attack", &"ability", &"harvest", &"build", &"place" or &"train".
func note(what: StringName) -> void:
	_done[what] = true
	# Whoever gives an order has selected; whoever attacks knows how to move.
	if what == &"attack":
		_done[&"move"] = true
	if what == &"attack" or what == &"move" or what == &"harvest":
		_done[&"select"] = true


## The step the player is on.
func current() -> StringName:
	if base:
		for step in BASE_STEPS:
			if not _done.has(step):
				return step
		return BASE_LAST
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
			return "Press F, then left-click the ground: your troops walk there and fight whatever they meet. Right-click an enemy to attack that one."
		&"ability":
			if ability != null:
				return "Your commander can help a wounded soldier. Press Q or the %s button, then left-click the soldier." % ability.display_name
	return "Keep your troops inside the ring around the rock, with no enemy inside, for %d seconds. Or destroy every enemy." % roundi(def.hold_seconds)


func _base_text() -> String:
	match current():
		&"select":
			return "Your harvester is the truck beside the refinery. Left-click it."
		&"harvest":
			return "Right-click the Orichalcum rock in the middle of the map (the gold patch on the minimap). Everything you build is paid for with Orichalcum."
		&"build":
			return "The build menu is at the right. Click Generator: your headquarters starts on it, and it is paid for bit by bit while it is built."
		&"place":
			return "When it is ready, click 'Place the Generator' and then a spot on the stony building ground by your headquarters. Green squares mean it fits."
		&"train":
			return "Now build a Barracks and place it. It gets a tab of its own in the build menu: open it and click a soldier to train one."
	return "Buildings use power and Generators make it: use more than you make and everything builds at half speed. A Workshop builds more harvesters."


func _practice_text(def: MissionDef) -> String:
	if base:
		return _base_text()
	match current():
		&"select":
			return "Your harvesters are the trucks beside the refinery. Left-click one, or drag a box around both."
		&"harvest":
			return "Right-click the Orichalcum rock in the middle of the map (the gold patch on the minimap). The harvesters drive there and start work."
	var storage := def.player_refinery.storage if def.player_refinery != null else 0
	if def.has_raid():
		return "Raiders are coming for your harvesters. A harvester that is attacked unfolds and guards its trailer. Send your troops to help it: if it dies, the raiders take the trailer's Orichalcum."
	return "The harvesters now work on their own: the robot fills the trailer, the truck takes it to the refinery. The refinery stores up to %d; when it is full they wait with their load." % storage
