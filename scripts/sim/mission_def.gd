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
## Each side gets `troop_count` troops and one commander. The player starts at
## the map's first start position, the enemy at the second.
@export var troop_count := 4
@export var player_troop: UnitType
@export var player_commander: UnitType
@export var enemy_troop: UnitType
@export var enemy_commander: UnitType

@export_group("Rules")
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
