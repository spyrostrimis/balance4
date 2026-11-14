class_name BuildingType
extends Resource
## One kind of building. Defined in data/buildings/*.tres.
##
## M4 has one building, the refinery, and it is put on the map by the mission.
## Placing buildings, their cost, their health and production come with M5.

## Short internal name, e.g. &"blue_refinery".
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
## Second line shown under the name, e.g. "Blue Refinery".
@export var role := ""
## How many cells it covers, across and down. Units cannot enter them.
@export var footprint := Vector2i(2, 2)
## How far it sees, in cells, from each cell it covers.
@export var sight := 3

@export_group("Economy")
## Do harvesters unload here?
@export var is_refinery := false
## How much Orichalcum it adds to its side's storage.
@export var storage := 0

@export_group("Looks")
## Picture of the building on its foundation, from tools/make_buildings.py.
@export var sprite: Texture2D
## Where the top-left corner of the footprint is inside the picture, in pixels.
@export var sprite_origin := Vector2i.ZERO
## Colour of the building on the minimap.
@export var minimap_color := Color(0.45, 0.72, 1.0)
