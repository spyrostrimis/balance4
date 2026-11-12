class_name Shroud
extends RefCounted
## Which cells one team has explored. Unexplored cells are hidden; once a cell
## has been seen it stays visible.

var size := Vector2i.ZERO
## Goes up by one every time new cells are revealed.
var version := 0
## Every revealed cell, in the order it was revealed. Views that draw the
## shroud remember how far into this list they have got.
var revealed_log: Array[Vector2i] = []

var _explored := PackedByteArray()


func _init(p_size: Vector2i) -> void:
	size = p_size
	_explored.resize(size.x * size.y)


func is_explored(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	return _explored[cell.y * size.x + cell.x] != 0


## Like is_explored, but a cell outside the map counts as its nearest cell inside.
func is_explored_clamped(cell: Vector2i) -> bool:
	return is_explored(Vector2i(clampi(cell.x, 0, size.x - 1), clampi(cell.y, 0, size.y - 1)))


func explored_count() -> int:
	return revealed_log.size()


## Reveal a roughly round area. Returns how many cells were new.
func reveal_circle(center: Vector2i, radius: int) -> int:
	var added := 0
	# The extra "+ radius" rounds the circle off so it has no single-cell tips.
	var limit := radius * radius + radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > limit:
				continue
			var cell := center + Vector2i(dx, dy)
			if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
				continue
			var index := cell.y * size.x + cell.x
			if _explored[index] == 0:
				_explored[index] = 1
				revealed_log.append(cell)
				added += 1
	if added > 0:
		version += 1
	return added
