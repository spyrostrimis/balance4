class_name BuildingType
extends Resource
## One kind of building. Defined in data/buildings/*.tres.
##
## A headquarters lists the buildings its side can construct (`builds`); a
## production building lists the units it turns out (`produces`). See
## Production for how both are queued, paid for and placed.

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

@export_group("Building")
## What it costs in Orichalcum, and how long it takes to construct, in seconds.
@export var cost := 0
@export var build_seconds := 10.0
## How much damage it takes before it is destroyed.
@export var max_health := 500
## Power it makes (above 0) or uses (below 0).
@export var power := 0
## The buildings (BuildingType) a side that owns this one can construct. A
## building with anything in this list is a headquarters.
@export var builds: Array[Resource] = []
## The units (UnitType) this building produces.
@export var produces: Array[Resource] = []
## One line for the build menu saying what the building is for.
@export var blurb := ""

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
