class_name SimWorld
extends RefCounted
## The game simulation: the map, the units and buildings on it, the Orichalcum
## deposits, and the rules that move units, make them fight and make
## harvesters earn and defend their trailers.
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
## A harvester that finds no free place to stand beside its deposit or its
## refinery looks again after this many ticks.
const RETRY_TICKS := 10
## A robot that has to walk further than this from its trailer to dig (in
## cells) hitches up and parks nearer to the Orichalcum instead.
const REPARK_CELLS := 3
## A guarding robot goes back to work this many ticks after the last enemy
## has left.
const CALM_TICKS := 40
## The eight cells around a cell, the four that share a side first.
const AROUND: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1),
	Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1),
]

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
var buildings: Array[SimBuilding] = []
## The Orichalcum deposits of the map. A deposit stays in the list when it has
## run out.
var deposits: Array[Deposit] = []
## Deposit cells that have been emptied, in the order it happened. The UI
## follows it to redraw them.
var spent_log: Array[Vector2i] = []
## Orichalcum in store per team, and Orichalcum a team has taken out of
## other sides' orphaned trailers: team -> amount.
var stored := {}
var stolen := {}
## Trailers standing on their own: unhitched by their robot, or orphaned.
var trailers: Array[SimTrailer] = []
## The build queues of every side: constructing buildings and producing units.
var production: Production

var _by_id := {}
var _next_id := 1
var _occupant := PackedInt32Array()   # unit id per cell, 0 for none
var _building := PackedInt32Array()   # building id per cell, 0 for none
var _deposit := PackedInt32Array()    # deposit id per cell, 0 for none
var _trailer_cell := PackedInt32Array()  # trailer id per cell, 0 for none
var _buildings_by_id := {}
var _trailers_by_id := {}
var _region := PackedInt32Array()     # connected walkable area per cell, 0 for impassable
var _astar := AStarGrid2D.new()
var _shrouds := {}
var _any_dead := false


func _init(p_map: MapData) -> void:
	map = p_map
	size = map.get_size()
	_occupant.resize(size.x * size.y)
	_building.resize(size.x * size.y)
	_trailer_cell.resize(size.x * size.y)
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
	_find_deposits()
	production = Production.new(self)


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


## Walkable, not built on and not occupied by a unit or a trailer.
func is_free(cell: Vector2i) -> bool:
	return _is_open(cell) and not _taken(_index(cell))


## Is there a trailer on this cell, or a unit other than the one given?
func _taken(index: int, unit_id := 0) -> bool:
	return _trailer_cell[index] != 0 or (_occupant[index] != 0 and _occupant[index] != unit_id)


## Ground a unit can stand on: walkable terrain with no building on it.
func _is_open(cell: Vector2i) -> bool:
	return map.is_walkable(cell) and _building[_index(cell)] == 0


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
## then carry on. Harvesters just move: they only ever fight for their trailer.
func order_attack_move(unit_ids: Array, target: Vector2i) -> void:
	_order_walk(unit_ids, target, SimUnit.Order.ATTACK_MOVE)


## Tell units to chase one unit and attack it until it is dead. Units that
## cannot attack, harvesters and the target itself ignore the order.
func order_attack(unit_ids: Array, target_id: int) -> void:
	var target := get_unit(target_id)
	if target == null:
		return
	for id in unit_ids:
		var unit := get_unit(id)
		if unit == null or unit == target or unit.type.attack_damage <= 0 or unit.type.is_harvester():
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
			_quit_job(unit)
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
		_quit_job(unit)
		unit.order = SimUnit.Order.MOVE if unit.type.is_harvester() else order
		unit.order_cell = slot
		unit.order_target = 0
		unit.target_id = 0
		if unit.is_robot():
			# A robot goes back to its trailer and becomes a truck before it drives off.
			_stop(unit)
			unit.held_goal = slot
			unit.has_held_goal = true
		else:
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
				if _trailer_cell[index] != 0 or (occupant != 0 and not leaving.has(occupant)):
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
		if unit.job == SimUnit.Job.DEPLOY or unit.job == SimUnit.Job.PACK:
			unit.job_ticks_left -= 1
			if unit.job_ticks_left > 0 or not _change_shape(unit):
				continue                    # changing shape; nothing else happens
		if _act(unit):
			continue                        # it is busy fighting or using its ability
		if unit.wait_ticks > 0:
			unit.wait_ticks -= 1
			continue
		if unit.has_goal:
			_try_step(unit)
			var walking := unit.order == SimUnit.Order.MOVE or unit.order == SimUnit.Order.ATTACK_MOVE
			if walking and not unit.has_goal and not unit.is_moving() and not unit.is_robot():
				unit.order = SimUnit.Order.NONE     # arrived, or gave up
	_take_orphans()
	production.tick()
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
	if unit.type.is_harvester():
		return _act_harvester(unit)
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
			if _region[index] != region or _taken(index, unit.id):
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
	target.health = maxi(0, target.health - damage_to(target, attacker.type.attack_damage))
	target.last_hurt_tick = tick_count
	if target.health == 0:
		_kill(target)
	elif target.type.is_harvester():
		target.provoked_by = attacker.id        # a harvester looks after itself: see _threat()
		target.provoked_tick = tick_count
	# The victim fights back, and idle comrades near it come to its help.
	for unit in units:
		if unit.team != target.team or unit.dead or unit.type.attack_damage <= 0 or unit.type.is_harvester():
			continue
		if unit != target and not in_range(unit.cell, target.cell, HELP_RANGE):
			continue
		if unit.order != SimUnit.Order.NONE and unit.order != SimUnit.Order.ATTACK_MOVE:
			continue
		unit.provoked_by = attacker.id
		unit.provoked_tick = tick_count
		if unit.target_id == 0:
			unit.target_id = attacker.id


## How much health a hit of `damage` takes off a unit. A harvester's robot
## has armour that stops part of every hit; nothing else has any.
static func damage_to(target: SimUnit, damage: int) -> int:
	if target.trailer_id == 0 or target.type.robot_armor <= 0:
		return damage
	return maxi(1, roundi(damage * (100 - target.type.robot_armor) / 100.0))


func _kill(unit: SimUnit) -> void:
	unit.dead = true
	_stop(unit)
	if _occupant[_index(unit.cell)] == unit.id:
		_occupant[_index(unit.cell)] = 0
	if unit.type.is_harvester():
		_orphan_trailer(unit)
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


# --- buildings -------------------------------------------------------------------

## Can a building of this type stand with its top-left corner on a cell? Every
## cell it covers must be ground that can be built on, with no building and no
## unit on it.
func can_build(type: BuildingType, cell: Vector2i) -> bool:
	for y in type.footprint.y:
		for x in type.footprint.x:
			if not can_build_on(cell + Vector2i(x, y)):
				return false
	return true


## Could one cell be covered by a new building? It must be ground that can be
## built on, with no building, unit or trailer on it.
func can_build_on(cell: Vector2i) -> bool:
	if not map.is_buildable(cell):
		return false
	return _building[_index(cell)] == 0 and not _taken(_index(cell))


## Put a building on the map, its top-left corner on a cell. Units can no
## longer enter the cells it covers. Returns null if it cannot stand there.
func add_building(type: BuildingType, team: int, cell: Vector2i) -> SimBuilding:
	if not can_build(type, cell):
		return null
	var building := SimBuilding.new()
	building.id = _next_id
	_next_id += 1
	building.type = type
	building.team = team
	building.cell = cell
	buildings.append(building)
	_buildings_by_id[building.id] = building
	for covered in building.cells():
		_building[_index(covered)] = building.id
		_astar.set_point_solid(covered, true)
		shroud_for(team).reveal_circle(covered, type.sight)
	_build_regions()
	return building


## The building with this id, or null.
func get_building(id: int) -> SimBuilding:
	return _buildings_by_id.get(id)


## The building covering a cell, or null.
func building_at(cell: Vector2i) -> SimBuilding:
	if not map.in_bounds(cell):
		return null
	var id := _building[_index(cell)]
	return null if id == 0 else _buildings_by_id[id]


## The place nearest to a cell where a building of this type can stand (its
## top-left cell), measured from the middle of the building. NO_CELL if there
## is none on the map.
func nearest_build_site(type: BuildingType, near: Vector2i) -> Vector2i:
	var best := NO_CELL
	var best_distance := 0.0
	var target := Vector2(near) + Vector2(0.5, 0.5)
	for y in size.y - type.footprint.y + 1:
		for x in size.x - type.footprint.x + 1:
			var cell := Vector2i(x, y)
			var distance := (Vector2(cell) + Vector2(type.footprint) / 2.0).distance_squared_to(target)
			if (best == NO_CELL or distance < best_distance) and can_build(type, cell):
				best = cell
				best_distance = distance
	return best


## Can a team see a building? It always sees its own; it sees others once it
## has explored any cell they cover.
func is_building_visible_to(building: SimBuilding, team: int) -> bool:
	if building.team == team:
		return true
	var shroud := shroud_for(team)
	for covered in building.cells():
		if shroud.is_explored(covered):
			return true
	return false


# --- Orichalcum ------------------------------------------------------------------

## Orichalcum a team has in store.
func stored_for(team: int) -> int:
	return int(stored.get(team, 0))


## How much Orichalcum a team can store: the sum of what its buildings hold.
func storage_for(team: int) -> int:
	var total := 0
	for building in buildings:
		if building.team == team:
			total += building.type.storage
	return total


## Take Orichalcum out of a team's store. Returns false, and takes nothing,
## if there is not that much in it.
func spend(team: int, amount: int) -> bool:
	if amount > stored_for(team):
		return false
	stored[team] = stored_for(team) - amount
	return true


## Put Orichalcum back into a team's store. It is the team's own, so all of
## it comes back, even if that leaves the store fuller than its limit for a
## while (harvesters then wait until there is room again).
func refund(team: int, amount: int) -> void:
	stored[team] = stored_for(team) + amount


## Power a team's buildings make, and power they use.
func power_made(team: int) -> int:
	var total := 0
	for building in buildings:
		if building.team == team and building.type.power > 0:
			total += building.type.power
	return total


func power_used(team: int) -> int:
	var total := 0
	for building in buildings:
		if building.team == team and building.type.power < 0:
			total -= building.type.power
	return total


## Does a team use more power than it makes? Then it builds at half speed.
func is_low_power(team: int) -> bool:
	return power_used(team) > power_made(team)


## Put a new unit on the free cell nearest to the front (the bottom edge) of
## a building. Returns null if there is no free cell near it.
func add_unit_beside(type: UnitType, team: int, building: SimBuilding) -> SimUnit:
	var door := building.cell + Vector2i(building.type.footprint.x / 2, building.type.footprint.y)
	door = door.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var cell := nearest_free_cell(door, 0)
	if cell == NO_CELL or _cells_apart(cell, door) > 4:
		return null
	var unit := add_unit(type, team, cell)
	if unit != null:
		unit.facing = 0
	return unit


## The deposit a cell belongs to, or null.
func deposit_at(cell: Vector2i) -> Deposit:
	if not map.in_bounds(cell):
		return null
	var id := _deposit[_index(cell)]
	return null if id == 0 else deposits[id - 1]


## Orichalcum left in all deposits of the map together.
func ore_left() -> int:
	var total := 0
	for deposit in deposits:
		total += deposit.amount
	return total


## Tell harvesters to work a deposit: drive to it, unhitch the trailer, dig
## and fill it, take the load to a refinery and come back, until the deposit
## has run out. `cell` is any cell of the deposit. Other units ignore the
## order. Returns false if the cell is not a deposit or no harvester was among
## the units.
func order_harvest(unit_ids: Array, cell: Vector2i) -> bool:
	var deposit := deposit_at(cell)
	if deposit == null:
		return false
	var any := false
	for id in unit_ids:
		var unit := get_unit(id)
		if unit == null or not unit.type.is_harvester():
			continue
		any = true
		unit.unload_first = false
		var at_work := unit.trailer_id != 0 and unit.order == SimUnit.Order.HARVEST and not unit.leaving
		if at_work and unit.deposit_id == deposit.id:
			continue                            # it is a robot at this rock already
		_start_trip(unit, SimUnit.Job.TO_DEPOSIT)
		unit.deposit_id = deposit.id
	return any


## Tell harvesters to take what they carry to a refinery now. Afterwards they
## go back to the deposit they were working, if it has anything left. Returns
## false if the building is not a refinery or no harvester of its side was
## among the units.
func order_unload(unit_ids: Array, building_id: int) -> bool:
	var refinery := get_building(building_id)
	if refinery == null or not refinery.type.is_refinery:
		return false
	var any := false
	for id in unit_ids:
		var unit := get_unit(id)
		if unit == null or not unit.type.is_harvester() or unit.team != refinery.team:
			continue
		_start_trip(unit, SimUnit.Job.TO_REFINERY)
		unit.refinery_id = refinery.id
		unit.unload_first = true
		any = true
	return any


func _start_trip(unit: SimUnit, job: SimUnit.Job) -> void:
	_stop(unit)
	_quit_job(unit)
	unit.order = SimUnit.Order.HARVEST
	unit.order_target = 0
	unit.target_id = 0
	unit.retry_tick = -1000
	# A robot becomes a truck again first, and sets off after that.
	if unit.is_robot():
		unit.next_job = job
	else:
		unit.job = job


## Take a harvester off what it is doing because it has new orders. A robot
## goes back to its trailer and becomes a truck before it does anything else.
func _quit_job(unit: SimUnit) -> void:
	if not unit.type.is_harvester():
		return
	unit.work_part = 0
	unit.has_held_goal = false
	unit.next_job = SimUnit.Job.NONE
	if unit.trailer_id != 0:
		unit.leaving = true
	elif unit.job == SimUnit.Job.DEPLOY:
		unit.job = SimUnit.Job.PACK             # the trailer is still hitched: just fold up again
		unit.job_ticks_left = unit.type.transform_ticks()
		unit.park_facing = unit.facing
	elif unit.job != SimUnit.Job.PACK:
		unit.job = SimUnit.Job.NONE


## One tick of a harvester. Returns true while it works or fights on the spot,
## false while it is driving or walking (or has nothing to do).
func _act_harvester(unit: SimUnit) -> bool:
	if unit.trailer_id != 0:
		return _act_robot(unit)
	# A truck. One that is attacked stops, unhitches and guards its trailer,
	# unless it has been told to move: then it drives on.
	if unit.order != SimUnit.Order.MOVE and _threat(unit) != null:
		_stop(unit)
		_start_deploy(unit, SimUnit.Job.GUARD)
		return true
	if unit.order != SimUnit.Order.HARVEST:
		return false
	match unit.job:
		SimUnit.Job.NONE:
			_next_trip(unit)
		SimUnit.Job.TO_DEPOSIT:
			return _go_to_deposit(unit)
		SimUnit.Job.TO_REFINERY:
			return _go_to_refinery(unit)
		SimUnit.Job.UNLOAD:
			return _unload(unit)
		_:
			unit.job = SimUnit.Job.NONE
	return false


## One tick of a harvester in its robot shape.
func _act_robot(unit: SimUnit) -> bool:
	var trailer := get_trailer(unit.trailer_id)
	if unit.leaving:
		return _go_hitch(unit, trailer)
	var threat := _threat(unit)
	if threat != null:
		if unit.job != SimUnit.Job.GUARD:
			_stop(unit)
			# Remember whether there is work to come back to.
			unit.next_job = SimUnit.Job.TO_ROCK if unit.order == SimUnit.Order.HARVEST else SimUnit.Job.NONE
			unit.job = SimUnit.Job.GUARD
			unit.work_part = 0
		unit.threat_tick = tick_count
		return _guard(unit, trailer, threat)
	if unit.job == SimUnit.Job.GUARD:
		if tick_count - unit.threat_tick >= CALM_TICKS:
			_resume(unit)
		return true
	if unit.order != SimUnit.Order.HARVEST:
		unit.leaving = true                     # a robot with no work: be a truck again
		unit.next_job = SimUnit.Job.NONE
		return true
	match unit.job:
		SimUnit.Job.TO_ROCK:
			return _go_to_rock(unit, trailer)
		SimUnit.Job.EXTRACT:
			_extract(unit)
		SimUnit.Job.TO_TRAILER:
			return _go_to_trailer(unit, trailer)
		SimUnit.Job.LOAD:
			_load(unit)
		_:
			unit.job = SimUnit.Job.TO_ROCK
	return true


## Decide where a truck goes next: to a refinery when it is full or there is
## nothing left to fetch, otherwise to a deposit. With an empty trailer and no
## Orichalcum left anywhere, its work is done.
func _next_trip(unit: SimUnit) -> void:
	var deposit := _working_deposit(unit)
	if unit.cargo >= unit.type.cargo_capacity or (unit.cargo > 0 and (deposit == null or unit.unload_first)):
		unit.job = SimUnit.Job.TO_REFINERY
	elif deposit != null:
		unit.job = SimUnit.Job.TO_DEPOSIT
	else:
		unit.order = SimUnit.Order.NONE
		_stop(unit)
	unit.retry_tick = -1000


## The deposit a harvester should work: its own while that has Orichalcum,
## otherwise the nearest one that has and that it can drive up to. Null if
## there is none.
func _working_deposit(unit: SimUnit) -> Deposit:
	if unit.deposit_id != 0 and not deposits[unit.deposit_id - 1].is_empty():
		return deposits[unit.deposit_id - 1]
	var best: Deposit = null
	var best_distance := 0
	for deposit in deposits:
		if deposit.is_empty():
			continue
		var spot := _spot_beside(unit, deposit.cells)
		if spot == NO_CELL:
			continue
		var distance := (spot - unit.cell).length_squared()
		if best == null or distance < best_distance:
			best = deposit
			best_distance = distance
	if best != null:
		unit.deposit_id = best.id
	return best


## Drive to the deposit and park as near as possible to rock that still holds
## Orichalcum. There the truck starts to unfold.
func _go_to_deposit(unit: SimUnit) -> bool:
	var deposit := _working_deposit(unit)
	if deposit == null:
		unit.job = SimUnit.Job.NONE             # it ran out on the way: decide again
		_stop(unit)
		return false
	if unit.has_goal or tick_count - unit.retry_tick < RETRY_TICKS:
		return false
	var rock := _live_cell_beside(unit.cell, deposit)
	var spot := unit.cell if rock != NO_CELL else nearest_free_cell(deposit.nearest_live_cell(unit.cell), region_at(unit.cell), {}, {unit.id: true})
	if spot == NO_CELL:
		unit.retry_tick = tick_count
		return false
	if spot != unit.cell:
		_set_goal(unit, spot)
		return false
	if rock == NO_CELL:
		rock = deposit.nearest_live_cell(unit.cell)
	unit.job_cell = rock
	unit.facing = facing_toward(rock - unit.cell)
	_start_deploy(unit, SimUnit.Job.TO_ROCK)
	return true


## Walk to the place to dig from: beside the Orichalcum nearest to the trailer.
func _go_to_rock(unit: SimUnit, trailer: SimTrailer) -> bool:
	var deposit := deposits[unit.deposit_id - 1] if unit.deposit_id != 0 else null
	if deposit == null or deposit.is_empty() or unit.cargo + unit.pack >= unit.type.cargo_capacity:
		unit.job = SimUnit.Job.TO_TRAILER       # nothing more to dig here
		return true
	if unit.has_goal:
		return false
	if tick_count - unit.retry_tick < RETRY_TICKS:
		return true
	var spot := _dig_spot(unit, deposit, trailer)
	if spot == NO_CELL:
		unit.retry_tick = tick_count
		return true
	if unit.dug_here and _cells_apart(spot, trailer.cell) > REPARK_CELLS:
		unit.leaving = true                     # too far to carry: move the trailer nearer
		unit.next_job = SimUnit.Job.NONE
		return true
	if spot != unit.cell:
		_set_goal(unit, spot)
		return false
	unit.job_cell = deposit.nearest_live_cell(unit.cell)
	unit.facing = facing_toward(unit.job_cell - unit.cell)
	unit.job = SimUnit.Job.EXTRACT
	unit.work_part = 0
	return true


## Dig: fill the pack on the robot's back.
func _extract(unit: SimUnit) -> void:
	var type := unit.type
	var deposit := deposits[unit.deposit_id - 1]
	var room := mini(type.pack_capacity - unit.pack, type.cargo_capacity - unit.cargo - unit.pack)
	var dug: Array[Vector2i] = []
	var got := deposit.take(unit.cell, mini(_work_step(unit, type.harvest_rate), room), dug)
	unit.pack += got
	if got > 0:
		unit.dug_here = true
		unit.job_cell = dug[0]
		unit.facing = facing_toward(dug[0] - unit.cell)
	if got >= room or deposit.is_empty():
		unit.job = SimUnit.Job.TO_TRAILER
		unit.work_part = 0


## Walk back to the trailer with a full pack.
func _go_to_trailer(unit: SimUnit, trailer: SimTrailer) -> bool:
	if _cells_apart(unit.cell, trailer.cell) == 1:
		_stop(unit)
		unit.facing = facing_toward(trailer.cell - unit.cell)
		unit.job = SimUnit.Job.LOAD
		unit.work_part = 0
		return true
	_walk_to_trailer(unit, trailer)
	return false


## Tip the pack into the trailer. Then dig on, or, with the trailer full or
## the deposit empty, hitch up and leave.
func _load(unit: SimUnit) -> void:
	var moved := mini(_work_step(unit, unit.type.load_rate), unit.pack)
	unit.pack -= moved
	unit.cargo += moved
	if unit.pack > 0:
		return
	var deposit := deposits[unit.deposit_id - 1] if unit.deposit_id != 0 else null
	if deposit == null or deposit.is_empty() or unit.cargo >= unit.type.cargo_capacity:
		unit.leaving = true
		unit.next_job = SimUnit.Job.NONE
	else:
		unit.job = SimUnit.Job.TO_ROCK
		unit.retry_tick = -1000


func _go_to_refinery(unit: SimUnit) -> bool:
	var refinery := _refinery_for(unit)
	if refinery == null:
		return false                            # nowhere to take it: wait
	if refinery.is_beside(unit.cell):
		_stop(unit)
		unit.facing = facing_toward(Vector2i(refinery.center().floor()) - unit.cell)
		unit.job = SimUnit.Job.UNLOAD
		unit.work_part = 0
		return true
	_drive_beside(unit, refinery.cells())
	return false


## Hand cargo over to the refinery. When the side's storage is full the truck
## waits there with what it still has.
func _unload(unit: SimUnit) -> bool:
	if get_building(unit.refinery_id) == null:
		unit.job = SimUnit.Job.TO_REFINERY
		return false
	var room := storage_for(unit.team) - stored_for(unit.team)
	if room <= 0:
		unit.work_part = 0
		return true                             # the store is full: wait
	var moved := mini(mini(_work_step(unit, unit.type.unload_rate), unit.cargo), room)
	unit.cargo -= moved
	stored[unit.team] = stored_for(unit.team) + moved
	if unit.cargo == 0:
		unit.unload_first = false
		unit.job = SimUnit.Job.NONE             # next tick: back to the deposit
	return true


## Is a harvester standing at its refinery with a load that the full store
## cannot take?
func is_waiting_for_room(unit: SimUnit) -> bool:
	return unit.job == SimUnit.Job.UNLOAD and unit.cargo > 0 and stored_for(unit.team) >= storage_for(unit.team)


## How much a harvester moves this tick at `rate` units of Orichalcum a second.
func _work_step(unit: SimUnit, rate: int) -> int:
	unit.work_part += rate
	var whole := unit.work_part / TICKS_PER_SECOND
	unit.work_part -= whole * TICKS_PER_SECOND
	return whole


## The refinery a harvester unloads at: the one it was sent to, otherwise the
## nearest of its side. Null if its side has none.
func _refinery_for(unit: SimUnit) -> SimBuilding:
	var chosen := get_building(unit.refinery_id)
	if chosen != null and chosen.team == unit.team and chosen.type.is_refinery:
		return chosen
	var best: SimBuilding = null
	var best_distance := 0.0
	for building in buildings:
		if building.team != unit.team or not building.type.is_refinery:
			continue
		var distance := building.center().distance_squared_to(Vector2(unit.cell))
		if best == null or distance < best_distance:
			best = building
			best_distance = distance
	unit.refinery_id = best.id if best != null else 0
	return best


## Send a harvester that stands still to the nearest free cell beside some
## cells (a building, or a trailer). If every such cell is taken it waits and
## looks again a little later.
func _drive_beside(unit: SimUnit, cells: Array[Vector2i]) -> void:
	if unit.has_goal or tick_count - unit.retry_tick < RETRY_TICKS:
		return
	var spot := _spot_beside(unit, cells)
	if spot == NO_CELL:
		unit.retry_tick = tick_count
	else:
		_set_goal(unit, spot)


## The free cell nearest to a unit that touches one of the given cells (a side
## or a corner) and that the unit can reach. NO_CELL if there is none.
func _spot_beside(unit: SimUnit, cells: Array[Vector2i]) -> Vector2i:
	var best := NO_CELL
	var best_distance := 0
	var region := region_at(unit.cell)
	for cell in cells:
		for step in AROUND:
			var spot := cell + step
			if not map.in_bounds(spot):
				continue
			var index := _index(spot)
			if _region[index] != region or _taken(index, unit.id):
				continue
			var distance := (spot - unit.cell).length_squared()
			if best == NO_CELL or distance < best_distance \
					or (distance == best_distance and (spot.y < best.y or (spot.y == best.y and spot.x < best.x))):
				best = spot
				best_distance = distance
	return best


## A cell of a deposit that touches a cell and still holds Orichalcum, or
## NO_CELL. Cells that share a side come before those that touch at a corner.
func _live_cell_beside(cell: Vector2i, deposit: Deposit) -> Vector2i:
	for step in AROUND:
		var near := cell + step
		if deposit.has_cell(near) and not deposit.is_spent(near):
			return near
	return NO_CELL


## Where a robot digs from: the free cell beside the Orichalcum nearest to its
## trailer, on the trailer's side. If rock that is spent lies between, the
## nearest free cell to that Orichalcum. NO_CELL if there is none.
func _dig_spot(unit: SimUnit, deposit: Deposit, trailer: SimTrailer) -> Vector2i:
	var live := deposit.nearest_live_cell(trailer.cell)
	if live == NO_CELL:
		return NO_CELL
	var best := NO_CELL
	var best_distance := 0
	var region := region_at(unit.cell)
	for step in AROUND:
		var spot := live + step
		if not map.in_bounds(spot):
			continue
		var index := _index(spot)
		if _region[index] != region or _taken(index, unit.id):
			continue
		var distance := (spot - trailer.cell).length_squared()
		if (best == NO_CELL or distance < best_distance) and _can_walk_to(unit, spot):
			best = spot
			best_distance = distance
	if best == NO_CELL:
		best = nearest_free_cell(live, region, {}, {unit.id: true})
		if best != NO_CELL and not _can_walk_to(unit, best):
			best = unit.cell                    # walled in by trailers and units: dig from here
	return best


## Is there a way for a unit to a cell right now, around trailers and around
## units that are staying put?
func _can_walk_to(unit: SimUnit, cell: Vector2i) -> bool:
	if cell == unit.cell:
		return true
	var blocked: Array[Vector2i] = []
	for other in units:
		if other != unit and not other.dead and other.is_settled():
			blocked.append(other.cell)
	for trailer in trailers:
		blocked.append(trailer.cell)
	for at in blocked:
		_astar.set_point_solid(at, true)
	var found := not _astar.get_id_path(unit.cell, cell).is_empty()
	for at in blocked:
		_astar.set_point_solid(at, false)
	return found


## How many steps apart two cells are (a diagonal step counts as one).
static func _cells_apart(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Group the ore-bearing cells of the map into deposits: cells that touch
## (a side or a corner) belong to the same one.
func _find_deposits() -> void:
	_deposit.resize(size.x * size.y)
	_deposit.fill(0)
	for y in size.y:
		for x in size.x:
			var start := Vector2i(x, y)
			if _deposit[_index(start)] != 0 or map.terrain_at(start).ore <= 0:
				continue
			var deposit := Deposit.new()
			deposit.id = deposits.size() + 1
			deposit.spent_log = spent_log
			deposits.append(deposit)
			_deposit[_index(start)] = deposit.id
			var stack: Array[Vector2i] = [start]
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				deposit.add_cell(cell, map.terrain_at(cell).ore)
				for step in AROUND:
					var near := cell + step
					if map.in_bounds(near) and _deposit[_index(near)] == 0 and map.terrain_at(near).ore > 0:
						_deposit[_index(near)] = deposit.id
						stack.append(near)


# --- truck, robot and trailer ------------------------------------------------------

## The trailer with this id (one that stands on its own), or null.
func get_trailer(id: int) -> SimTrailer:
	return _trailers_by_id.get(id)


## The trailer standing on a cell, or null.
func trailer_at(cell: Vector2i) -> SimTrailer:
	if not map.in_bounds(cell):
		return null
	var id := _trailer_cell[_index(cell)]
	return null if id == 0 else _trailers_by_id[id]


## Orichalcum in a trailer that stands on its own.
func trailer_cargo(trailer: SimTrailer) -> int:
	var owner := get_unit(trailer.owner_id)
	return owner.cargo if owner != null else trailer.cargo


## Can a team see a trailer? Its own always, others on ground it has explored.
func is_trailer_visible_to(trailer: SimTrailer, team: int) -> bool:
	return trailer.team == team or shroud_for(team).is_explored(trailer.cell)


## Orichalcum a team has taken out of other sides' orphaned trailers.
func stolen_for(team: int) -> int:
	return int(stolen.get(team, 0))


## Begin to change a truck into a robot. `then` is what the robot does next.
func _start_deploy(unit: SimUnit, then: SimUnit.Job) -> void:
	unit.job = SimUnit.Job.DEPLOY
	unit.job_ticks_left = unit.type.transform_ticks()
	unit.next_job = then
	unit.work_part = 0


## A change of shape has run its time. Returns true if the unit is a truck
## that may act in this tick, false if it is (still) busy.
func _change_shape(unit: SimUnit) -> bool:
	if unit.job == SimUnit.Job.DEPLOY:
		if not _unhitch(unit):
			unit.job_ticks_left = 1             # no room to step off: try again next tick
			return false
		unit.job = unit.next_job
		unit.next_job = SimUnit.Job.NONE
		unit.threat_tick = tick_count
		return false
	unit.job = unit.next_job
	unit.next_job = SimUnit.Job.NONE
	unit.leaving = false
	unit.facing = unit.park_facing
	if unit.has_held_goal:
		unit.has_held_goal = false
		_set_goal(unit, unit.held_goal)
	return true


## The robot steps off: the trailer stays on the truck's cell and the robot
## takes a free cell next to it, towards its work. Returns false if every
## cell around is taken.
func _unhitch(unit: SimUnit) -> bool:
	var toward := unit.job_cell
	if unit.next_job == SimUnit.Job.GUARD:
		var threat := _threat(unit)
		toward = threat.cell if threat != null else unit.cell
	var best := NO_CELL
	var best_score := 0
	var region := region_at(unit.cell)
	for i in AROUND.size():
		var spot := unit.cell + AROUND[i]
		if not map.in_bounds(spot) or _region[_index(spot)] != region or _taken(_index(spot)):
			continue
		# Cells that share a side come first; among those, the one nearest to the work.
		var score := (spot - toward).length_squared() + (0 if i < 4 else 10000)
		if best == NO_CELL or score < best_score:
			best = spot
			best_score = score
	if best == NO_CELL:
		return false
	var trailer := SimTrailer.new()
	trailer.id = _next_id
	_next_id += 1
	trailer.team = unit.team
	trailer.type = unit.type
	trailer.cell = unit.cell
	trailer.facing = unit.facing
	trailer.owner_id = unit.id
	_add_trailer(trailer)
	unit.trailer_id = trailer.id
	unit.dug_here = false
	_begin_step(unit, best)
	return true


func _add_trailer(trailer: SimTrailer) -> void:
	trailers.append(trailer)
	_trailers_by_id[trailer.id] = trailer
	_trailer_cell[_index(trailer.cell)] = trailer.id


func _remove_trailer(trailer: SimTrailer) -> void:
	trailers.erase(trailer)
	_trailers_by_id.erase(trailer.id)
	if _trailer_cell[_index(trailer.cell)] == trailer.id:
		_trailer_cell[_index(trailer.cell)] = 0


## A robot that is leaving: walk up to the trailer, step onto it and fold up.
func _go_hitch(unit: SimUnit, trailer: SimTrailer) -> bool:
	if _cells_apart(unit.cell, trailer.cell) != 1:
		_walk_to_trailer(unit, trailer)
		return false
	_stop(unit)
	# What is in the pack goes into the trailer with it.
	unit.cargo += unit.pack
	unit.pack = 0
	unit.park_facing = trailer.facing
	_remove_trailer(trailer)
	_begin_step(unit, trailer.cell)             # at the robot's pace: it still has its trailer_id
	unit.trailer_id = 0
	unit.job = SimUnit.Job.PACK
	unit.job_ticks_left = unit.type.transform_ticks()
	unit.work_part = 0
	return true


## Send a robot to the nearest free cell beside its trailer.
func _walk_to_trailer(unit: SimUnit, trailer: SimTrailer) -> void:
	if unit.has_goal and _cells_apart(unit.goal, trailer.cell) == 1:
		return
	_drive_beside(unit, [trailer.cell] as Array[Vector2i])


## The enemy a harvester has to deal with, or null. A robot minds any enemy
## fighter that comes near its trailer or itself; a truck only once it has
## been hit. Other sides' harvesters are no threat: they never attack.
func _threat(unit: SimUnit) -> SimUnit:
	var robot := unit.trailer_id != 0
	var hurt := tick_count - unit.last_hurt_tick <= PROVOKED_TICKS
	if not robot and not hurt:
		return null
	var around := get_trailer(unit.trailer_id).cell if robot else unit.cell
	var best := nearest_fighter(around, unit.team, unit.type.acquire_range)
	if best == null and robot:
		best = nearest_fighter(unit.cell, unit.team, unit.type.acquire_range)
	if best == null and hurt:
		var attacker := get_unit(unit.provoked_by)
		# The one that hit it, unless it has been left well behind.
		if attacker != null and attacker.team != unit.team \
				and in_range(around, attacker.cell, unit.type.acquire_range + LEASH_EXTRA):
			best = attacker
	return best


## The nearest unit of another team that can fight, within `reach` cells of a
## cell, or null. Harvesters do not count.
func nearest_fighter(cell: Vector2i, team: int, reach: int) -> SimUnit:
	var best: SimUnit = null
	var best_distance := 0
	for other in units:
		if other.team == team or other.dead or other.type.is_harvester() or other.type.attack_damage <= 0:
			continue
		if not in_range(cell, other.cell, reach):
			continue
		var distance := (other.cell - cell).length_squared()
		if best == null or distance < best_distance:
			best = other
			best_distance = distance
	return best


## Stand guard: stay on a cell beside the trailer, on the side the enemy is
## on, and hit whatever comes within reach.
func _guard(unit: SimUnit, trailer: SimTrailer, threat: SimUnit) -> bool:
	if _cells_apart(unit.cell, trailer.cell) == 1:
		# It keeps hitting the enemy it has started on for as long as that one is within reach.
		var foe := get_unit(unit.target_id)
		if foe == null or foe.team == unit.team or not in_range(unit.cell, foe.cell, unit.type.attack_range):
			foe = nearest_fighter(unit.cell, unit.team, unit.type.attack_range)
		unit.target_id = foe.id if foe != null else 0
		if foe != null:
			_stop(unit)
			unit.facing = facing_toward(foe.cell - unit.cell)
			if unit.attack_ticks_left == 0 and unit.type.attack_damage > 0:
				_strike(unit, foe)
			return true
	var best := NO_CELL
	var best_distance := 0
	var region := region_at(unit.cell)
	for step in AROUND:
		var spot := trailer.cell + step
		if not map.in_bounds(spot) or _region[_index(spot)] != region or _taken(_index(spot), unit.id):
			continue
		var distance := (spot - threat.cell).length_squared() * 100 + (spot - unit.cell).length_squared()
		if best == NO_CELL or distance < best_distance:
			best = spot
			best_distance = distance
	if best == NO_CELL or best == unit.cell:
		_stop(unit)
		unit.facing = facing_toward(threat.cell - unit.cell)
		return true
	if not unit.has_goal or unit.goal != best:
		_set_goal(unit, best)
	return false


## The enemy is gone: back to digging if there is digging left here,
## otherwise hitch up and carry on as a truck.
func _resume(unit: SimUnit) -> void:
	unit.work_part = 0
	var deposit := deposits[unit.deposit_id - 1] if unit.deposit_id != 0 else null
	var work := unit.next_job == SimUnit.Job.TO_ROCK and unit.order == SimUnit.Order.HARVEST and not unit.unload_first
	unit.next_job = SimUnit.Job.NONE
	if work and deposit != null and not deposit.is_empty() and unit.cargo + unit.pack < unit.type.cargo_capacity:
		unit.job = SimUnit.Job.TO_TRAILER if unit.pack > 0 else SimUnit.Job.TO_ROCK
		unit.retry_tick = -1000
	else:
		unit.leaving = true


## A harvester has been destroyed. Its trailer is left behind as an orphan if
## there is Orichalcum in it, and is gone if there is none. What the robot
## had in its pack is lost.
func _orphan_trailer(unit: SimUnit) -> void:
	var trailer := get_trailer(unit.trailer_id)
	unit.trailer_id = 0
	if trailer == null:
		if unit.cargo <= 0:
			return
		trailer = SimTrailer.new()              # it died as a truck: the trailer stays where it stood
		trailer.id = _next_id
		_next_id += 1
		trailer.team = unit.team
		trailer.type = unit.type
		trailer.cell = unit.cell
		trailer.facing = unit.facing
		_add_trailer(trailer)
	trailer.owner_id = 0
	trailer.cargo = unit.cargo
	if trailer.cargo <= 0:
		_remove_trailer(trailer)


## Units standing next to an orphaned trailer of another side take its
## Orichalcum: all of it if their side has no storage, otherwise as much as
## fits into their store. An empty orphan is gone.
func _take_orphans() -> void:
	for trailer: SimTrailer in trailers.duplicate():
		if not trailer.is_orphan():
			continue
		for unit in units:
			if unit.dead or unit.team == trailer.team or unit.is_moving() or _cells_apart(unit.cell, trailer.cell) != 1:
				continue
			var take := trailer.cargo
			var storage := storage_for(unit.team)
			if storage > 0:
				take = mini(take, storage - stored_for(unit.team))
			if take <= 0:
				continue
			trailer.cargo -= take
			if storage > 0:
				stored[unit.team] = stored_for(unit.team) + take
			stolen[unit.team] = stolen_for(unit.team) + take
			effects.append({
				"kind": &"steal", "tick": tick_count, "team": unit.team,
				"from": Vector2(trailer.cell), "to": unit.visual_cell(),
			})
			if trailer.cargo <= 0:
				_remove_trailer(trailer)
				break


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
	if _trailer_cell[_index(unit.goal)] != 0 or (at_goal != null and at_goal != unit and at_goal.is_settled()):
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
	if _trailer_cell[_index(next)] != 0:
		unit.path.clear()                   # a trailer has been parked there: plan again
		_blocked(unit, 0)
	elif other == null:
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
	var diagonal := step.x != 0 and step.y != 0
	unit.move_ticks_total = unit.type.robot_ticks_per_cell(diagonal) if unit.trailer_id != 0 else unit.type.ticks_per_cell(diagonal)
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
## staying put (and, if asked, around every other unit) and around trailers. If the goal cannot be
## reached the path leads as close to it as possible.
func _find_path(unit: SimUnit, around_everyone: bool) -> void:
	var blocked: Array[Vector2i] = []
	for other in units:
		if other != unit and not other.dead and (around_everyone or other.is_settled()):
			blocked.append(other.cell)
			_astar.set_point_solid(other.cell, true)
	for trailer in trailers:
		blocked.append(trailer.cell)
		_astar.set_point_solid(trailer.cell, true)
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
			if _region[_index(start)] != 0 or not _is_open(start):
				continue
			next_region += 1
			_region[_index(start)] = next_region
			var stack: Array[Vector2i] = [start]
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var near: Vector2i = cell + step
					if _is_open(near) and _region[_index(near)] == 0:
						_region[_index(near)] = next_region
						stack.append(near)
