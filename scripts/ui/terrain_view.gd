class_name TerrainView
extends Node2D
## Draws a map's terrain with one TileMapLayer per terrain type.
##
## The first terrain of the biome is the ground: one tile per cell. Every other
## terrain is drawn on top with border tiles on a grid shifted by half a cell
## (a "dual grid"): each of those tiles sits on the corner where four cells meet
## and is picked by which of the four cells have that terrain. That gives
## rounded, irregular borders from only 15 shapes per terrain.
## The atlases come from tools/make_tiles.py, which documents their layout.

const CELL := MapData.CELL_SIZE
## Tile textures repeat every this many cells.
const PERIOD := 8
## Bits of a border tile's row in its atlas: which cells around the corner have the terrain.
const TOP_LEFT := 1
const TOP_RIGHT := 2
const BOTTOM_LEFT := 4
const BOTTOM_RIGHT := 8

var map: MapData
var tile_set: TileSet
## Layer of the ground terrain, then one per overlay terrain, in drawing order.
var terrain_layers: Array[TileMapLayer] = []
var decor_layer: TileMapLayer


func show_map(p_map: MapData) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	terrain_layers.clear()
	decor_layer = null
	map = p_map
	var biome := map.biome
	var size := map.get_size()
	tile_set = build_tile_set(biome)

	var ground := _add_layer("Ground_%s" % biome.terrains[0].id, Vector2.ZERO)
	for y in size.y:
		for x in size.x:
			ground.set_cell(Vector2i(x, y), 0, Vector2i(posmod(x, PERIOD), posmod(y, PERIOD)))

	if biome.decor != null and biome.decor_density > 0.0:
		decor_layer = _add_layer("Decor", Vector2.ZERO, false)
		var decor_source := biome.terrains.size()
		var count := biome.decor.get_width() / CELL
		for y in size.y:
			for x in size.x:
				var pick := decor_at(map, Vector2i(x, y), biome.decor_density, count)
				if pick.x >= 0:
					decor_layer.set_cell(Vector2i(x, y), decor_source, Vector2i(pick.x, 0), pick.y)

	var half := Vector2(-CELL / 2.0, -CELL / 2.0)
	for index in range(1, biome.terrains.size()):
		var layer := _add_layer("Overlay_%s" % biome.terrains[index].id, half)
		for j in size.y + 1:
			for i in size.x + 1:
				var mask := corner_mask(map, index, i, j)
				if mask != 0:
					layer.set_cell(Vector2i(i, j), index, border_tile(i, j, mask))


func _add_layer(layer_name: String, offset: Vector2, is_terrain := true) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.position = offset
	add_child(layer)
	if is_terrain:
		terrain_layers.append(layer)
	return layer


## One TileSet for the whole biome. Source id = index of the terrain in the
## biome; the decor atlas, if any, is the source after the last terrain.
static func build_tile_set(biome: Biome) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	for index in biome.terrains.size():
		# Row 0 of a border atlas is the empty "no corner" row.
		ts.add_source(_atlas_source(biome.terrains[index].tiles, 0 if index == 0 else 1), index)
	if biome.decor != null:
		ts.add_source(_atlas_source(biome.decor, 0), biome.terrains.size())
	return ts


static func _atlas_source(texture: Texture2D, first_row: int) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(CELL, CELL)
	var columns := texture.get_width() / CELL
	var rows := texture.get_height() / CELL
	for y in range(first_row, rows):
		for x in columns:
			source.create_tile(Vector2i(x, y))
	return source


## Which of the four cells around grid corner (i, j) have the given terrain.
## Corner (i, j) is the top-left corner of cell (i, j). Cells outside the map
## count as their nearest cell inside it, so terrain runs cleanly to the edge.
static func corner_mask(p_map: MapData, terrain_index: int, i: int, j: int) -> int:
	var mask := 0
	if p_map.terrain_index_clamped(Vector2i(i - 1, j - 1)) == terrain_index:
		mask |= TOP_LEFT
	if p_map.terrain_index_clamped(Vector2i(i, j - 1)) == terrain_index:
		mask |= TOP_RIGHT
	if p_map.terrain_index_clamped(Vector2i(i - 1, j)) == terrain_index:
		mask |= BOTTOM_LEFT
	if p_map.terrain_index_clamped(Vector2i(i, j)) == terrain_index:
		mask |= BOTTOM_RIGHT
	return mask


## Atlas position of the border tile for grid corner (i, j) with the given mask.
static func border_tile(i: int, j: int, mask: int) -> Vector2i:
	return Vector2i(posmod(i, PERIOD) + PERIOD * posmod(j, PERIOD), mask)


## Which prop, if any, decorates a cell. Returns (prop index, tile transform),
## or (-1, 0) for none. Only open ground gets props: the cell and its eight
## neighbours must all be ground. The choice depends only on the cell, so a map
## always looks the same.
static func decor_at(p_map: MapData, cell: Vector2i, density: float, count: int) -> Vector2i:
	if count <= 0:
		return Vector2i(-1, 0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if p_map.terrain_index_clamped(cell + Vector2i(dx, dy)) != 0:
				return Vector2i(-1, 0)
	var h := cell_hash(cell)
	if float(h % 10000) / 10000.0 >= density:
		return Vector2i(-1, 0)
	var prop := (h / 10000) % count
	# Mirroring across the diagonal keeps the light coming from the north-west.
	var transform := TileSetAtlasSource.TRANSFORM_TRANSPOSE if (h / 1000000) % 2 == 1 else 0
	return Vector2i(prop, transform)


## A well-mixed, repeatable non-negative number for a cell.
static func cell_hash(cell: Vector2i) -> int:
	var h := (cell.x * 374761393 + cell.y * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 2246822519) & 0xFFFFFFFF
	return (h ^ (h >> 15)) & 0x7FFFFFFF
