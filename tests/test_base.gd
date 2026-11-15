extends TestCase
## Base building and production: building and unit costs, the build queues,
## paying bit by bit, placing a finished building, units coming out of their
## production building, power, the base trial, and the build menu on screen.

const FOREST := "res://data/biomes/forest.tres"
const TEAMS := ["blue", "red"]
const KINDS := ["headquarters", "generator", "refinery", "barracks", "workshop"]
const BASES := ["res://data/missions/base_trial_blue.tres", "res://data/missions/base_trial_red.tres"]
const HARVEST_TRIAL := "res://data/missions/harvest_trial_blue.tres"
const MISSION_1 := "res://data/missions/first_claim_blue.tres"
const MAP_SCENE := "res://scenes/map_view.tscn"
const BLUE := 0
const RED := 1
const BUILDINGS := Production.BUILDINGS
const Waiting := BuildLine.Waiting
## Stone to build on at the left, grass around it, a small rock at the right.
const FIELD := [
	"........................",
	".ssssssssss.............",
	".ssssssssss.........oo..",
	".ssssssssss.........oo..",
	".ssssssssss.............",
	".ssssssssss.............",
	"........................",
	"........................",
]
const HQ_SITE := Vector2i(1, 1)


func _type(kind: String, team := "blue") -> BuildingType:
	return load("res://data/buildings/%s_%s.tres" % [team, kind]) as BuildingType


func _unit(kind: String, team := "blue") -> UnitType:
	return load("res://data/units/%s_%s.tres" % [team, kind]) as UnitType


## A world with Blue's headquarters on the stone and Orichalcum in Blue's store.
func _world(orichalcum := 1000) -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(FIELD)
	var world := SimWorld.new(map)
	world.shroud_for(BLUE).reveal_circle(Vector2i(8, 4), 30)
	world.add_building(_type("headquarters"), BLUE, HQ_SITE)
	world.stored[BLUE] = orichalcum
	return world


func _run(world: SimWorld, seconds: float) -> void:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		world.tick()


## Run until `done` returns true. Returns how many ticks that took, or -1 if it never did.
func _ticks_until(world: SimWorld, done: Callable, seconds := 200.0) -> int:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		if done.call():
			return i
		world.tick()
	return -1


## Queue a building, wait until it is ready and put it on a cell.
func _build(world: SimWorld, kind: String, cell: Vector2i) -> SimBuilding:
	var production := world.production
	production.queue(BLUE, BUILDINGS, _type(kind))
	_ticks_until(world, func() -> bool: return production.ready_building(BLUE) != null)
	return production.place(BLUE, cell)


# --- data ----------------------------------------------------------------------------

func test_building_data() -> void:
	for team: String in TEAMS:
		for kind: String in KINDS:
			var type := _type(kind, team)
			check(type != null, "%s %s loads" % [team, kind])
			if type == null:
				continue
			check_eq(type.id, StringName("%s_%s" % [team, kind]), "its id says what it is")
			check(type.display_name != "" and type.blurb != "", "%s has a name and a line for the build menu" % type.id)
			check_eq(type.sprite.get_size(), Vector2(type.footprint * 32 + type.sprite_origin * 2), "%s: its picture covers its cells and a margin" % type.id)
			if kind != "headquarters":
				check(type.cost > 0 and type.build_seconds > 0.0, "%s costs Orichalcum and takes time" % type.id)
		var hq := _type("headquarters", team)
		check_eq(hq.builds.size(), 4, "the headquarters can construct four buildings")
		for kind: String in ["generator", "refinery", "barracks", "workshop"]:
			check(hq.builds.has(_type(kind, team)), "among them the %s" % kind)
		check(hq.power > 0 and hq.storage > 0, "it makes a little power and stores a little")
		check(_type("generator", team).power > 0, "the generator makes power")
		for kind: String in ["refinery", "barracks", "workshop"]:
			check(_type(kind, team).power < 0, "the %s uses power" % kind)
		check_eq(_type("barracks", team).produces, [_unit("infantry", team)] as Array[Resource], "the barracks trains infantry")
		check_eq(_type("workshop", team).produces, [_unit("harvester", team), _unit("tank", team)] as Array[Resource],
				"the workshop builds harvesters and light tanks")
		check(_unit("infantry", team).cost > 0 and _unit("harvester", team).cost > _unit("infantry", team).cost,
				"units cost Orichalcum, a harvester more than a soldier")
		check_eq(_unit("commander", team).cost, 0, "commanders are not for sale")


# --- queues and paying ---------------------------------------------------------------

func test_a_building_is_paid_for_while_it_is_built() -> void:
	var world := _world(500)
	var production := world.production
	var generator := _type("generator")
	check_eq(production.keys(BLUE), [BUILDINGS] as Array[StringName], "a side with a headquarters has a queue for buildings")
	check_eq(production.options(BLUE, BUILDINGS).size(), 4, "with four things to build")
	check_eq(production.problem(BLUE, BUILDINGS, generator), "", "a generator can be queued")
	check(production.queue(BLUE, BUILDINGS, generator), "and is")
	var line := production.line(BLUE, BUILDINGS)
	check_eq(line.current(), generator, "it is the item being built")
	check_eq(world.stored_for(BLUE), 500, "nothing is paid when it is queued")
	_run(world, 4.0)
	check_eq(world.stored_for(BLUE), 425, "half way through, half of its 150 is paid")
	check(absf(line.share() - 0.5) < 0.01, "and the queue says it is half done")
	check(production.ready_building(BLUE) == null, "it is not ready yet")
	_run(world, 4.0)
	check_eq(world.stored_for(BLUE), 350, "after its 8 seconds all of it is paid")
	check(line.is_ready() and line.waiting == Waiting.PLACE, "and it waits to be placed")
	check_eq(production.ready_building(BLUE), generator, "it is the building that is ready")
	_run(world, 10.0)
	check_eq(world.stored_for(BLUE), 350, "waiting costs nothing more")
	check_eq(world.buildings.size(), 1, "it is not on the map until it is placed")


func test_placing_a_finished_building() -> void:
	var world := _world()
	var production := world.production
	var generator := _type("generator")
	check(production.place(BLUE, Vector2i(4, 1)) == null, "nothing can be placed while nothing is ready")
	production.queue(BLUE, BUILDINGS, generator)
	_run(world, 8.0)
	check(not production.can_place(BLUE, generator, Vector2i(12, 3)), "it cannot stand on grass")
	check(not production.can_place(BLUE, generator, Vector2i(10, 4)), "nor half on grass")
	check(not production.can_place(BLUE, generator, Vector2i(2, 2)), "nor on the headquarters")
	check(production.can_place(BLUE, generator, Vector2i(3, 1)), "it can stand on free stone, right beside another building")
	var soldier := world.add_unit(_unit("infantry"), BLUE, Vector2i(6, 4))
	check(not production.can_place(BLUE, generator, Vector2i(5, 3)), "a unit in the way blocks it")
	check(production.can_place(BLUE, generator, Vector2i(7, 3)), "next to the unit it fits")
	check(production.place(BLUE, Vector2i(12, 3)) == null, "placing it on grass does nothing")
	check_eq(production.ready_building(BLUE), generator, "it stays ready")
	var made := world.power_made(BLUE)
	var building := production.place(BLUE, Vector2i(3, 1))
	check(building != null and building.type == generator and building.team == BLUE, "placed on stone it becomes a building")
	check_eq(building.cell, Vector2i(3, 1), "where it was put")
	check(world.building_at(Vector2i(4, 2)) == building, "covering its cells")
	check_eq(world.power_made(BLUE), made + generator.power, "and it works at once: more power")
	check(production.line(BLUE, BUILDINGS).is_empty(), "the queue is empty again")
	check(production.ready_building(BLUE) == null, "and nothing is ready")
	check_eq(soldier.cell, Vector2i(6, 4), "the unit was not touched")


func test_buildings_stand_only_on_explored_ground() -> void:
	var world := _world()
	var production := world.production
	var hidden := world.shroud_for(RED)
	check(not hidden.is_explored(Vector2i(8, 4)), "Red has not seen the stone")
	check(not production.can_place(RED, _type("generator", "red"), Vector2i(7, 3)), "so Red cannot place a building there")
	check(not PlacementView.cell_ok(world, RED, Vector2i(7, 3)), "and its preview shows the cell as bad")
	check(PlacementView.cell_ok(world, BLUE, Vector2i(7, 3)), "Blue, who has, sees it as good")
	check(not PlacementView.cell_ok(world, BLUE, Vector2i(12, 3)), "grass is bad for anyone")
	check(not PlacementView.cell_ok(world, BLUE, Vector2i(1, 1)), "and so is a cell with a building on it")


func test_a_queue_needs_its_building() -> void:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(FIELD)
	var world := SimWorld.new(map)
	world.stored[BLUE] = 1000
	var production := world.production
	check(production.keys(BLUE).is_empty(), "a side with no buildings has no queues")
	check(production.problem(BLUE, BUILDINGS, _type("generator")).contains("headquarters"), "without a headquarters nothing can be constructed")
	check(not production.queue(BLUE, BUILDINGS, _type("generator")), "so queueing fails")
	check(production.options(BLUE, BUILDINGS).is_empty(), "and the menu is empty")
	world = _world()
	production = world.production
	check(production.problem(BLUE, BUILDINGS, _unit("infantry")) != "", "a soldier is not a building")
	check(production.problem(BLUE, BUILDINGS, _type("generator", "red")) != "", "Blue cannot build Red's buildings")
	check(production.problem(BLUE, &"blue_barracks", _unit("infantry")) != "", "without a barracks no soldier can be trained")
	check(production.problem(RED, BUILDINGS, _type("generator", "red")) != "", "and Blue's headquarters is no use to Red")


func test_queue_holds_five_and_builds_in_order() -> void:
	var world := _world()
	var production := world.production
	var order := ["generator", "barracks", "generator", "workshop", "refinery"]
	for kind: String in order:
		check(production.queue(BLUE, BUILDINGS, _type(kind)), "%s goes into the queue" % kind)
	check_eq(production.problem(BLUE, BUILDINGS, _type("generator")), "The queue is full", "a sixth does not")
	check(not production.queue(BLUE, BUILDINGS, _type("generator")), "queueing it fails")
	var line := production.line(BLUE, BUILDINGS)
	check_eq(line.items.size(), 5, "five are queued")
	_run(world, 30.0)
	check_eq(line.current(), _type("generator"), "the first stays at the front until it is placed")
	check_eq(line.items.size(), 5, "and the others wait behind it")
	check_eq(world.stored_for(BLUE), 850, "only the first has been paid for")
	check(production.place(BLUE, Vector2i(3, 1)) != null, "placing it")
	check_eq(line.current(), _type("barracks"), "brings on the next")
	check_eq(line.progress, 0, "from the start")
	_run(world, 10.0)
	check_eq(production.ready_building(BLUE), _type("barracks"), "which is ready after its own build time")


func test_cancelling_gives_the_orichalcum_back() -> void:
	var world := _world(500)
	var production := world.production
	production.queue(BLUE, BUILDINGS, _type("refinery"))
	production.queue(BLUE, BUILDINGS, _type("generator"))
	_run(world, 6.0)
	var line := production.line(BLUE, BUILDINGS)
	check(world.stored_for(BLUE) < 500, "some of the refinery is paid")
	var progress := line.progress
	check(production.cancel(BLUE, BUILDINGS), "cancel takes out the last item")
	check_eq(line.items, [_type("refinery")] as Array[Resource], "the generator that was waiting")
	check_eq(line.progress, progress, "the refinery carries on")
	check(production.cancel(BLUE, BUILDINGS), "cancel again takes out the refinery")
	check(line.is_empty(), "the queue is empty")
	check_eq(world.stored_for(BLUE), 500, "and everything paid for it is back in the store")
	check(not production.cancel(BLUE, BUILDINGS), "there is nothing more to cancel")
	production.queue(BLUE, BUILDINGS, _type("generator"))
	_run(world, 9.0)
	check_eq(world.stored_for(BLUE), 350, "a finished building is paid in full")
	production.cancel(BLUE, BUILDINGS)
	check_eq(world.stored_for(BLUE), 500, "cancelling it before it is placed gives all of it back")
	check(production.ready_building(BLUE) == null, "and nothing is ready any more")


func test_building_stops_when_the_store_is_empty() -> void:
	var world := _world(60)
	var production := world.production
	production.queue(BLUE, BUILDINGS, _type("generator"))
	_run(world, 20.0)
	var line := production.line(BLUE, BUILDINGS)
	check_eq(line.waiting, Waiting.FUNDS, "with too little Orichalcum the work stops")
	check(world.stored_for(BLUE) < 2, "when the store is used up (%d left)" % world.stored_for(BLUE))
	check(line.share() > 0.3 and line.share() < 0.45, "as far as the 60 went (%.2f)" % line.share())
	check_eq(BuildPanel.queue_status(line, false), "Waiting for Orichalcum", "the menu says what it waits for")
	world.stored[BLUE] = 500
	_run(world, 6.0)
	check(line.is_ready(), "with more Orichalcum it is finished")
	check_eq(line.paid, 150, "for exactly its price")


# --- production ----------------------------------------------------------------------

func test_barracks_trains_soldiers() -> void:
	var world := _world()
	var production := world.production
	_build(world, "generator", Vector2i(3, 1))
	var barracks := _build(world, "barracks", Vector2i(5, 1))
	check(barracks != null, "a barracks is built")
	var key: StringName = barracks.type.id
	check_eq(production.keys(BLUE), [BUILDINGS, key] as Array[StringName], "it gives its side a queue of its own")
	check_eq(production.options(BLUE, key), [_unit("infantry")] as Array[Resource], "for soldiers")
	var stored := world.stored_for(BLUE)
	check(production.queue(BLUE, key, _unit("infantry")) and production.queue(BLUE, key, _unit("infantry")), "two soldiers are queued")
	var ticks := _ticks_until(world, func() -> bool: return world.team_size(BLUE) == 1)
	check_eq(ticks, 120, "the first comes out after its 6 seconds")
	var soldier: SimUnit = world.units[0]
	check(soldier.type == _unit("infantry") and soldier.team == BLUE, "it is a Blue soldier")
	check(barracks.is_beside(soldier.cell), "standing beside the barracks")
	check_eq(soldier.cell.y, barracks.cell.y + 2, "in front of it")
	check_eq(world.stored_for(BLUE), stored - 60, "and cost 60")
	check_eq(_ticks_until(world, func() -> bool: return world.team_size(BLUE) == 2), 120, "the second follows after another 6 seconds")
	check(world.units[0].cell != world.units[1].cell, "onto a cell of its own")
	check(production.line(BLUE, key).is_empty(), "then the queue is empty")
	check_eq(world.stored_for(BLUE), stored - 120, "two soldiers cost 120")
	production.queue(BLUE, key, _unit("infantry"))
	production.queue(BLUE, BUILDINGS, _type("workshop"))
	_run(world, 3.0)
	check(production.line(BLUE, key).progress > 0 and production.line(BLUE, BUILDINGS).progress > 0, "the two queues work at the same time")


func test_workshop_builds_a_harvester_that_goes_to_work() -> void:
	var world := _world(2000)
	_build(world, "generator", Vector2i(3, 1))
	_build(world, "refinery", Vector2i(5, 1))
	var workshop := _build(world, "workshop", Vector2i(1, 4))
	check(workshop != null, "a workshop is built")
	world.production.queue(BLUE, workshop.type.id, _unit("harvester"))
	check_eq(_ticks_until(world, func() -> bool: return world.team_size(BLUE) == 1), 240, "a harvester takes 12 seconds")
	var harvester: SimUnit = world.units[0]
	check(harvester.type.is_harvester(), "it is a harvester")
	check_eq(harvester.order, SimUnit.Order.HARVEST, "and it sets off for the rock without being told")
	var stored := world.stored_for(BLUE)
	_run(world, 60.0)
	check(world.stored_for(BLUE) > stored, "and brings Orichalcum home (%d more)" % (world.stored_for(BLUE) - stored))


func test_a_unit_waits_inside_when_there_is_no_room() -> void:
	var world := _world()
	var production := world.production
	_build(world, "generator", Vector2i(3, 1))
	var barracks := _build(world, "barracks", Vector2i(5, 1))
	# Wall the barracks in: every cell within reach of its door is taken.
	var door := barracks.cell + Vector2i(1, 2)
	var blockers := 0
	for y in range(door.y - 4, door.y + 5):
		for x in range(door.x - 4, door.x + 5):
			if world.add_unit(_unit("infantry", "red"), BLUE, Vector2i(x, y)) != null:
				blockers += 1
	production.queue(BLUE, barracks.type.id, _unit("infantry"))
	_run(world, 10.0)
	var line := production.line(BLUE, barracks.type.id)
	check_eq(world.team_size(BLUE), blockers, "with no free cell near the door the soldier does not come out")
	check_eq(line.waiting, Waiting.ROOM, "the queue says it has no room")
	check_eq(BuildPanel.queue_status(line, false), "No room for it to come out", "and so does the menu")
	world._kill(world.unit_at(door))
	_run(world, 1.0)
	check_eq(world.team_size(BLUE), blockers, "once a cell is free it comes out")
	check(world.unit_at(door) != null and world.unit_at(door).type == _unit("infantry"), "onto the free cell")
	check(line.is_empty(), "and the queue moves on")


# --- power ---------------------------------------------------------------------------

func test_power_is_made_and_used() -> void:
	var world := _world()
	check_eq([world.power_made(BLUE), world.power_used(BLUE)], [30, 0], "the headquarters makes 30 power")
	check(not world.is_low_power(BLUE), "which is enough for itself")
	_build(world, "barracks", Vector2i(3, 1))
	check_eq([world.power_made(BLUE), world.power_used(BLUE)], [30, 20], "a barracks uses 20 of it")
	check(not world.is_low_power(BLUE), "still enough")
	_build(world, "workshop", Vector2i(5, 1))
	check_eq([world.power_made(BLUE), world.power_used(BLUE)], [30, 60], "a workshop as well uses more than there is")
	check(world.is_low_power(BLUE), "power is low")
	check_eq(BuildPanel.power_text(world, BLUE), "Power 60 / 30  LOW", "the menu says so")
	check_eq([world.power_made(RED), world.power_used(RED)], [0, 0], "the other side has none of this")
	_build(world, "generator", Vector2i(8, 1))
	check_eq(world.power_made(BLUE), 130, "a generator adds 100")
	check(not world.is_low_power(BLUE), "and power is no longer low")
	check_eq(BuildPanel.power_text(world, BLUE), "Power 60 / 130", "as the menu shows")


func test_low_power_halves_the_building_speed() -> void:
	var world := _world()
	var production := world.production
	var barracks := _build(world, "barracks", Vector2i(3, 1))
	var key: StringName = barracks.type.id
	production.queue(BLUE, key, _unit("infantry"))
	check_eq(_ticks_until(world, func() -> bool: return world.team_size(BLUE) == 1), 120, "with enough power a soldier takes 6 seconds")
	_build(world, "workshop", Vector2i(5, 1))
	check(world.is_low_power(BLUE), "a workshop tips the base into low power")
	production.queue(BLUE, key, _unit("infantry"))
	var ticks := _ticks_until(world, func() -> bool: return world.team_size(BLUE) == 2)
	check(ticks >= 239 and ticks <= 241, "now a soldier takes twice as long (%d ticks)" % ticks)
	check(BuildPanel.queue_status(production.line(BLUE, key), true).contains("half speed") or production.line(BLUE, key).is_empty(),
			"and the menu warns about it")
	production.queue(BLUE, BUILDINGS, _type("generator"))
	ticks = _ticks_until(world, func() -> bool: return production.ready_building(BLUE) != null)
	check(ticks >= 319 and ticks <= 321, "buildings are slowed down too (%d ticks for the generator)" % ticks)
	check_eq(production.line(BLUE, BUILDINGS).paid, 150, "but cost the same")


# --- the base trial ------------------------------------------------------------------

func test_base_trial_start() -> void:
	for path: String in BASES:
		var def := load(path) as MissionDef
		check(def != null and def.practice and def.has_base(), "%s is a practice mission with a base" % path)
		var mission := Mission.new(def)
		var world := mission.world
		var hq := world.get_building(mission.player_headquarters_id)
		var refinery := world.get_building(mission.player_refinery_id)
		check(hq != null and not hq.type.builds.is_empty(), "the player has a headquarters")
		check(refinery != null and refinery.type.is_refinery, "and a refinery")
		check_eq(world.buildings.size(), 2, "and nothing else built")
		check(not hq.rect().intersects(refinery.rect()), "they do not stand on each other")
		check((hq.center() - Vector2(def.map.starts[0])).length() < 8.0, "the headquarters is near the player's start")
		check_eq(world.units.size(), 1, "one unit")
		check(world.units[0].type.is_harvester(), "a harvester")
		check_eq(world.stored_for(BLUE), 500, "500 Orichalcum to start with")
		check_eq(world.storage_for(BLUE), 1000, "room for 1000")
		check_eq(world.deposits[0].capacity, world.deposits[0].cells.size() * 150, "the rock is three times as rich as usual")
		check_eq([world.power_used(BLUE), world.power_made(BLUE)], [30, 30], "the headquarters just powers the refinery")
		check_eq(world.production.keys(BLUE), [BUILDINGS] as Array[StringName], "the player can construct buildings")
		var sites := 0
		for kind: String in ["generator", "barracks", "workshop"]:
			var type: BuildingType = hq.type.builds.filter(func(option: BuildingType) -> bool: return option.id.ends_with(kind))[0]
			var site := world.nearest_build_site(type, hq.cell)
			if site != SimWorld.NO_CELL and world.production.can_place(BLUE, type, site):
				world.add_building(type, BLUE, site)
				sites += 1
		check_eq(sites, 3, "there is explored building ground for a generator, a barracks and a workshop")
	check(not (load(HARVEST_TRIAL) as MissionDef).has_base(), "the harvest trial has no base")
	var plain := Mission.new(load(HARVEST_TRIAL))
	check_eq(plain.world.deposits[0].capacity, plain.world.deposits[0].cells.size() * 50, "and the usual rock")
	check(plain.world.production.keys(BLUE).is_empty(), "nothing can be built in it")
	check(Mission.new(load(MISSION_1)).world.production.keys(BLUE).is_empty(), "nor in Mission 1")


func test_base_trial_can_be_played_through() -> void:
	for path: String in BASES:
		var mission := Mission.new(load(path) as MissionDef)
		var world := mission.world
		var production := world.production
		var hq := world.get_building(mission.player_headquarters_id)
		world.order_harvest([world.units[0].id], world.deposits[0].cells[0])
		var built := 0
		for kind: String in ["generator", "barracks", "workshop"]:
			var type: BuildingType = hq.type.builds.filter(func(option: BuildingType) -> bool: return option.id.ends_with(kind))[0]
			production.queue(BLUE, BUILDINGS, type)
			for tick in 20 * 400:
				if production.ready_building(BLUE) == type:
					break
				mission.tick()
			if production.place(BLUE, world.nearest_build_site(type, hq.cell)) != null:
				built += 1
		check_eq(built, 3, "a generator, a barracks and a workshop are built in %s" % path)
		check(not world.is_low_power(BLUE), "with the generator there is power for them")
		var keys := production.keys(BLUE)
		check_eq(keys.size(), 3, "the barracks and the workshop each have a queue")
		for i in 3:
			production.queue(BLUE, keys[1], production.options(BLUE, keys[1])[0])
		production.queue(BLUE, keys[2], production.options(BLUE, keys[2])[0])
		for tick in 20 * 600:
			if world.team_size(BLUE) >= 5:
				break
			mission.tick()
		var soldiers := world.units.filter(func(unit: SimUnit) -> bool: return not unit.type.is_harvester()).size()
		check_eq([soldiers, world.team_size(BLUE) - soldiers], [3, 2], "three soldiers are trained and a second harvester is built")
		check(mission.seconds() < 600.0, "all within ten minutes (%d s)" % int(mission.seconds()))
		for tick in 20 * 60:
			mission.tick()
		check(world.units.all(func(unit: SimUnit) -> bool: return not unit.type.is_harvester() or unit.order == SimUnit.Order.HARVEST),
				"both harvesters are at work")
		check(not mission.is_over(), "a practice mission has no end")


# --- on screen -----------------------------------------------------------------------

func _view(path: String) -> MapView:
	MapView.requested_mission = path
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	return view


func _click(view: MapView, map_point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = map_point - view.camera.position
	view._unhandled_input(event)
	if button == MOUSE_BUTTON_LEFT:
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.pressed = false
		release.position = event.position
		view._unhandled_input(release)


func _steps(view: MapView, done: Callable, seconds := 60.0) -> bool:
	for i in roundi(seconds * 20):
		if done.call():
			return true
		view._process(0.05)
	return done.call()


func test_title_screen_offers_the_base_trial() -> void:
	var title := load("res://scripts/ui/title_screen.gd")
	check_eq(title.map_from_args(PackedStringArray(["--map=base-forest"])), "base-forest", "--map=base-forest")
	check_eq(title.map_from_args(PackedStringArray(["--map=base-desert"])), "base-desert", "--map=base-desert")
	check((load(title.MISSIONS["base-forest"]) as MissionDef).has_base(), "it starts the base trial")
	var node := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(node)
	check(node.get_node_or_null("Center/Box/Bases/BaseForest") != null, "there is a button for the forest base")
	check(node.get_node_or_null("Center/Box/Bases/BaseDesert") != null, "and one for the desert base")
	node.free()


func test_build_menu_texts() -> void:
	var generator := _type("generator")
	check_eq(BuildPanel.cell_text(generator), "Generator\n150", "a grid cell shows name and cost")
	check_eq(BuildPanel.cell_text(_unit("infantry")), "Guardsman\n60", "for units too")
	var line := BuildLine.new()
	check_eq(BuildPanel.queue_title(line), "Nothing in the queue", "an empty queue says so")
	check_eq(BuildPanel.queue_status(line, false), "", "and has no status")
	line.items.append(generator)
	line.progress = 40
	check_eq(BuildPanel.queue_title(line), "Generator", "the queue names what is being built")
	check_eq(BuildPanel.queue_status(line, false), "25%", "and how far it is")
	check(BuildPanel.queue_status(line, true).contains("low power"), "with a warning when power is low")
	line.items.append(_type("barracks"))
	line.items.append(_type("barracks"))
	check_eq(BuildPanel.queue_title(line), "Generator  (+2)", "and counts what waits behind it")
	line.waiting = Waiting.PLACE
	check(BuildPanel.queue_status(line, false).begins_with("Ready"), "a finished building is ready")
	var world := _world()
	check_eq(BuildPanel.tab_name(world, BLUE, BUILDINGS), "Build", "the buildings tab is called Build")
	_build(world, "barracks", Vector2i(3, 1))
	check_eq(BuildPanel.tab_name(world, BLUE, &"blue_barracks"), "Barracks", "a production building's tab has its name")
	check(MapView.describe_building(world, world.buildings[0]).contains("Makes 30 power"), "the sidebar says what a building makes")
	check(MapView.describe_building(world, world.buildings[0]).contains("Constructs buildings"), "and that the headquarters constructs")
	check(MapView.describe_building(world, world.buildings[1]).contains("Uses 20 power"), "what a building uses")
	check(MapView.describe_building(world, world.buildings[1]).contains("Produces: Guardsman"), "and what it produces")


func test_scene_shows_the_build_menu_only_with_a_base() -> void:
	var view := _view(HARVEST_TRIAL)
	check(not view.hud.build_panel.visible, "the harvest trial has no build menu")
	check(view._help.visible, "and keeps the list of controls")
	check(view.hud._objective.visible, "and its objective")
	view.free()
	view = _view(BASES[0])
	check(view.hud.build_panel.visible, "the base trial has the build menu")
	check(not view._help.visible and not view.hud._objective.visible, "in place of the controls and the objective")
	check(view.hud._top_right.text.contains("Orichalcum 500 / 1000"), "the top bar shows the store: '%s'" % view.hud._top_right.text)
	check(view.hud._top_right.text.contains("Power 30 / 30"), "and the power")
	view.free()


func test_building_from_the_build_menu() -> void:
	for path: String in BASES:
		var view := _view(path)
		var world := view.world
		var production := world.production
		var panel := view.hud.build_panel
		var hq := world.get_building(view.mission.player_headquarters_id)
		view._process(0.05)
		check_eq(panel.tab_keys(), [BUILDINGS] as Array[StringName], "the menu has one tab at first")
		check_eq(panel.items().size(), 4, "with four buildings")
		check_eq(panel._names[0].text, "Generator\n150", "the first is the generator")
		check(panel._icons[0].texture != null, "with its picture")
		check(not panel._cancel.visible and not panel._place.visible, "nothing is queued, so there is nothing to cancel or place")
		view.hints.note(&"harvest")
		check_eq(view.hints.current(), &"build", "the hints ask for a building")
		var generator: BuildingType = panel.items()[0]
		panel.build_pressed.emit(BUILDINGS, generator)
		check_eq(production.line(BLUE, BUILDINGS).current(), generator, "a click on the generator queues it")
		check_eq(view.hints.current(), &"place", "and the hints move on")
		view.begin_placement()
		check_eq(view.mode, MapView.Mode.NORMAL, "it cannot be placed before it is ready")
		check(view.hint_text().contains("No building is ready"), "and the hint box says so")
		check(_steps(view, func() -> bool: return production.ready_building(BLUE) == generator, 20.0), "it gets built")
		view._process(0.05)
		check(panel._place.visible and panel._place.text == "Place the Generator", "the menu offers to place it")
		check(panel._cancel.visible, "or to cancel it")
		check_eq(world.stored_for(BLUE), 350, "it has cost 150")
		panel.place_pressed.emit()
		check_eq(view.mode, MapView.Mode.PLACE, "a click on it starts placing")
		check(view.hint_text().begins_with("Placing the Generator"), "the hint box says what the next click does")
		var site := world.nearest_build_site(generator, hq.cell)
		var middle := Vector2(site * 32) + Vector2(32, 32)
		check_eq(PlacementView.cell_for(generator, middle), site, "the building's middle goes under the mouse")
		view.camera.center_on(middle)
		view.placement_view.show_at(world, generator, middle)
		check(view.placement_view.visible and view.placement_view.cell == site, "the preview shows where it would stand")
		# A click on the headquarters does not place it; a right click leaves placing.
		_click(view, hq.center() * 32.0)
		check_eq(world.buildings.size(), 2, "it cannot be put on another building")
		check(view.hint_text().contains("cannot stand there"), "and the hint box says why")
		check_eq(view.mode, MapView.Mode.PLACE, "placing goes on")
		_click(view, middle, MOUSE_BUTTON_RIGHT)
		check_eq(view.mode, MapView.Mode.NORMAL, "a right click stops placing")
		check(not view.placement_view.visible, "and hides the preview")
		check_eq(production.ready_building(BLUE), generator, "the building stays ready")
		# Clicking the building in the grid while it is ready also starts placing it.
		panel.build_pressed.emit(BUILDINGS, generator)
		check_eq(view.mode, MapView.Mode.PLACE, "a click on the ready building in the grid places it too")
		check_eq(production.line(BLUE, BUILDINGS).items.size(), 1, "without queueing another")
		_click(view, middle)
		check_eq(world.buildings.size(), 3, "a left click on free building ground places it")
		check_eq(world.buildings[2].cell, site, "where the preview was")
		check_eq(view.mode, MapView.Mode.NORMAL, "and placing is over")
		check_eq(view.hints.current(), &"train", "the hints move on to production")
		check(BuildingsView.building_at_point(world, middle, BLUE) == world.buildings[2], "the new building is on the map")
		view._process(0.05)
		check(view.hud._top_right.text.contains("Power 30 / 130"), "the top bar shows the new power: '%s'" % view.hud._top_right.text)

		# A barracks gets a tab of its own, and its soldiers come out beside it.
		var barracks: BuildingType = panel.items()[2]
		panel.build_pressed.emit(BUILDINGS, barracks)
		panel.build_pressed.emit(BUILDINGS, generator)
		view._process(0.05)
		check_eq(panel._queue_title.text, "Barracks  (+1)", "the queue shows what is built and what waits")
		panel.cancel_pressed.emit(BUILDINGS)
		check_eq(production.line(BLUE, BUILDINGS).items.size(), 1, "cancel takes the last one out")
		check(_steps(view, func() -> bool: return production.ready_building(BLUE) == barracks, 20.0), "the barracks gets built")
		view.begin_placement()
		var place := world.nearest_build_site(barracks, hq.cell)
		check(view.place_at(Vector2(place * 32) + Vector2(32, 32)), "and placed")
		view._process(0.05)
		check_eq(panel.tab_keys().size(), 2, "the menu has a second tab")
		check_eq(panel._tabs[1].text, "Barracks", "named after the barracks")
		panel._on_tab(1)
		view._process(0.05)
		check_eq(panel.items().size(), 1, "it offers one kind of soldier")
		var units := world.team_size(BLUE)
		panel.build_pressed.emit(panel.key, panel.items()[0])
		check_eq(view.hints.current(), &"power", "training one finishes the hints")
		check(_steps(view, func() -> bool: return world.team_size(BLUE) == units + 1, 20.0), "the soldier is trained")
		var soldier: SimUnit = world.units[-1]
		check(world.buildings[3].is_beside(soldier.cell), "and stands beside the barracks")
		check(UnitsView.unit_at_point(world, UnitsView.feet_position(soldier) + UnitsView.BODY, BLUE) == soldier, "where it can be selected")
		view.free()


func test_esc_leaves_placing() -> void:
	var view := _view(BASES[0])
	var production := view.world.production
	var generator: BuildingType = production.options(BLUE, BUILDINGS)[0]
	view.queue_build(BUILDINGS, generator)
	_steps(view, func() -> bool: return production.ready_building(BLUE) == generator, 20.0)
	view.begin_placement()
	check_eq(view.mode, MapView.Mode.PLACE, "placing has started")
	view.cancel_build(BUILDINGS)
	check_eq(view.mode, MapView.Mode.NORMAL, "cancelling the building ends placing")
	check_eq(view.world.stored_for(BLUE), 500, "and gives the Orichalcum back")
	view.free()
