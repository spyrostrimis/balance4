class_name SimBuilding
extends RefCounted
## One building in the simulation. Plain data; it never moves. It can be
## attacked, and it is gone from the world once its health reaches 0.

var id := 0
var type: BuildingType
var team := 0
## The top-left cell of the cells it covers.
var cell := Vector2i.ZERO
var health := 0
## The simulation tick at which it was last hit. For drawing.
var last_hurt_tick := -1000


## The cells it covers, as a rectangle.
func rect() -> Rect2i:
	return Rect2i(cell, type.footprint)


## The cells it covers, row by row.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in type.footprint.y:
		for x in type.footprint.x:
			out.append(cell + Vector2i(x, y))
	return out


## Is a cell right next to the building (touching a side or a corner), and not
## under it?
func is_beside(other: Vector2i) -> bool:
	var area := rect()
	return not area.has_point(other) and area.grow(1).has_point(other)


## The middle of the building, in cells.
func center() -> Vector2:
	return Vector2(cell) + Vector2(type.footprint) / 2.0


## The cell it covers that is nearest to another cell.
func nearest_cell(from: Vector2i) -> Vector2i:
	var area := rect()
	return Vector2i(clampi(from.x, area.position.x, area.end.x - 1), clampi(from.y, area.position.y, area.end.y - 1))
