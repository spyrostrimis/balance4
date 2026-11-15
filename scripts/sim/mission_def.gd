class_name MissionDef
extends Resource
## What a mission is made of: the map, the sides and who plays them, the
## forces placed on the map, the objectives, the triggers and the hints.
## Defined in data/missions/*.tres; the parts are in scripts/sim/missions/.

## How the mission is presented. The rules come from the objectives; the kind
## only decides what the HUD shows and how the mission is named.
enum Kind {
	## A mission of the story, e.g. Mission 1.
	STORY,
	## A practice mission: no way to win or lose; the player leaves it from the
	## pause menu. If an enemy is in it, it is raiders.
	PRACTICE,
	## A skirmish against the computer: both sides have a base.
	SKIRMISH,
}

## Short internal name, e.g. &"first_claim_blue".
@export var id: StringName
@export var number := 1
## Name shown to the player.
@export var display_name := ""
@export var kind := Kind.STORY
@export var map: MapData

## The sides; the first is the player's (team 0), the second the enemy's.
@export var sides: Array[MissionSide] = []
## What is on the map at the start. Buildings are put down first (nearest
## building ground to where they are placed), then units, in this order.
@export var forces: Array[Placement] = []
## How many times richer than usual the map's Orichalcum rock is.
@export_range(1, 10) var ore_richness := 1

@export_group("Control area")
## Radius of the control area around the map's control point, in cells.
@export var control_radius := 5.0
## How long a side must hold the control area on its own to win it, in
## seconds (see HoldCondition). 0: the mission has no control area.
@export var hold_seconds := 0.0

@export_group("Rules")
## What the player must do. See Objective for how they decide the outcome.
@export var objectives: Array[Objective] = []
## What happens during the mission. See MissionTrigger.
@export var triggers: Array[MissionTrigger] = []
## What the hint box teaches, step by step. See MissionHints.
@export var hints: HintList


## A practice mission (see Kind).
var practice: bool:
	get: return kind == Kind.PRACTICE
## A skirmish against the computer (see Kind).
var skirmish: bool:
	get: return kind == Kind.SKIRMISH
## The player's and the enemy's names and colours.
var player_side: String:
	get: return side_name(Mission.PLAYER_TEAM)
var enemy_side: String:
	get: return side_name(Mission.ENEMY_TEAM)
var player_color: Color:
	get: return side_color(Mission.PLAYER_TEAM)
var enemy_color: Color:
	get: return side_color(Mission.ENEMY_TEAM)
## The line the HUD shows as the objective: the first primary objective that
## is not hidden at the start.
var objective: String:
	get:
		for item in objectives:
			if item.primary and not item.hidden:
				return item.text
		return ""


func side_name(team: int) -> String:
	return sides[team].name if team < sides.size() else ""


func side_color(team: int) -> Color:
	return sides[team].color if team < sides.size() else Color.WHITE


## The types placed for a side at the start, in order.
func placed_types(team: int) -> Array[Resource]:
	var out: Array[Resource] = []
	for placement in forces:
		if placement.team == team and placement.type != null:
			out.append(placement.type)
	return out


## The unit type of a side's first hero, or null.
func hero_type(team: int) -> UnitType:
	for type in placed_types(team):
		if type is UnitType and (type as UnitType).is_hero:
			return type
	return null


## The player's commander's type, or null.
var player_commander: UnitType:
	get: return hero_type(Mission.PLAYER_TEAM)


## Does the player have a base to build up in this mission (a headquarters)?
func has_base() -> bool:
	for type in placed_types(Mission.PLAYER_TEAM):
		if type is BuildingType and not (type as BuildingType).builds.is_empty():
			return true
	return false


## Does the mission have a control area to hold?
func has_control() -> bool:
	return hold_seconds > 0.0 and control_radius > 0.0


## Is this a practice mission in which raiders come for the harvesters?
func has_raid() -> bool:
	return practice and not placed_types(Mission.ENEMY_TEAM).is_empty()


## The objective with this id, or null.
func get_objective(objective_id: StringName) -> Objective:
	for item in objectives:
		if item.id == objective_id:
			return item
	return null


## What is wrong with this mission's data: an empty list means nothing.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if map == null:
		out.append("no map")
	if sides.size() < 2:
		out.append("fewer than two sides")
	var ids := {}
	for item in objectives:
		if item.id == &"" or ids.has(item.id):
			out.append("objective without a unique id: '%s'" % item.text)
		ids[item.id] = true
	for placement in forces:
		if placement.type == null:
			out.append("a placement without a type")
		elif not (placement.type is UnitType or placement.type is BuildingType):
			out.append("a placement of something that is neither a unit nor a building")
		if placement.team >= sides.size():
			out.append("a placement for a side that does not exist")
	for side in sides:
		if map != null and side.start >= map.starts.size():
			out.append("side %s starts at a start position the map has not got" % side.name)
	return out
