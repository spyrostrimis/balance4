class_name MissionDef
extends Resource
## What a mission is made of: the map, the two forces and the rules for
## winning. Defined in data/missions/*.tres.

## Short internal name, e.g. &"first_claim_blue".
@export var id: StringName
@export var number := 1
## Name shown to the player.
@export var display_name := ""
@export var map: MapData

@export_group("Forces")
## What the two sides are called on screen, and their HUD colours.
@export var player_side := ""
@export var enemy_side := ""
@export var player_color := Color(0.45, 0.72, 1.0)
@export var enemy_color := Color(1.0, 0.45, 0.35)
## Each side gets `troop_count` troops and one commander (either can be left
## out by giving no type). The player starts at
## the map's first start position, the enemy at the second.
@export var troop_count := 4
## How many troops the enemy gets, if not the same number: -1 means `troop_count`.
@export var enemy_troop_count := -1
@export var player_troop: UnitType
@export var player_commander: UnitType
@export var enemy_troop: UnitType
@export var enemy_commander: UnitType

@export_group("Economy")
## The player's headquarters, or null for a mission without base building. It
## is put on the ground nearest to the player's start that can be built on,
## before the refinery. What the player can build is listed in its type.
@export var player_headquarters: BuildingType
## Orichalcum in the player's store at the start (never more than fits).
@export var start_orichalcum := 0
## How many times richer than usual the map's Orichalcum rock is.
@export_range(1, 10) var ore_richness := 1
## The player's refinery, or null for a mission without one. It is put on the
## ground nearest to the player's start that can be built on.
@export var player_refinery: BuildingType
## The player's harvesters: their type and how many. They start beside the
## refinery.
@export var player_harvester: UnitType
@export var harvester_count := 0

@export_group("Enemy base")
## The same for the enemy, at the map's second start position. Only a
## skirmish gives the enemy a base.
@export var enemy_headquarters: BuildingType
@export var enemy_refinery: BuildingType
@export var enemy_harvester: UnitType
@export var enemy_harvester_count := 0
@export var enemy_start_orichalcum := 0

@export_group("Rules")
## A practice mission has no way to win or lose. The player leaves it with
## Esc. If it has enemy troops they are raiders: after `enemy_delay_seconds`
## they go for the player's harvesters (see Raiders).
@export var practice := false
## A skirmish: both sides have a base and the enemy is the computer opponent
## (see ComputerOpponent). There is no control area to hold: a side loses
## when it has no buildings and no troops left (harvesters do not count).
@export var skirmish := false
## Radius of the control area around the map's control point, in cells.
@export var control_radius := 5.0
## How long a side must hold the control area on its own to win, in seconds.
@export var hold_seconds := 45.0
## How long the scripted opponent waits before it sets off, in seconds.
@export var enemy_delay_seconds := 20.0
## The opponent attacks in two waves: half of its troops first, then the rest
## with its commander this many seconds later. 0 sends everyone at once.
@export var enemy_wave_seconds := 8.0
## One line for the HUD saying what to do.
@export var objective := ""


## How many troops the enemy starts with.
func enemy_troops() -> int:
	return troop_count if enemy_troop_count < 0 else enemy_troop_count


## Does the player have a base to build up in this mission?
func has_base() -> bool:
	return player_headquarters != null


## Is this a practice mission in which raiders come for the harvesters?
func has_raid() -> bool:
	return practice and enemy_troop != null and enemy_troops() > 0
