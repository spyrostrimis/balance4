class_name Production
extends RefCounted
## Spending Orichalcum: constructing buildings and producing units.
##
## Every side has one queue for buildings and one queue for each kind of
## production building it owns. A side needs a headquarters (a building whose
## type lists what it `builds`) to construct buildings, and a production
## building (one whose type lists what it `produces`) to produce units.
##
## An item is paid for bit by bit while it is built, so a side that runs out
## of Orichalcum stops building until more comes in. A finished building waits
## in its queue until it is placed on the map; a finished unit comes out beside
## the building that made it. A side that uses more power than it makes builds
## at half speed.

## The key of a side's queue for buildings. The queue for units has the id of
## the production building's type as its key.
const BUILDINGS := &"buildings"
## How many items a queue holds, the one being built included.
const QUEUE_LIMIT := 5

## The world it belongs to. Held weakly: the world owns its Production, and
## two objects holding each other would never be freed.
var world: SimWorld:
	get:
		return _world.get_ref()

var _world: WeakRef
var _lines := {}        # team -> { key -> BuildLine }


func _init(p_world: SimWorld) -> void:
	_world = weakref(p_world)


## What an item (a BuildingType or a UnitType) costs.
static func cost_of(item: Resource) -> int:
	return int(item.get("cost"))


## How many ticks an item takes to build at full power.
static func ticks_of(item: Resource) -> int:
	return maxi(1, roundi(float(item.get("build_seconds")) * SimWorld.TICKS_PER_SECOND))


## A side's queue with this key. Made the first time it is asked for.
func line(team: int, key: StringName) -> BuildLine:
	if not _lines.has(team):
		_lines[team] = {}
	var lines: Dictionary = _lines[team]
	if not lines.has(key):
		lines[key] = BuildLine.new()
	return lines[key]


## The building of a side that works a queue: its headquarters for BUILDINGS,
## otherwise its first building of the type the key names. Null if it has none.
func builder(team: int, key: StringName) -> SimBuilding:
	for building in world.buildings:
		if building.team != team:
			continue
		if key == BUILDINGS and not building.type.builds.is_empty():
			return building
		if key != BUILDINGS and building.type.id == key and not building.type.produces.is_empty():
			return building
	return null


## The keys of the queues a side can use right now: BUILDINGS first if it has
## a headquarters, then one for each kind of production building it owns, in
## the order they were built.
func keys(team: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if builder(team, BUILDINGS) != null:
		out.append(BUILDINGS)
	for building in world.buildings:
		if building.team == team and not building.type.produces.is_empty() and not out.has(building.type.id):
			out.append(building.type.id)
	return out


## What a side can put into a queue: building types for BUILDINGS, unit types
## otherwise. Empty if it has nothing to work the queue with.
func options(team: int, key: StringName) -> Array[Resource]:
	var out: Array[Resource] = []
	var maker := builder(team, key)
	if maker != null:
		out.assign(maker.type.builds if key == BUILDINGS else maker.type.produces)
	return out


## Why a side cannot add an item to a queue, in words for the player. "" if
## it can.
func problem(team: int, key: StringName, item: Resource) -> String:
	if builder(team, key) == null:
		return "You need a headquarters to build that" if key == BUILDINGS else "The building that makes that is gone"
	if not options(team, key).has(item):
		return "That cannot be built here"
	if line(team, key).items.size() >= QUEUE_LIMIT:
		return "The queue is full"
	return ""


## Add an item to the end of a queue. Returns false (and does nothing) if
## problem() reports one. Nothing is paid until work on the item starts.
func queue(team: int, key: StringName, item: Resource) -> bool:
	if problem(team, key, item) != "":
		return false
	line(team, key).items.append(item)
	return true


## Take the item at `index` out of a queue (by default the last one). What
## has been paid for it is given back. Returns false if there is no such item.
func cancel(team: int, key: StringName, index := -1) -> bool:
	var the_line := line(team, key)
	if index < 0:
		index = the_line.items.size() - 1
	if index < 0 or index >= the_line.items.size():
		return false
	the_line.items.remove_at(index)
	if index == 0:
		world.refund(team, the_line.paid)
		_start_next(the_line)
	return true


## The finished building a side has waiting to be placed, or null.
func ready_building(team: int) -> BuildingType:
	var the_line := line(team, BUILDINGS)
	return the_line.current() as BuildingType if the_line.is_ready() else null


## Can a side put a building of this type with its top-left corner on a
## cell? It must fit there (see SimWorld.can_build) on ground the side has
## explored.
func can_place(team: int, type: BuildingType, cell: Vector2i) -> bool:
	if type == null or not world.can_build(type, cell):
		return false
	var shroud := world.shroud_for(team)
	for y in type.footprint.y:
		for x in type.footprint.x:
			if not shroud.is_explored(cell + Vector2i(x, y)):
				return false
	return true


## Put a side's finished building on the map, its top-left corner on a cell.
## Returns the building, or null if nothing is ready or it cannot stand there.
func place(team: int, cell: Vector2i) -> SimBuilding:
	var type := ready_building(team)
	if type == null or not can_place(team, type, cell):
		return null
	var building := world.add_building(type, team, cell)
	if building == null:
		return null
	var the_line := line(team, BUILDINGS)
	the_line.items.remove_at(0)
	_start_next(the_line)
	return building


## Advance every queue by one tick.
func tick() -> void:
	for team: int in _lines:
		var slow := world.is_low_power(team) and world.tick_count % 2 == 1
		var lines: Dictionary = _lines[team]
		for key: StringName in lines:
			_advance(team, key, lines[key], slow)


func _start_next(the_line: BuildLine) -> void:
	the_line.progress = 0
	the_line.paid = 0
	the_line.waiting = BuildLine.Waiting.NOTHING


func _advance(team: int, key: StringName, the_line: BuildLine, slow: bool) -> void:
	if the_line.is_empty() or the_line.is_ready():
		return
	var maker := builder(team, key)
	if maker == null:
		the_line.waiting = BuildLine.Waiting.BUILDER
		return
	var item := the_line.current()
	var total := ticks_of(item)
	if the_line.progress < total:
		if slow:
			return
		# Pay for the next tick of work: the cost is spread evenly over the build time.
		var due := cost_of(item) * (the_line.progress + 1) / total - the_line.paid
		if not world.spend(team, due):
			the_line.waiting = BuildLine.Waiting.FUNDS
			return
		the_line.paid += due
		the_line.progress += 1
		the_line.waiting = BuildLine.Waiting.NOTHING
		if the_line.progress < total:
			return
	if item is BuildingType:
		the_line.waiting = BuildLine.Waiting.PLACE
		return
	var unit := world.add_unit_beside(item as UnitType, team, maker)
	if unit == null:
		the_line.waiting = BuildLine.Waiting.ROOM
		return
	the_line.items.remove_at(0)
	_start_next(the_line)
	if unit.type.is_harvester() and not world.deposits.is_empty():
		# A new harvester goes to work on its own.
		var nearest: Deposit = null
		for deposit in world.deposits:
			if deposit.is_empty():
				continue
			if nearest == null or (deposit.cells[0] - unit.cell).length_squared() < (nearest.cells[0] - unit.cell).length_squared():
				nearest = deposit
		if nearest != null:
			world.order_harvest([unit.id], nearest.cells[0])
