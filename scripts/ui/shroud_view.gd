class_name ShroudView
extends TileMapLayer
## Draws the black cover over cells the player has not explored yet.
##
## It uses the same half-cell-shifted border tiles as the terrain (see
## TerrainView), so the edge of the explored area is ragged instead of square.

const CELL := MapData.CELL_SIZE
const ATLAS := preload("res://assets/tiles/shroud.png")

var shroud: Shroud
var _seen := 0        # how much of shroud.revealed_log has been drawn


func setup(p_shroud: Shroud) -> void:
	shroud = p_shroud
	if tile_set == null:
		var ts := TileSet.new()
		ts.tile_size = Vector2i(CELL, CELL)
		ts.add_source(TerrainView._atlas_source(ATLAS, 1), 0)
		tile_set = ts
	position = Vector2(-CELL / 2.0, -CELL / 2.0)
	clear()
	for j in shroud.size.y + 1:
		for i in shroud.size.x + 1:
			_update_corner(i, j)
	_seen = shroud.revealed_log.size()


## Redraw around the cells revealed since the last call.
func refresh() -> void:
	if shroud == null:
		return
	var revealed := shroud.revealed_log
	while _seen < revealed.size():
		var cell := revealed[_seen]
		_seen += 1
		for dj in 2:
			for di in 2:
				_update_corner(cell.x + di, cell.y + dj)


## Which of the four cells around grid corner (i, j) are still unexplored,
## in the same bits as TerrainView.corner_mask.
static func corner_mask(p_shroud: Shroud, i: int, j: int) -> int:
	var mask := 0
	if not p_shroud.is_explored_clamped(Vector2i(i - 1, j - 1)):
		mask |= TerrainView.TOP_LEFT
	if not p_shroud.is_explored_clamped(Vector2i(i, j - 1)):
		mask |= TerrainView.TOP_RIGHT
	if not p_shroud.is_explored_clamped(Vector2i(i - 1, j)):
		mask |= TerrainView.BOTTOM_LEFT
	if not p_shroud.is_explored_clamped(Vector2i(i, j)):
		mask |= TerrainView.BOTTOM_RIGHT
	return mask


func _update_corner(i: int, j: int) -> void:
	var mask := corner_mask(shroud, i, j)
	if mask == 0:
		erase_cell(Vector2i(i, j))
	else:
		set_cell(Vector2i(i, j), 0, TerrainView.border_tile(i, j, mask))
