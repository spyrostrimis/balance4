class_name DepositView
extends TileMapLayer
## Draws the mined-out parts of the Orichalcum deposits: bare rock with the
## crystals dug out, over every deposit cell that has been emptied.
##
## It uses the same half-cell-shifted border tiles as the terrain (see
## TerrainView), with the same outline as the rock underneath, so a spent cell
## at the edge of a formation covers it exactly.

const CELL := MapData.CELL_SIZE

var world: SimWorld
## The cells drawn as spent so far: cell -> true.
var spent := {}
var _seen := 0        # how much of world.spent_log has been drawn


func setup(p_world: SimWorld) -> void:
	world = p_world
	spent.clear()
	_seen = 0
	clear()
	position = Vector2(-CELL / 2.0, -CELL / 2.0)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	for terrain in world.map.biome.terrains:
		if terrain.spent_tiles != null:
			ts.add_source(TerrainView._atlas_source(terrain.spent_tiles, 1), 0)
			break
	tile_set = ts
	visible = ts.get_source_count() > 0
	refresh()


## Redraw around the cells emptied since the last call.
func refresh() -> void:
	if world == null or not visible:
		return
	var log := world.spent_log
	while _seen < log.size():
		var cell := log[_seen]
		_seen += 1
		spent[cell] = true
		for dj in 2:
			for di in 2:
				_update_corner(cell.x + di, cell.y + dj)


## Which of the four cells around grid corner (i, j) are spent, in the same
## bits as TerrainView.corner_mask.
static func corner_mask(p_spent: Dictionary, i: int, j: int) -> int:
	var mask := 0
	if p_spent.has(Vector2i(i - 1, j - 1)):
		mask |= TerrainView.TOP_LEFT
	if p_spent.has(Vector2i(i, j - 1)):
		mask |= TerrainView.TOP_RIGHT
	if p_spent.has(Vector2i(i - 1, j)):
		mask |= TerrainView.BOTTOM_LEFT
	if p_spent.has(Vector2i(i, j)):
		mask |= TerrainView.BOTTOM_RIGHT
	return mask


func _update_corner(i: int, j: int) -> void:
	var mask := corner_mask(spent, i, j)
	if mask == 0:
		erase_cell(Vector2i(i, j))
	else:
		set_cell(Vector2i(i, j), 0, TerrainView.border_tile(i, j, mask))
