class_name Biome
extends Resource
## A set of terrain types that belong together (forest, desert).
## Defined in data/biomes/*.tres.

@export var id: StringName
@export var display_name := ""
## Terrain types in drawing order. The first one is the ground that lies under
## everything; each later one is drawn on top of the ones before it.
@export var terrains: Array[TerrainType] = []
## Optional row of small props (32 px each) scattered on open ground. Looks only.
@export var decor: Texture2D
## Share of open ground cells that get a prop, 0 to 1.
@export_range(0.0, 1.0) var decor_density := 0.0

var _by_symbol := {}


## Index into [member terrains] of the terrain with this map symbol, or -1.
func terrain_index_for_symbol(symbol: String) -> int:
	if _by_symbol.size() != terrains.size():
		_by_symbol.clear()
		for i in terrains.size():
			_by_symbol[terrains[i].symbol] = i
	return _by_symbol.get(symbol, -1)


## Index of the terrain with this id, or -1.
func terrain_index_for_id(terrain_id: StringName) -> int:
	for i in terrains.size():
		if terrains[i].id == terrain_id:
			return i
	return -1


## Human-readable problems with this definition. Empty when it is valid.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if terrains.is_empty():
		out.append("biome '%s' has no terrain types" % id)
	var ids := {}
	var symbols := {}
	for i in terrains.size():
		var t := terrains[i]
		if t == null:
			out.append("terrain %d is missing" % i)
			continue
		if t.symbol.length() != 1:
			out.append("terrain '%s' needs a one-character symbol" % t.id)
		if ids.has(t.id):
			out.append("terrain id '%s' is used twice" % t.id)
		if symbols.has(t.symbol):
			out.append("symbol '%s' is used twice" % t.symbol)
		ids[t.id] = true
		symbols[t.symbol] = true
		if t.tiles == null:
			out.append("terrain '%s' has no tile atlas" % t.id)
	return out
