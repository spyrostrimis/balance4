class_name UnitType
extends Resource
## One kind of unit. Defined in data/units/*.tres.

## Short internal name, e.g. &"blue_infantry".
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
## Second line shown under the name, e.g. "Blue Infantry".
@export var role := ""
@export var max_health := 60
## Movement speed in cells per second.
@export var speed := 2.5
## How far the unit sees, in cells. It lifts the shroud this far around itself.
@export var sight := 4
@export_group("Combat")
## Health taken off the target by one hit. 0 means the unit cannot attack.
@export var attack_damage := 0
## How far it can hit, in cells. 1 reaches the eight cells around it.
@export var attack_range := 1
## Seconds between two hits.
@export var attack_interval := 1.0
## How far away it notices enemies on its own, in cells.
@export var acquire_range := 4

@export_group("Production")
## What it costs in Orichalcum, and how long a production building takes to
## turn one out, in seconds. Units that are not produced leave these alone.
@export var cost := 0
@export var build_seconds := 5.0

@export_group("Hero")
## Heroes are special units; the HUD treats them differently from troops.
@export var is_hero := false
## The ability the player can trigger, if any.
@export var ability: Ability
## The ability that is always on, if any (e.g. an aura).
@export var passive: Ability

@export_group("Harvester")
## How much Orichalcum its trailer carries. 0 means the unit is not a harvester.
@export var cargo_capacity := 0
## How much the robot carries on its back from the rock to the trailer.
@export var pack_capacity := 0
## Orichalcum the robot digs out of a deposit per second.
@export var harvest_rate := 0
## Orichalcum the robot tips from its pack into the trailer per second.
@export var load_rate := 0
## Orichalcum the truck hands over to a refinery per second.
@export var unload_rate := 0
## How long it takes to change from truck to robot, and back, in seconds.
@export var transform_seconds := 1.0
## Movement speed of the robot in cells per second. (`speed` is the truck's.)
@export var robot_speed := 2.0
## How much of every hit the robot's armour stops, in percent. The truck has none.
@export_range(0, 95) var robot_armor := 0

@export_group("Looks")
## Sprite sheet from tools/make_units.py: 8 columns (facing: 0 south, 2 west,
## 4 north, 6 east). Troops have 3 rows (standing, then the two halves of a
## step). Harvesters have 6: empty truck, loaded truck, halfway between truck
## and robot, the two halves of the robot's swing, and the robot standing.
@export var sprites: Texture2D
## Harvesters: the trailer on its own, 8 facings by 2 rows (empty, loaded),
## sprites of the same size and with the same anchor as the harvester's.
@export var trailer_sprites: Texture2D
## Size of one sprite in the sheet, in pixels.
@export var sprite_size := Vector2i(24, 24)
## Colour of the unit's dot on the minimap.
@export var minimap_color := Color(0.45, 0.72, 1.0)
## The point of a sprite that stands on the ground (its feet).
@export var sprite_anchor := Vector2i(12, 18)
## A machine (a harvester, a tank): it explodes when destroyed.
@export var is_vehicle := false
## Heroes: the face the HUD shows (from tools/make_hud.py), 44x54 pixels.
@export var portrait: Texture2D


## How many simulation ticks it takes to cross one cell, straight or diagonally.
func ticks_per_cell(diagonal: bool) -> int:
	var straight := maxi(1, roundi(SimWorld.TICKS_PER_SECOND / maxf(speed, 0.01)))
	return roundi(straight * 1.41421356) if diagonal else straight


## The same for a harvester in its robot shape.
func robot_ticks_per_cell(diagonal: bool) -> int:
	var straight := maxi(1, roundi(SimWorld.TICKS_PER_SECOND / maxf(robot_speed, 0.01)))
	return roundi(straight * 1.41421356) if diagonal else straight


## How many simulation ticks pass between two hits.
func attack_ticks() -> int:
	return maxi(1, roundi(attack_interval * SimWorld.TICKS_PER_SECOND))


func is_harvester() -> bool:
	return cargo_capacity > 0


## How many simulation ticks a harvester takes to change shape.
func transform_ticks() -> int:
	return maxi(1, roundi(transform_seconds * SimWorld.TICKS_PER_SECOND))
