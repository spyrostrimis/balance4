class_name ControlPoint
extends RefCounted
## The area around the Orichalcum rock that both sides fight over.
##
## A side "holds" the area while it is the only side with units inside. Its
## hold time then counts up. While both sides have units inside, the area is
## contested and the count pauses. When the area is empty, or the other side
## takes it, the count starts again from zero.

const NOBODY := -1

## Middle of the area, in cells (whole numbers are grid corners).
var center := Vector2.ZERO
## Radius of the area, in cells.
var radius := 5.0
## How many ticks a side must hold the area to win.
var hold_ticks_needed := 900

## The only team with units inside right now, or NOBODY.
var holder := NOBODY
## Do two or more teams have units inside right now?
var contested := false
## The team whose hold time is counting (it stays the owner while contested).
var owner := NOBODY
## How long the owner has held the area, in ticks.
var hold_ticks := 0


func _init(p_center: Vector2, p_radius: float, hold_seconds: float) -> void:
	center = p_center
	radius = p_radius
	hold_ticks_needed = maxi(1, roundi(hold_seconds * SimWorld.TICKS_PER_SECOND))


## Is a cell inside the area? A cell counts by its middle.
func contains(cell: Vector2i) -> bool:
	return (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(center) <= radius * radius


## Look at who is inside and advance the hold time by one tick.
func update(world: SimWorld) -> void:
	var inside := {}
	for unit in world.units:
		if not unit.dead and contains(unit.cell):
			inside[unit.team] = true
	contested = inside.size() > 1
	holder = inside.keys()[0] if inside.size() == 1 else NOBODY
	if holder != NOBODY:
		if owner != holder:
			owner = holder
			hold_ticks = 0
		hold_ticks += 1
	elif not contested:
		owner = NOBODY
		hold_ticks = 0


## Has the owner held the area for long enough?
func is_won() -> bool:
	return owner != NOBODY and hold_ticks >= hold_ticks_needed


## How far the owner's hold time has got, 0 to 1.
func progress() -> float:
	return clampf(float(hold_ticks) / hold_ticks_needed, 0.0, 1.0)


## Seconds the owner still has to hold the area.
func seconds_left() -> float:
	return maxf(0.0, (hold_ticks_needed - hold_ticks) * SimWorld.TICK_SECONDS)
