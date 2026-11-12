class_name SimWorld
extends RefCounted
## The game simulation: the map, the units on it and the rules that move them.
##
## It advances in fixed steps ("ticks"), 20 per second, and never looks at the
## clock, the screen or the mouse, so the same orders always give the same
## result. The UI calls tick() at the right pace and draws what it finds here.

const TICKS_PER_SECOND := 20
const TICK_SECONDS := 1.0 / TICKS_PER_SECOND
## The team the player controls.
const PLAYER_TEAM := 0
## How long a unit waits when another unit is in its way, in ticks.
const WAIT_TICKS := 3
## After this many blocked attempts in a row a unit gives up and stops.
const MAX_BLOCKED_TRIES := 8
## After this many it stops waiting for moving units and plans a way around them.
const DETOUR_TRIES := 4

const NO_CELL := Vector2i(-1, -1)

var map: MapData
var size := Vector2i.ZERO
var tick_count := 0
var units: Array[SimUnit] = []

var _by_id := {}
var _next_id := 1
var _occupant := PackedInt32Array()   # unit id per cell, 0 for none
var _region := PackedInt32Array()     # connected walkable area per cell, 0 for impassable
var _astar := AStarGrid2D.new()
var _shrouds := {}


func _init(p_map: MapData) -> void:
	map = p_map
	size = map.get_size()
	_occupant.resize(size.x * size.y)
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in size.y:
		for x in size.x:
			if not map.is_walkable(Vector2i(x, y)):
				_astar.set_point_solid(Vector2i(x, y), true)
	_build_regions()


# --- units ---------------------------------------------------------------------

## Put a new unit on the map. Returns null if the cell is impassable or taken.
func add_unit(type: UnitType, team: int, cell: Vector2i) -> SimUnit:
	if not is_free(cell):
		return null
	var unit := SimUnit.new()
	unit.id = _next_id
	_next_id += 1
	unit.type = type
	unit.team = team
	unit.health = type.max_health
	unit.cell = cell
	unit.from_cell = cell
	units.append(unit)
	_by_id[unit.id] = unit
	_occupant[_index(cell)] = unit.id
	shroud_for(team).reveal_circle(cell, type.sight)
	return unit


func get_unit(id: int) -> SimUnit:
	return _by_id.get(id)


## The unit occupying a cell, or null.
func unit_at(cell: Vector2i) -> SimUnit:
	if not map.in_bounds(cell):
		return null
	var id := _occupant[_index(cell)]
	return null if id == 0 else _by_id[id]


## Walkable and not occupied.
func is_free(cell: Vector2i) -> bool:
	return map.is_walkable(cell) and _occupant[_index(cell)] == 0


## What a team has explored. Created the first time it is asked for.
func shroud_for(team: int) -> Shroud:
	if not _shrouds.has(team):
		_shrouds[team] = Shroud.new(size)
	return _shrouds[team]


## Number of the connected walkable area a cell belongs to, 0 if impassable.
## Units can only reach cells with the same number as their own.
func region_at(cell: Vector2i) -> int:
	return _region[_index(cell)] if map.in_bounds(cell) else 0


# --- orders --------------------------------------------------------------------

## Tell units to walk to a cell. Each unit gets its own cell: the one nearest
## the target goes to the target itself, the others gather around it. A target
## that cannot be reached (water, another island) is replaced by the nearest
## cell that can.
func order_move(unit_ids: Array, target: Vector2i) -> void:
	var movers: Array[SimUnit] = []
	var ordered := {}
	for id in unit_ids:
		var unit := get_unit(id)
		if unit != null and not ordered.has(id):
			movers.append(unit)
			ordered[id] = true
	target = target.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	movers.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var da := (a.cell - target).length_squared()
		var db := (b.cell - target).length_squared()
		return da < db or (da == db and a.id < b.id))
	var taken := {}
	for unit in movers:
		var slot := nearest_free_cell(target, region_at(unit.cell), taken, ordered)
		if slot == NO_CELL:
			continue
		taken[slot] = true
		unit.goal = slot
		unit.has_goal = true
		unit.path.clear()
		unit.wait_ticks = 0
		unit.blocked_tries = 0


## Tell units to stop where they are (they finish the step they are in).
func order_stop(unit_ids: Array) -> void:
	for id in unit_ids:
		var unit := get_unit(id)
		if unit != null:
			_stop(unit)


## The walkable cell nearest to target that is in the given region, not in
## `taken` and not occupied (units whose id is in `leaving` do not count as
## occupying). NO_CELL if there is none.
func nearest_free_cell(target: Vector2i, region: int, taken := {}, leaving := {}) -> Vector2i:
	var max_radius := maxi(size.x, size.y)
	for radius in range(0, max_radius + 1):
		var best := NO_CELL
		var best_distance := 0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := target + Vector2i(dx, dy)
				if not map.in_bounds(cell) or taken.has(cell):
					continue
				var index := _index(cell)
				if _region[index] == 0 or (region != 0 and _region[index] != region):
					continue
				var occupant := _occupant[index]
				if occupant != 0 and not leaving.has(occupant):
					continue
				var distance := dx * dx + dy * dy
				if best == NO_CELL or distance < best_distance:
					best = cell
					best_distance = distance
		if best != NO_CELL:
			return best
	return NO_CELL


# --- the tick --------------------------------------------------------------------

## Advance the simulation by one step.
func tick() -> void:
	tick_count += 1
	for unit in units:
		if unit.move_ticks_left > 0:
			unit.move_ticks_left -= 1
			if unit.move_ticks_left > 0:
				continue
			unit.from_cell = unit.cell      # arrived
		if unit.wait_ticks > 0:
			unit.wait_ticks -= 1
			continue
		if unit.has_goal:
			_try_step(unit)


func _try_step(unit: SimUnit) -> void:
	if unit.cell == unit.goal:
		_stop(unit)
		return
	# Someone has settled on the goal: aim for the nearest free cell instead.
	var at_goal := unit_at(unit.goal)
	if at_goal != null and at_goal != unit and at_goal.is_settled():
		var other_goal := nearest_free_cell(unit.goal, region_at(unit.cell), {}, {unit.id: true})
		if other_goal == NO_CELL or other_goal == unit.cell:
			_stop(unit)
			return
		unit.goal = other_goal
		unit.path.clear()
	if unit.path.is_empty():
		_find_path(unit, false)
		if unit.path.is_empty():
			_blocked(unit)
			return
	var next := unit.path[0]
	var step := next - unit.cell
	if maxi(absi(step.x), absi(step.y)) != 1:
		unit.path.clear()                   # the path no longer starts next to us; plan again
		return
	var other := unit_at(next)
	if other == null:
		_begin_step(unit, next)
	elif _wants_to_swap(other, unit):
		# Two units of one team walking into each other simply change places.
		_occupant[_index(unit.cell)] = 0
		_occupant[_index(other.cell)] = 0
		var mine := unit.cell
		_begin_step(unit, other.cell)
		_begin_step(other, mine)
	elif other.is_settled():
		unit.path.clear()                   # walk around it: plan again next tick
		_blocked(unit, 0)
	else:
		_blocked(unit)                      # it is on the move: give it a moment
		if unit.has_goal and unit.blocked_tries >= DETOUR_TRIES:
			_find_path(unit, true)


func _wants_to_swap(other: SimUnit, unit: SimUnit) -> bool:
	return (other.team == unit.team and other.has_goal and not other.is_moving()
			and not other.path.is_empty() and other.path[0] == unit.cell)


func _begin_step(unit: SimUnit, next: Vector2i) -> void:
	if _occupant[_index(unit.cell)] == unit.id:
		_occupant[_index(unit.cell)] = 0
	_occupant[_index(next)] = unit.id
	var step := next - unit.cell
	unit.from_cell = unit.cell
	unit.cell = next
	unit.facing = facing_for(step)
	unit.move_ticks_total = unit.type.ticks_per_cell(step.x != 0 and step.y != 0)
	unit.move_ticks_left = unit.move_ticks_total
	if not unit.path.is_empty() and unit.path[0] == next:
		unit.path.remove_at(0)
	unit.blocked_tries = 0
	unit.wait_ticks = 0
	shroud_for(unit.team).reveal_circle(next, unit.type.sight)


func _blocked(unit: SimUnit, wait := WAIT_TICKS) -> void:
	unit.blocked_tries += 1
	unit.wait_ticks = wait
	if unit.blocked_tries > MAX_BLOCKED_TRIES:
		_stop(unit)


func _stop(unit: SimUnit) -> void:
	unit.has_goal = false
	unit.path.clear()
	unit.wait_ticks = 0
	unit.blocked_tries = 0


## Plan a path to the unit's goal around terrain and around units that are
## staying put (and, if asked, around every other unit). If the goal cannot be
## reached the path leads as close to it as possible.
func _find_path(unit: SimUnit, around_everyone: bool) -> void:
	var blocked: Array[Vector2i] = []
	for other in units:
		if other != unit and (around_everyone or other.is_settled()):
			blocked.append(other.cell)
			_astar.set_point_solid(other.cell, true)
	var cells := _astar.get_id_path(unit.cell, unit.goal, true)
	for cell in blocked:
		_astar.set_point_solid(cell, false)
	unit.path.clear()
	for i in range(1, cells.size()):
		unit.path.append(cells[i])


## The path a unit would take between two cells over open terrain, ignoring
## other units. Empty if there is none. For tests and tools.
func terrain_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not map.in_bounds(from) or not map.in_bounds(to):
		return []
	if _region[_index(from)] == 0 or _region[_index(from)] != _region[_index(to)]:
		return []
	return _astar.get_id_path(from, to)


## Facing number for a step of one cell in any of the eight directions.
static func facing_for(step: Vector2i) -> int:
	match Vector2i(signi(step.x), signi(step.y)):
		Vector2i(0, 1): return 0
		Vector2i(-1, 1): return 1
		Vector2i(-1, 0): return 2
		Vector2i(-1, -1): return 3
		Vector2i(0, -1): return 4
		Vector2i(1, -1): return 5
		Vector2i(1, 0): return 6
		Vector2i(1, 1): return 7
	return 0


func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


## Number the connected walkable areas. Moving diagonally needs both cells
## beside the diagonal to be walkable, so areas joined only corner to corner
## count as separate.
func _build_regions() -> void:
	_region.resize(size.x * size.y)
	_region.fill(0)
	var next_region := 0
	for y in size.y:
		for x in size.x:
			var start := Vector2i(x, y)
			if _region[_index(start)] != 0 or not map.is_walkable(start):
				continue
			next_region += 1
			_region[_index(start)] = next_region
			var stack: Array[Vector2i] = [start]
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var near: Vector2i = cell + step
					if map.is_walkable(near) and _region[_index(near)] == 0:
						_region[_index(near)] = next_region
						stack.append(near)
