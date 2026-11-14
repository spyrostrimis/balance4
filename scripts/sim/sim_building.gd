class_name SimBuilding
extends RefCounted
## One building in the simulation. Plain data; it never moves.

var id := 0
var type: BuildingType
var team := 0
## The top-left cell of the cells it covers.
var cell := Vector2i.ZERO


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
