class_name SimUnit
extends RefCounted
## One unit in the simulation. Plain data; SimWorld changes it every tick.

var id := 0
var type: UnitType
var team := 0
var health := 0
## The cell the unit occupies. A unit that is walking already occupies the cell
## it is walking into.
var cell := Vector2i.ZERO
## The cell the unit is walking out of (same as cell when it stands still).
var from_cell := Vector2i.ZERO
## 0 south, 1 south-west, 2 west, 3 north-west, 4 north, 5 north-east, 6 east, 7 south-east.
var facing := 0
## Ticks the current step takes in total, and how many of them are left.
var move_ticks_total := 0
var move_ticks_left := 0
## Where the unit has been told to go, if has_goal is true.
var goal := Vector2i.ZERO
var has_goal := false
## The cells still to walk through, next one first.
var path: Array[Vector2i] = []
## Ticks to stand and wait before trying to move again.
var wait_ticks := 0
## How many times in a row the unit found its way blocked.
var blocked_tries := 0


## Is the unit between two cells right now?
func is_moving() -> bool:
	return move_ticks_left > 0


## A unit that stands still and has nowhere to go. Others must walk around it.
func is_settled() -> bool:
	return not has_goal and move_ticks_left == 0


## Where to draw the unit, in cells (whole numbers are cell positions).
## alpha is how far we are between the last tick and the next, 0 to 1.
func visual_cell(alpha := 0.0) -> Vector2:
	if move_ticks_left <= 0 or move_ticks_total <= 0:
		return Vector2(cell)
	var t := clampf((move_ticks_total - move_ticks_left + alpha) / move_ticks_total, 0.0, 1.0)
	return Vector2(from_cell).lerp(Vector2(cell), t)
