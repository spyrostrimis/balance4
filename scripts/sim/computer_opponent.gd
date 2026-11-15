class_name ComputerOpponent
extends RefCounted
## The computer opponent of a skirmish. It plays one side with the same
## rules and the same orders as the player: it queues buildings and units in
## its Production queues and pays for them out of its own store, places what
## its headquarters finishes on explored building ground, keeps its power up,
## sends its harvesters to the rock, defends its base and its harvesters, and
## attacks in waves.
##
## It looks at the world once a second (THINK_TICKS). What it does is decided
## in this order:
##
## 1. Base: build what is next on its list (BASE_PLAN), a generator first
##    whenever the next building would leave it short of power, and place
##    every finished building near its headquarters.
## 2. Economy: keep HARVESTERS harvesters, and send idle ones to the rock.
##    While it has a workshop and too few harvesters it saves up for one
##    and queues nothing else.
## 3. Army: train troops at its barracks and tanks at its workshop while it
##    can afford them and has fewer than ARMY_LIMIT.
## 4. Defence: any enemy unit near its buildings, or an enemy fighter near
##    its harvesters, is attacked by every soldier at home.
## 5. Attack: once ATTACK_AFTER_SECONDS have passed and enough soldiers wait
##    at home (`wave_size`, which grows after every wave), they all set off
##    for the nearest enemy building it has seen, or else the enemy's start.
##    Soldiers of a wave that have nothing left to fight go on to the next
##    target. When it has seen nothing of the enemy where the enemy started,
##    it is told where what is left of the enemy is (a simplification).
## 6. Repair: a building below REPAIR_BELOW of its health is repaired, as
##    the player can, while the store holds more than UNIT_RESERVE.
##
## It never uses a hero's ability. Its numbers are provisional.

## How often it thinks, in ticks.
const THINK_TICKS := 20
## The buildings it wants, in order: the role of each (see role_of) and how
## many of that role it wants to have at that point.
const BASE_PLAN: Array = [
	[&"power", 1], [&"barracks", 1], [&"factory", 1], [&"power", 2], [&"refinery", 2], [&"barracks", 2], [&"power", 3],
]
## How many harvesters it keeps.
const HARVESTERS := 2
## It stops training once it has this many fighters.
const ARMY_LIMIT := 16
## Units are queued only while the store holds at least this much, unless
## nothing is being constructed.
const UNIT_RESERVE := 150
## Size of the first attack wave, how much each wave grows, and the largest wave.
const FIRST_WAVE := 5
const WAVE_GROWTH := 2
const LARGEST_WAVE := 12
## No attack before this.
const ATTACK_AFTER_SECONDS := 150.0
## Enemy units this close to one of its buildings (in cells) are attacked.
const DEFEND_RANGE := 9
## Enemy fighters this close to one of its harvesters or trailers are attacked.
const ESCORT_RANGE := 6
## How far from the middle of its headquarters it builds, in cells.
const BUILD_RADIUS := 14
## The cell its soldiers wait on is this far from the headquarters, towards the middle of the map.
const RALLY_CELLS := 6
## A building below this share of its health is repaired.
const REPAIR_BELOW := 0.6

var world: SimWorld
var team := 1
## The side it plays against, and the cell that side started from.
var enemy_team := 0
var enemy_start := Vector2i.ZERO
## Where its soldiers wait for the next wave.
var rally := Vector2i.ZERO
var wave_size := FIRST_WAVE
## How many waves it has sent so far.
var waves := 0
## Ids of the units it has sent to attack.
var attackers := {}

var _home := Vector2.ZERO


func _init(p_world: SimWorld, p_team: int, p_enemy_team: int, p_enemy_start: Vector2i) -> void:
	world = p_world
	team = p_team
	enemy_team = p_enemy_team
	enemy_start = p_enemy_start
	var hq := world.production.builder(team, Production.BUILDINGS)
	_home = hq.center() if hq != null else Vector2(enemy_start)
	var toward := (Vector2(world.size) / 2.0 - _home).normalized()
	var region := 0
	for unit in world.units:
		if unit.team == team:
			region = world.region_at(unit.cell)
			break
	rally = world.nearest_free_cell(Vector2i((_home + toward * RALLY_CELLS).floor()), region)


## What a building of a side is for, as the computer sees it: &"power",
## &"refinery", &"factory" (it makes harvesters), &"barracks" (it makes other
## units), &"headquarters" or &"other".
static func role_of(type: BuildingType) -> StringName:
	if not type.builds.is_empty():
		return &"headquarters"
	if type.is_refinery:
		return &"refinery"
	for item: UnitType in type.produces:
		if item.is_harvester():
			return &"factory"
	if not type.produces.is_empty():
		return &"barracks"
	if type.power > 0:
		return &"power"
	return &"other"


func tick() -> void:
	if world.tick_count % THINK_TICKS != 0:
		return
	_place_ready()
	_plan_base()
	_keep_harvesting()
	_train()
	_attack(_defend())
	_repair()


## Repair damaged buildings while it can spare the Orichalcum; stop when it cannot.
func _repair() -> void:
	var spare := world.stored_for(team) > UNIT_RESERVE
	for building in world.buildings:
		if building.team != team:
			continue
		if not spare:
			building.repairing = false
		elif not building.repairing and building.health < building.type.max_health * REPAIR_BELOW:
			world.order_repair(building.id, true)


# --- the base ----------------------------------------------------------------------------

func _count(role: StringName) -> int:
	var count := 0
	for building in world.buildings:
		if building.team == team and role_of(building.type) == role:
			count += 1
	return count


## The building type of a role that its headquarters can construct, or null.
func _type_for(role: StringName) -> BuildingType:
	for item: BuildingType in world.production.options(team, Production.BUILDINGS):
		if role_of(item) == role:
			return item
	return null


## Queue the next building on the plan, if nothing is being constructed.
func _plan_base() -> void:
	var production := world.production
	if production.builder(team, Production.BUILDINGS) == null:
		return
	if not production.line(team, Production.BUILDINGS).is_empty() or short_of_harvesters():
		return
	var next: BuildingType = null
	for step: Array in BASE_PLAN:
		if _count(step[0]) < int(step[1]):
			next = _type_for(step[0])
			if next != null:
				break
	# A refinery that would leave the side with more than it can keep is wasted: build it only when the store fills up.
	if next != null and role_of(next) == &"refinery" and world.stored_for(team) < world.storage_for(team) * 3 / 4:
		next = null
	var spare := world.power_made(team) - world.power_used(team)
	var power := _type_for(&"power")
	if power != null and ((next != null and next.power < 0 and spare + next.power < 0) or spare < 0):
		next = power
	if next != null:
		production.queue(team, Production.BUILDINGS, next)


## Put a finished building on the map, as near to the headquarters as it fits.
## A building that fits nowhere is cancelled, and what it cost comes back.
func _place_ready() -> void:
	var production := world.production
	var type := production.ready_building(team)
	if type == null:
		return
	var site := find_site(type)
	if site == SimWorld.NO_CELL:
		production.cancel(team, Production.BUILDINGS, 0)
	else:
		production.place(team, site)


## Where the computer would put a building of this type: the free site
## nearest to its headquarters, within BUILD_RADIUS, that keeps a cell of
## room around every building (if there is one; otherwise one that only
## keeps clear of the doors). NO_CELL if there is none.
func find_site(type: BuildingType) -> Vector2i:
	var best := SimWorld.NO_CELL
	var best_score := 0.0
	var corner := Vector2i(_home.floor()) - Vector2i(BUILD_RADIUS, BUILD_RADIUS)
	for y in BUILD_RADIUS * 2:
		for x in BUILD_RADIUS * 2:
			var cell := corner + Vector2i(x, y)
			if not world.production.can_place(team, type, cell):
				continue
			var area := Rect2i(cell, type.footprint)
			if _blocks_a_door(area):
				continue
			var score := (Vector2(cell) + Vector2(type.footprint) / 2.0).distance_to(_home)
			if _crowds(area):
				score += 100.0
			if best == SimWorld.NO_CELL or score < best_score:
				best = cell
				best_score = score
	return best


## Would a building on these cells stand in front of the door of a building
## of its side (the two rows under it, where units come out and harvesters
## unload)?
func _blocks_a_door(area: Rect2i) -> bool:
	for building in world.buildings:
		if building.team != team:
			continue
		var door := Rect2i(building.cell + Vector2i(-1, building.type.footprint.y), Vector2i(building.type.footprint.x + 2, 2))
		if door.intersects(area):
			return true
	return false


## Would a building on these cells touch another building?
func _crowds(area: Rect2i) -> bool:
	var around := area.grow(1)
	for building in world.buildings:
		if around.intersects(building.rect()):
			return true
	return false


# --- the economy ---------------------------------------------------------------------------

## Does it have a workshop to build harvesters with, too few of them and
## Orichalcum left to dig?
func short_of_harvesters() -> bool:
	return _count(&"factory") > 0 and _harvesters().size() < HARVESTERS and world.ore_left() > 0


func _harvesters() -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for unit in world.units:
		if unit.team == team and not unit.dead and unit.type.is_harvester():
			out.append(unit)
	return out


## Send every harvester that stands idle to the rock with the most Orichalcum left nearest to it.
func _keep_harvesting() -> void:
	for unit in _harvesters():
		if unit.order != SimUnit.Order.NONE or unit.is_robot():
			continue
		var best: Deposit = null
		for deposit in world.deposits:
			if deposit.is_empty():
				continue
			if best == null or (deposit.cells[0] - unit.cell).length_squared() < (best.cells[0] - unit.cell).length_squared():
				best = deposit
		if best != null:
			world.order_harvest([unit.id], best.cells[0])


# --- the army ------------------------------------------------------------------------------

## Queue units: harvesters while it has fewer than HARVESTERS (and there is
## Orichalcum to dig), troops at every barracks and tanks at the workshop.
func _train() -> void:
	var production := world.production
	var building_now := not production.line(team, Production.BUILDINGS).is_empty()
	var rich := (world.stored_for(team) >= UNIT_RESERVE or not building_now) and not short_of_harvesters()
	var harvesters := _harvesters().size()
	for key in production.keys(team):
		if key == Production.BUILDINGS:
			continue
		var the_line := production.line(team, key)
		var options := production.options(team, key)
		var wanted: UnitType = null
		var queued_harvesters := 0
		for item: UnitType in the_line.items:
			if item.is_harvester():
				queued_harvesters += 1
		for item: UnitType in options:
			if item.is_harvester():
				if harvesters + queued_harvesters < HARVESTERS and world.ore_left() > 0:
					wanted = item
					break
			elif wanted == null and rich and world.fighter_count(team) + _queued_fighters() < ARMY_LIMIT:
				wanted = item
		if wanted != null and the_line.items.size() < (1 if not wanted.is_harvester() else 2):
			production.queue(team, key, wanted)


func _queued_fighters() -> int:
	var count := 0
	var production := world.production
	for key in production.keys(team):
		if key == Production.BUILDINGS:
			continue
		for item: UnitType in production.line(team, key).items:
			if not item.is_harvester():
				count += 1
	return count


func _fighters() -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for unit in world.units:
		if unit.team == team and not unit.dead and unit.type.attack_damage > 0 and not unit.type.is_harvester():
			out.append(unit)
	return out


## The enemy unit that is the worst threat to the base or the harvesters:
## the one nearest to the headquarters. Null if there is none.
func threat() -> SimUnit:
	var best: SimUnit = null
	var best_distance := 0.0
	var guarded: Array[Vector2i] = []
	for unit in _harvesters():
		guarded.append(unit.cell)
	for trailer in world.trailers:
		if trailer.team == team:
			guarded.append(trailer.cell)
	for enemy in world.units:
		if enemy.team == team or enemy.dead or not world.is_visible_to(enemy, team):
			continue
		var near := false
		for building in world.buildings:
			if building.team == team and SimWorld.in_range(enemy.cell, building.nearest_cell(enemy.cell), DEFEND_RANGE):
				near = true
				break
		if not near and enemy.type.attack_damage > 0 and not enemy.type.is_harvester():
			for cell in guarded:
				if SimWorld.in_range(enemy.cell, cell, ESCORT_RANGE):
					near = true
					break
		if not near:
			continue
		var distance := Vector2(enemy.cell).distance_squared_to(_home)
		if best == null or distance < best_distance:
			best = enemy
			best_distance = distance
	return best


## Send the soldiers at home at the nearest threat. Returns true if there was one.
func _defend() -> bool:
	var enemy := threat()
	if enemy == null:
		return false
	var defenders: Array[int] = []
	for unit in _fighters():
		if attackers.has(unit.id) or unit.order == SimUnit.Order.ATTACK:
			continue
		defenders.append(unit.id)
	if not defenders.is_empty():
		world.order_attack_move(defenders, enemy.cell)
	return true


## Keep the units of earlier waves busy; unless the base is being defended,
## gather idle soldiers at the rally cell and send a wave when it is big enough.
func _attack(defending: bool) -> void:
	var home: Array[int] = []
	var waiting: Array[int] = []
	for unit in _fighters():
		if attackers.has(unit.id):
			if unit.order == SimUnit.Order.NONE and unit.target_id == 0:
				var target := next_target(unit.cell)
				if target != SimWorld.NO_CELL:
					world.order_attack_move([unit.id], target)
			continue
		home.append(unit.id)
		if unit.order == SimUnit.Order.NONE and unit.target_id == 0 and SimWorld._cells_apart(unit.cell, rally) > 3:
			waiting.append(unit.id)
	# Forget attackers that have died.
	for id: int in attackers.keys():
		if world.get_unit(id) == null:
			attackers.erase(id)
	if defending:
		return
	if not waiting.is_empty():
		world.order_attack_move(waiting, rally)
	var late_enough := world.tick_count >= roundi(ATTACK_AFTER_SECONDS * SimWorld.TICKS_PER_SECOND)
	if late_enough and home.size() >= wave_size:
		var target := next_target(rally)
		if target == SimWorld.NO_CELL:
			return
		world.order_attack_move(home, target)
		for id in home:
			attackers[id] = true
		waves += 1
		wave_size = mini(wave_size + WAVE_GROWTH, LARGEST_WAVE)


## Where to send attackers next, from a cell: the nearest enemy building it
## has seen, else the enemy's start until it has seen that, else the nearest
## enemy building or unit wherever it is. NO_CELL when nothing of the enemy
## is left.
func next_target(from: Vector2i) -> Vector2i:
	var shroud := world.shroud_for(team)
	var best := SimWorld.NO_CELL
	for building in world.buildings:
		if building.team == enemy_team and world.is_building_visible_to(building, team):
			var cell := building.nearest_cell(from)
			if best == SimWorld.NO_CELL or (cell - from).length_squared() < (best - from).length_squared():
				best = cell
	if best != SimWorld.NO_CELL:
		return best
	if not shroud.is_explored(enemy_start):
		return enemy_start
	for building in world.buildings:
		if building.team == enemy_team:
			var cell := building.nearest_cell(from)
			if best == SimWorld.NO_CELL or (cell - from).length_squared() < (best - from).length_squared():
				best = cell
	if best != SimWorld.NO_CELL:
		return best
	for unit in world.units:
		if unit.team == enemy_team and not unit.dead:
			if best == SimWorld.NO_CELL or (unit.cell - from).length_squared() < (best - from).length_squared():
				best = unit.cell
	return best
