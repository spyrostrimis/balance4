class_name SimWorld
extends RefCounted
## The game simulation: the map, the units on it and the rules that move them
## and make them fight.
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
## A unit keeps fighting an enemy this many cells beyond the distance at which
## it would notice it, so a target is not dropped the moment it steps away.
const LEASH_EXTRA := 2
## A unit that has been hurt goes after its attacker, however far away, for
## this many ticks after the last blow.
const PROVOKED_TICKS := 100
## Idle units this close to a comrade that is hit come to its help, in cells.
const HELP_RANGE := 6
## How long an entry stays in `effects`, in ticks.
const EFFECT_TICKS := 20

const NO_CELL := Vector2i(-1, -1)

var map: MapData
var size := Vector2i.ZERO
var tick_count := 0
var units: Array[SimUnit] = []
## Recent things worth showing: hits, heals and deaths. Each entry is a
## dictionary with "kind" (&"hit", &"heal" or &"death"), "tick", "team" (of the
## unit that acted or died), and "from" and "to" (positions in cells). The UI
## draws them; nothing in the rules reads them.
var effects: Array[Dictionary] = []
## How many units have been killed so far. The UI watches it to forget dead units.
var removed_count := 0
## Units lost per team: team -> count.
var losses := {}

var _by_id := {}
var _next_id := 1
var _occupant := PackedInt32Array()   # unit id per cell, 0 for none
var _region := PackedInt32Array()     # connected walkable area per cell, 0 for impassable
var _astar := AStarGrid2D.new()
var _shrouds := {}
var _any_dead := false


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


## Put `count` units of one type on the free cells nearest to a cell.
func add_group(type: UnitType, team: int, near: Vector2i, count: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	var region := region_at(nearest_free_cell(near, 0))
	for i in count:
		var cell := nearest_free_cell(near, region)
		if cell == NO_CELL:
			break
		out.append(add_unit(type, team, cell))
	return out


## The living unit with this id, or null.
func get_unit(id: int) -> SimUnit:
	return _by_id.get(id)


## How many units a team has left.
func team_size(team: int) -> int:
	var count := 0
	for unit in units:
		if unit.team == team and not unit.dead:
			count += 1
	return count


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


## Can a team see a unit? It always sees its own; it sees others only on
## ground it has explored.
func is_visible_to(unit: SimUnit, team: int) -> bool:
	return unit.team == team or shroud_for(team).is_explored(unit.cell)


## Number of the connected walkable area a cell belongs to, 0 if impassable.
## Units can only reach cells with the same number as their own.
func region_at(cell: Vector2i) -> int:
	return _region[_index(cell)] if map.in_bounds(cell) else 0


# --- orders --------------------------------------------------------------------

## Tell units to walk to a cell and ignore enemies on the way. Each unit gets
## its own cell: the one nearest the target goes to the target itself, the
## others gather around it. A target that cannot be reached (water, trees,
## another island) is replaced by the nearest cell that can.
func order_move(unit_ids: Array, target: Vector2i) -> void:
	_order_walk(unit_ids, target, SimUnit.Order.MOVE)


## Like order_move, but the units fight any enemy they meet on the way and
## then carry on.
func order_attack_move(unit_ids: Array, target: Vector2i) -> void:
	_order_walk(unit_ids, target, SimUnit.Order.ATTACK_MOVE)


## Tell units to chase one unit and attack it until it is dead. Units that
## cannot attack, and the target itself, ignore the order.
func order_attack(unit_ids: Array, target_id: int) -> void:
	var target := get_unit(target_id)
	if target == null:
		return
	for id in unit_ids:
		var unit := get_unit(id)
		if unit == null or unit == target or unit.type.attack_damage <= 0:
			continue
		_stop(unit)
		unit.order = SimUnit.Order.ATTACK
		unit.order_target = target_id
		unit.target_id = target_id
		unit.chase_cell = NO_CELL


## Why a hero cannot use its ability on a unit right now, in words for the
## player. "" if it can.
func ability_problem(unit_id: int, target_id: int) -> String:
	var unit := get_unit(unit_id)
	if unit == null or unit.type.ability == null:
		return "No ability"
	var ability := unit.type.ability
	if unit.ability_ticks_left > 0:
		return "%s is not ready yet" % ability.display_name
	var target := get_unit(target_id)
	if target == null or target.team != unit.team:
		return "Pick one of your own units"
	if target == unit and not ability.can_target_self:
		return "Pick another unit, not the commander"
	if ability.kind == Ability.Kind.HEAL_TARGET and target.health >= target.type.max_health:
		return "That unit is not wounded"
	return ""


## Tell a hero to use its ability on a unit. It walks into range first if it
## has to. Returns false (and does nothing) if ability_problem() reports one.
func order_ability(unit_id: int, target_id: int) -> bool:
	if ability_problem(unit_id, target_id) != "":
		return false
	var unit := get_unit(unit_id)
	_stop(unit)
	unit.order = SimUnit.Order.ABILITY
	unit.order_target = target_id
	unit.target_id = 0
	unit.chase_cell = NO_CELL
	return true


## Tell units to stop where they are (they finish the step they are in). They
## still fight enemies that come near.
func order_stop(unit_ids: Array) -> void:
	for id in unit_ids:
		var unit := get_unit(id)
		if unit != null:
			_stop(unit)
			unit.order = SimUnit.Order.NONE
			unit.order_target = 0
			unit.target_id = 0


func _order_walk(unit_ids: Array, target: Vector2i, order: SimUnit.Order) -> void:
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
		unit.order = order
		unit.order_cell = slot
		unit.order_target = 0
		unit.target_id = 0
		_set_goal(unit, slot)


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
	while not effects.is_empty() and tick_count - int(effects[0]["tick"]) > EFFECT_TICKS:
		effects.pop_front()
	for unit in units:
		if unit.dead:
			continue
		if unit.attack_ticks_left > 0:
			unit.attack_ticks_left -= 1
		if unit.ability_ticks_left > 0:
			unit.ability_ticks_left -= 1
		if unit.move_ticks_left > 0:
			unit.move_ticks_left -= 1
			if unit.move_ticks_left > 0:
				continue
			unit.from_cell = unit.cell      # arrived
		if _act(unit):
			continue                        # it is busy fighting or using its ability
		if unit.wait_ticks > 0:
			unit.wait_ticks -= 1
			continue
		if unit.has_goal:
			_try_step(unit)
			var walking := unit.order == SimUnit.Order.MOVE or unit.order == SimUnit.Order.ATTACK_MOVE
			if walking and not unit.has_goal and not unit.is_moving():
				unit.order = SimUnit.Order.NONE     # arrived, or gave up
	if _any_dead:
		_any_dead = false
		units = units.filter(func(unit: SimUnit) -> bool: return not unit.dead)


# --- combat ----------------------------------------------------------------------

## Is cell b within `reach` cells of cell a? The area is round, like the area a
## unit sees: 1 reaches the eight cells around a.
static func in_range(a: Vector2i, b: Vector2i, reach: int) -> bool:
	return (a - b).length_squared() <= reach * reach + reach


## The nearest unit of another team within `reach` cells of a cell, or null.
func nearest_enemy(cell: Vector2i, team: int, reach: int) -> SimUnit:
	var best: SimUnit = null
	var best_distance := 0
	for other in units:
		if other.team == team or other.dead or not in_range(cell, other.cell, reach):
			continue
		var distance := (other.cell - cell).length_squared()
		if best == null or distance < best_distance:
			best = other
			best_distance = distance
	return best


## Let a unit fight or use its ability. Returns true if it did something that
## keeps it where it is this tick.
func _act(unit: SimUnit) -> bool:
	if unit.order == SimUnit.Order.MOVE:
		return false
	if unit.order == SimUnit.Order.ABILITY:
		return _act_ability(unit)
	if unit.type.attack_damage <= 0:
		return false
	var target := _pick_target(unit)
	if target == null:
		if unit.order == SimUnit.Order.ATTACK:
			unit.order = SimUnit.Order.NONE         # the target is dead
			unit.order_target = 0
			_stop(unit)
		elif unit.order == SimUnit.Order.ATTACK_MOVE:
			if not unit.has_goal:                   # the fight is over: walk on
				if unit.cell == unit.order_cell:
					unit.order = SimUnit.Order.NONE
				else:
					_set_goal(unit, unit.order_cell)
		elif unit.has_goal:
			_stop(unit)                             # what it was chasing got away
		return false
	if in_range(unit.cell, target.cell, unit.type.attack_range):
		_stop(unit)
		unit.facing = facing_toward(target.cell - unit.cell)
		if unit.attack_ticks_left == 0:
			_strike(unit, target)
		return true
	_approach(unit, target, unit.type.attack_range)
	return false


## The enemy a unit should fight now, or null. A unit with an attack order
## sticks to that target. Otherwise it keeps a target it can reach, and else
## takes the nearest enemy it notices.
func _pick_target(unit: SimUnit) -> SimUnit:
	if unit.order == SimUnit.Order.ATTACK:
		return get_unit(unit.order_target)
	var current := get_unit(unit.target_id) if unit.target_id != 0 else null
	if current != null and in_range(unit.cell, current.cell, unit.type.attack_range):
		return current
	var best := nearest_enemy(unit.cell, unit.team, unit.type.acquire_range)
	if best == null and current != null:
		var provoked := current.id == unit.provoked_by and tick_count - unit.provoked_tick <= PROVOKED_TICKS
		if provoked or in_range(unit.cell, current.cell, unit.type.acquire_range + LEASH_EXTRA):
			best = current
	unit.target_id = best.id if best != null else 0
	return best


## Walk towards a unit until it is within `reach` cells. Plans again only when
## the unit it is after has moved.
func _approach(unit: SimUnit, target: SimUnit, reach: int) -> void:
	if unit.has_goal and unit.chase_cell == target.cell:
		return
	var slot := _slot_near(unit, target.cell, reach)
	if slot == NO_CELL or slot == unit.cell:
		_stop(unit)                                 # nowhere better to stand: wait here
		return
	unit.chase_cell = target.cell
	_set_goal(unit, slot)


## The free cell within `reach` cells of a cell that is nearest to a unit. If
## all of them are taken, the nearest free cell beyond them.
func _slot_near(unit: SimUnit, around: Vector2i, reach: int) -> Vector2i:
	var best := NO_CELL
	var best_distance := 0
	var region := region_at(unit.cell)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := around + Vector2i(dx, dy)
			if cell == around or not map.in_bounds(cell) or not in_range(around, cell, reach):
				continue
			var index := _index(cell)
			if _region[index] != region or (_occupant[index] != 0 and _occupant[index] != unit.id):
				continue
			var distance := (cell - unit.cell).length_squared()
			if best == NO_CELL or distance < best_distance:
				best = cell
				best_distance = distance
	if best == NO_CELL:
		best = nearest_free_cell(around, region, {}, {unit.id: true})
	return best


func _strike(attacker: SimUnit, target: SimUnit) -> void:
	attacker.attack_ticks_left = attacker.type.attack_ticks()
	attacker.last_attack_tick = tick_count
	_add_effect(&"hit", attacker, target)
	target.health = maxi(0, target.health - attacker.type.attack_damage)
	target.last_hurt_tick = tick_count
	if target.health == 0:
		_kill(target)
	# The victim fights back, and idle comrades near it come to its help.
	for unit in units:
		if unit.team != target.team or unit.dead or unit.type.attack_damage <= 0:
			continue
		if unit != target and not in_range(unit.cell, target.cell, HELP_RANGE):
			continue
		if unit.order != SimUnit.Order.NONE and unit.order != SimUnit.Order.ATTACK_MOVE:
			continue
		unit.provoked_by = attacker.id
		unit.provoked_tick = tick_count
		if unit.target_id == 0:
			unit.target_id = attacker.id


func _kill(unit: SimUnit) -> void:
	unit.dead = true
	_stop(unit)
	if _occupant[_index(unit.cell)] == unit.id:
		_occupant[_index(unit.cell)] = 0
	_by_id.erase(unit.id)
	_any_dead = true
	removed_count += 1
	losses[unit.team] = int(losses.get(unit.team, 0)) + 1
	_add_effect(&"death", unit, unit)


func _act_ability(unit: SimUnit) -> bool:
	var ability := unit.type.ability
	var target := get_unit(unit.order_target)
	if ability == null or target == null or target.team != unit.team:
		unit.order = SimUnit.Order.NONE             # the unit it was for is gone
		unit.order_target = 0
		_stop(unit)
		return false
	if target != unit and not in_range(unit.cell, target.cell, ability.cast_range):
		_approach(unit, target, ability.cast_range)
		return false
	_stop(unit)
	if unit.ability_ticks_left > 0:
		return true                                 # in place; wait until it is ready
	if target != unit:
		unit.facing = facing_toward(target.cell - unit.cell)
	match ability.kind:
		Ability.Kind.HEAL_TARGET:
			target.health = mini(target.type.max_health, target.health + ability.amount)
	unit.ability_ticks_left = ability.cooldown_ticks()
	_add_effect(&"heal", unit, target)
	unit.order = SimUnit.Order.NONE
	unit.order_target = 0
	return true


func _add_effect(kind: StringName, actor: SimUnit, subject: SimUnit) -> void:
	effects.append({
		"kind": kind, "tick": tick_count, "team": actor.team,
		"from": actor.visual_cell(), "to": subject.visual_cell(),
	})


# --- movement --------------------------------------------------------------------

func _set_goal(unit: SimUnit, cell: Vector2i) -> void:
	unit.goal = cell
	unit.has_goal = true
	unit.path.clear()
	unit.wait_ticks = 0
	unit.blocked_tries = 0


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


## End a unit's walk. Its order is left alone.
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
		if other != unit and not other.dead and (around_everyone or other.is_settled()):
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


## Facing number for looking from one cell towards another, any distance away.
static func facing_toward(delta: Vector2i) -> int:
	if delta == Vector2i.ZERO:
		return 0
	return posmod(roundi(atan2(-delta.x, delta.y) / (PI / 4.0)), 8)


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
