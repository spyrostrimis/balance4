class_name TerrainType
extends Resource
## One kind of ground (grass, water, rock...). Defined in data/terrain/*.tres.

## Short internal name, unique within a biome, e.g. &"grass".
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
## The single character that stands for this terrain in a map's rows.
@export var symbol := ""
## Can ground units cross it?
@export var walkable := true
## Can buildings stand on it?
@export var buildable := false
## Colour of one cell of this terrain on the minimap.
@export var minimap_color := Color.MAGENTA
## Tile atlas made by tools/make_tiles.py. The first terrain of a biome uses a
## 256x256 ground atlas; all others use a 2048x512 border atlas.
@export var tiles: Texture2D
