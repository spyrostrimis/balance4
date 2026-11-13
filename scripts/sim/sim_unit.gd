class_name SimUnit
extends RefCounted
## One unit in the simulation. Plain data; SimWorld changes it every tick.

## What the unit has been told to do.
enum Order {
	## Nothing: it stands, and fights enemies that come near.
	NONE,
	## Walk to a cell and ignore enemies.
	MOVE,
	## Walk to a cell and fight enemies met on the way.
	ATTACK_MOVE,
	## Chase and attack one unit until it is dead.
	ATTACK,
	## Walk up to a unit and use the hero ability on it.
	ABILITY,
}

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


var order := Order.NONE
## Where a MOVE or ATTACK_MOVE order leads.
var order_cell := Vector2i.ZERO
## The unit an ATTACK or ABILITY order is aimed at (its id).
var order_target := 0
## The enemy the unit is fighting right now (its id), or 0.
var target_id := 0
## The target's cell when the unit last planned how to get to it.
var chase_cell := Vector2i(-1, -1)
## Ticks until it can hit again, and until its ability is ready again.
var attack_ticks_left := 0
var ability_ticks_left := 0
## Simulation ticks at which it last hit something and was last hurt. For drawing.
var last_attack_tick := -1000
var last_hurt_tick := -1000
## The enemy that last hurt it or a comrade near it (its id), and when. The
## unit goes after that enemy even if it is too far away to notice otherwise.
var provoked_by := 0
var provoked_tick := -1000
## Set when the unit has been killed. A dead unit is no longer in the world.
var dead := false


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
