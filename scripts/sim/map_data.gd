class_name MapData
extends Resource
## A map: a grid of terrain cells. Stored in data/maps/*.tres.
##
## The grid is written as text, one string per row and one character per cell;
## each character is the symbol of a terrain type in the map's biome.

## Size of one grid cell in pixels.
const CELL_SIZE := 32

@export var display_name := ""
@export var biome: Biome
## Cells where each side's force starts. The player's squad starts at the first.
@export var starts: Array[Vector2i] = []
## The point the two sides fight over (the middle of the Orichalcum rock), in
## cells; whole numbers are grid corners. Negative means the map has none.
@export var control_point := Vector2(-1, -1)
@export var rows: PackedStringArray = []:
	set(value):
		rows = value
		_parsed = false

var _parsed := false
var _width := 0
var _height := 0
var _cells := PackedByteArray()
var _problems := PackedStringArray()


## Map size in cells.
func get_size() -> Vector2i:
	_parse()
	return Vector2i(_width, _height)


## Map size in pixels.
func get_pixel_size() -> Vector2i:
	return get_size() * CELL_SIZE


func in_bounds(cell: Vector2i) -> bool:
	_parse()
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height


## Index into biome.terrains of the terrain at a cell, or -1 outside the map.
func terrain_index(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	return _cells[cell.y * _width + cell.x]


## Like terrain_index, but a cell outside the map counts as the nearest cell inside it.
func terrain_index_clamped(cell: Vector2i) -> int:
	_parse()
	if _width == 0 or _height == 0:
		return -1
	var x := clampi(cell.x, 0, _width - 1)
	var y := clampi(cell.y, 0, _height - 1)
	return _cells[y * _width + x]


## The terrain type at a cell, or null outside the map.
func terrain_at(cell: Vector2i) -> TerrainType:
	var index := terrain_index(cell)
	return null if index < 0 else biome.terrains[index]


func has_control_point() -> bool:
	return control_point.x >= 0.0 and control_point.y >= 0.0


## Can ground units stand on this cell? False outside the map.
func is_walkable(cell: Vector2i) -> bool:
	var t := terrain_at(cell)
	return t != null and t.walkable


## Can a building stand on this cell? False outside the map.
func is_buildable(cell: Vector2i) -> bool:
	var t := terrain_at(cell)
	return t != null and t.buildable


## The cell that contains a point given in map pixels.
static func cell_at_pixel(point: Vector2) -> Vector2i:
	return Vector2i((point / CELL_SIZE).floor())


## Centre of a cell, in map pixels.
static func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_SIZE


## Human-readable problems with this map. Empty when it is valid.
func problems() -> PackedStringArray:
	_parse()
	return _problems


func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	_problems = PackedStringArray()
	_cells = PackedByteArray()
	_height = rows.size()
	_width = rows[0].length() if _height > 0 else 0
	if biome == null:
		_problems.append("map has no biome")
		_width = 0
		_height = 0
		return
	_problems.append_array(biome.problems())
	if _width == 0:
		_problems.append("map is empty")
		_height = 0
		return
	_cells.resize(_width * _height)
	for y in _height:
		var row := rows[y]
		if row.length() != _width:
			_problems.append("row %d is %d cells long, expected %d" % [y, row.length(), _width])
		for x in _width:
			var index := -1
			if x < row.length():
				index = biome.terrain_index_for_symbol(row[x])
				if index < 0:
					_problems.append("unknown terrain symbol '%s' at (%d, %d)" % [row[x], x, y])
			_cells[y * _width + x] = maxi(index, 0)
	for start in starts:
		if not in_bounds(start):
			_problems.append("start position %s is outside the map" % start)
		elif not biome.terrains[_cells[start.y * _width + start.x]].walkable:
			_problems.append("start position %s is on impassable ground" % start)
