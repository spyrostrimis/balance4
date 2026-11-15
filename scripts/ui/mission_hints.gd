class_name MissionHints
extends RefCounted
## The hints shown at the bottom of the map. They teach one thing at a time
## and move on once the player has done what a hint describes.
##
## What they teach is data: the mission's HintList (data/hints/), one Hint per
## step, each done when its condition is true. A step that is done stays
## done. The last step, the one without a condition, stays up for good.

var mission: Mission
var _done := {}


func _init(p_mission: Mission) -> void:
	mission = p_mission


## The hints of the mission, in order (none if it has no HintList).
func steps() -> Array[Hint]:
	if mission.def.hints == null:
		return []
	return mission.def.hints.hints


## Tell the hints the player has done something (see Mission.note()).
func note(what: StringName) -> void:
	mission.note(what)


## The step the player is on, or null when the mission has no hints.
func current_hint() -> Hint:
	var last: Hint = null
	for hint in steps():
		last = hint
		if _done.has(hint.id):
			continue
		if hint.done_when != null and hint.done_when.check(mission):
			_done[hint.id] = true
			continue
		return hint
	return last


## The id of the step the player is on, e.g. &"select"; &"" with no hints.
func current() -> StringName:
	var hint := current_hint()
	return hint.id if hint != null else &""


## The hint to show now, with the mission's values filled in.
func text() -> String:
	var hint := current_hint()
	return fill(hint.text, mission) if hint != null else ""


## A hint's text with {player}, {enemy}, {hold_seconds}, {storage} and
## {ability} replaced by the mission's values.
static func fill(template: String, p_mission: Mission) -> String:
	var def := p_mission.def
	var commander := def.player_commander
	var ability: Ability = commander.ability if commander != null else null
	return template.format({
		"player": def.player_side,
		"enemy": def.enemy_side,
		"hold_seconds": roundi(def.hold_seconds),
		"storage": p_mission.world.storage_for(Mission.PLAYER_TEAM),
		"ability": ability.display_name if ability != null else "",
	})
