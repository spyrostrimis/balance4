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
## Sprite sheet from tools/make_units.py: 8 columns (facing: 0 south, 2 west,
## 4 north, 6 east) and 3 rows (standing, then the two halves of a step).
@export var sprites: Texture2D
## Size of one sprite in the sheet, in pixels.
@export var sprite_size := Vector2i(24, 24)
## Colour of the unit's dot on the minimap.
@export var minimap_color := Color(0.45, 0.72, 1.0)
## The point of a sprite that stands on the ground (its feet).
@export var sprite_anchor := Vector2i(12, 18)


## How many simulation ticks it takes to cross one cell, straight or diagonally.
func ticks_per_cell(diagonal: bool) -> int:
	var straight := maxi(1, roundi(SimWorld.TICKS_PER_SECOND / maxf(speed, 0.01)))
	return roundi(straight * 1.41421356) if diagonal else straight
