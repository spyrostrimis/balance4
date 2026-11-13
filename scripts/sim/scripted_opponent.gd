class_name ScriptedOpponent
extends RefCounted
## The enemy in Mission 1. It is a short script, not a real opponent: after a
## delay it sends its force to the control area with attack-move orders (some
## units can be held back to follow as a second wave), and from then on sends
## idle units at any intruder inside the area. It never uses its commander's
## ability. The real enemy AI comes in a later milestone.

## How often it looks at its units, in ticks.
const THINK_TICKS := 20

var world: SimWorld
var control: ControlPoint
var team := 1
## The cell its units gather at: just inside the control area, on its own side.
var rally := Vector2i.ZERO
var delay_ticks := 0
## Units of the second wave: unit id -> the tick from which it may set off.
var held := {}


func _init(p_world: SimWorld, p_control: ControlPoint, p_team: int, start: Vector2i, delay_seconds: float) -> void:
	world = p_world
	control = p_control
	team = p_team
	delay_ticks = roundi(delay_seconds * SimWorld.TICKS_PER_SECOND)
	rally = rally_cell(world, control, start)


## Keep a unit back until `seconds` after the rest of the force has set off.
func hold_back(unit_id: int, seconds: float) -> void:
	held[unit_id] = delay_ticks + roundi(seconds * SimWorld.TICKS_PER_SECOND)


## A walkable cell inside the control area on the side that faces `from`.
static func rally_cell(p_world: SimWorld, p_control: ControlPoint, from: Vector2i) -> Vector2i:
	var toward := (Vector2(from) + Vector2(0.5, 0.5) - p_control.center).normalized()
	var region := p_world.region_at(from)
	# Well inside the edge, so that a whole squad gathered around it is inside too.
	var distance := maxf(p_control.radius - 2.0, 0.5)
	while distance < p_control.radius:
		var cell := Vector2i((p_control.center + toward * distance).floor())
		if region != 0 and p_world.region_at(cell) == region:
			return cell
		distance += 0.5
	return p_world.nearest_free_cell(Vector2i(p_control.center), region)


func tick() -> void:
	if world.tick_count < delay_ticks or (world.tick_count - delay_ticks) % THINK_TICKS != 0:
		return
	var intruders: Array[SimUnit] = []
	for unit in world.units:
		if unit.team != team and control.contains(unit.cell):
			intruders.append(unit)
	var to_rally: Array[int] = []
	for unit in world.units:
		if unit.team != team or unit.order != SimUnit.Order.NONE or unit.target_id != 0:
			continue
		if world.tick_count < int(held.get(unit.id, 0)):
			continue                        # second wave: not yet
		var nearest: SimUnit = null
		for intruder in intruders:
			if nearest == null \
					or (intruder.cell - unit.cell).length_squared() < (nearest.cell - unit.cell).length_squared():
				nearest = intruder
		if nearest != null:
			world.order_attack_move([unit.id], nearest.cell)
		elif not control.contains(unit.cell):
			to_rally.append(unit.id)
	if not to_rally.is_empty():
		world.order_attack_move(to_rally, rally)
