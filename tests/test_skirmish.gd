extends TestCase
## Milestone M6: buildings that can be attacked and destroyed, the light
## tank, the computer opponent, and the skirmish against it.

const FOREST := "res://data/biomes/forest.tres"
const SKIRMISHES := ["res://data/missions/skirmish_blue.tres", "res://data/missions/skirmish_red.tres"]
const MAP_SCENE := "res://scenes/map_view.tscn"
const BLUE := 0
const RED := 1
const BUILDINGS := Production.BUILDINGS
## Stone for buildings at the left and at the right, grass between.
const FIELD := [
	"................................",
	".ssssss..................ssssss.",
	".ssssss..................ssssss.",
	".ssssss..................ssssss.",
	".ssssss..................ssssss.",
	".ssssss..................ssssss.",
	"................................",
	"................................",
]


func _type(kind: String, team := "blue") -> BuildingType:
	return load("res://data/buildings/%s_%s.tres" % [team, kind]) as BuildingType


func _unit(kind: String, team := "blue") -> UnitType:
	return load("res://data/units/%s_%s.tres" % [team, kind]) as UnitType


func _world() -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(FIELD)
	var world := SimWorld.new(map)
	for team in 2:
		world.shroud_for(team).reveal_circle(Vector2i(16, 4), 40)
	return world


func _run(world: SimWorld, seconds: float) -> void:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		world.tick()


## Run until `done` returns true. Returns false if it never did.
func _until(world: SimWorld, done: Callable, seconds := 120.0) -> bool:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		if done.call():
			return true
		world.tick()
	return done.call()


# --- buildings can be destroyed ------------------------------------------------------------

func test_buildings_have_health() -> void:
	for team: String in ["blue", "red"]:
		for kind: String in ["headquarters", "generator", "refinery", "barracks", "workshop"]:
			check(_type(kind, team).max_health > 0, "%s %s has health" % [team, kind])
		check(_type("headquarters", team).max_health > _type("generator", team).max_health, "the headquarters is the toughest")
	var world := _world()
	var barracks := world.add_building(_type("barracks", "red"), RED, Vector2i(26, 1))
	check_eq(barracks.health, barracks.type.max_health, "a new building is unharmed")
	check_eq(barracks.nearest_cell(Vector2i(20, 2)), Vector2i(26, 2), "its cell nearest to a point to its left")
	check_eq(barracks.nearest_cell(Vector2i(30, 9)), Vector2i(27, 2), "and to a point below and to its right")


func test_soldiers_destroy_a_building() -> void:
	var world := _world()
	var barracks := world.add_building(_type("barracks", "red"), RED, Vector2i(26, 1))
	var squad := world.add_group(_unit("infantry"), BLUE, Vector2i(14, 3), 3)
	var ids: Array[int] = []
	for unit in squad:
		ids.append(unit.id)
	world.order_attack(ids, barracks.id)
	for unit in squad:
		check_eq(unit.order, SimUnit.Order.ATTACK, "an order to attack a building is taken")
	check(_until(world, func() -> bool: return barracks.health < barracks.type.max_health, 20.0), "they walk up to it and hit it")
	check(_until(world, func() -> bool: return world.get_building(barracks.id) == null, 60.0), "until it is destroyed")
	check_eq(world.building_count(RED), 0, "Red has no building left")
	check_eq(int(world.buildings_lost.get(RED, 0)), 1, "and has lost one")
	check(world.building_at(Vector2i(26, 1)) == null, "its cells are empty")
	check(world.is_free(Vector2i(26, 1)), "and can be walked on")
	check(not world.terrain_path(Vector2i(20, 2), Vector2i(27, 2)).is_empty(), "units plan paths through them again")
	var wrecks := world.effects.filter(func(e: Dictionary) -> bool: return e["kind"] == &"wreck")
	check_eq(wrecks.size(), 1, "the UI is told it went up")
	_run(world, 2.0)
	for unit in squad:
		check_eq(unit.order, SimUnit.Order.NONE, "the attackers stand down when it is gone")


func test_harvesters_and_own_buildings_are_not_attacked() -> void:
	var world := _world()
	var own := world.add_building(_type("generator"), BLUE, Vector2i(1, 1))
	var enemy := world.add_building(_type("generator", "red"), RED, Vector2i(26, 1))
	var soldier := world.add_unit(_unit("infantry"), BLUE, Vector2i(8, 3))
	var harvester := world.add_unit(_unit("harvester"), BLUE, Vector2i(8, 5))
	world.order_attack([soldier.id], own.id)
	check_eq(soldier.order, SimUnit.Order.NONE, "a soldier will not attack its own side's building")
	world.order_attack([harvester.id], enemy.id)
	check(harvester.order != SimUnit.Order.ATTACK, "a harvester does not attack buildings")


func test_idle_units_attack_buildings_they_notice_but_units_come_first() -> void:
	var world := _world()
	var generator := world.add_building(_type("generator", "red"), RED, Vector2i(26, 1))
	var soldier := world.add_unit(_unit("infantry"), BLUE, Vector2i(23, 2))
	check(_until(world, func() -> bool: return generator.health < generator.type.max_health, 5.0),
			"an idle soldier attacks an enemy building within sight")
	check_eq(soldier.target_id, generator.id, "it is its target")
	var raider := world.add_unit(_unit("infantry", "red"), RED, Vector2i(22, 5))
	_run(world, 1.0)
	check_eq(soldier.target_id, raider.id, "an enemy soldier that comes near is fought first")
	check(_until(world, func() -> bool: return world.get_unit(raider.id) == null or world.get_unit(soldier.id) == null, 20.0), "one of them dies")


func test_attack_move_takes_out_buildings_on_the_way() -> void:
	var world := _world()
	var generator := world.add_building(_type("generator", "red"), RED, Vector2i(26, 1))
	var squad := world.add_group(_unit("infantry"), BLUE, Vector2i(10, 6), 4)
	var ids: Array[int] = []
	for unit in squad:
		ids.append(unit.id)
	world.order_attack_move(ids, Vector2i(29, 6))
	check(_until(world, func() -> bool: return world.get_building(generator.id) == null, 60.0),
			"troops on attack-move destroy an enemy building they pass")


func test_the_defenders_come_to_help_a_building() -> void:
	var world := _world()
	var barracks := world.add_building(_type("barracks", "red"), RED, Vector2i(26, 1))
	var guard := world.add_unit(_unit("infantry", "red"), RED, Vector2i(29, 6))
	world.add_unit(_unit("infantry"), BLUE, Vector2i(25, 3))
	check(_until(world, func() -> bool: return barracks.health < barracks.type.max_health, 5.0), "Blue hits the barracks")
	_run(world, 0.1)
	check(guard.target_id != 0 and world.get_unit(guard.target_id) != null, "the Red soldier nearby goes after the attacker")


func test_losing_a_building_empties_its_queue_and_its_storage() -> void:
	var world := _world()
	var hq := world.add_building(_type("headquarters"), BLUE, Vector2i(1, 1))
	var refinery := world.add_building(_type("refinery"), BLUE, Vector2i(3, 3))
	var barracks := world.add_building(_type("barracks"), BLUE, Vector2i(1, 3))
	world.stored[BLUE] = 500
	var production := world.production
	production.queue(BLUE, BUILDINGS, _type("generator"))
	production.queue(BLUE, BUILDINGS, _type("workshop"))
	production.queue(BLUE, &"blue_barracks", _unit("infantry"))
	_run(world, 2.0)
	var paid := production.line(BLUE, BUILDINGS).paid + production.line(BLUE, &"blue_barracks").paid
	check(paid > 0, "work has started and been paid for")
	var before := world.stored_for(BLUE)
	world.destroy_building(barracks)
	check(production.line(BLUE, &"blue_barracks").is_empty(), "the queue of a barracks that is gone is emptied")
	check(not production.keys(BLUE).has(&"blue_barracks"), "and is no longer offered")
	check_eq(production.line(BLUE, BUILDINGS).items.size(), 2, "the headquarters' queue goes on")
	world.destroy_building(hq)
	check(production.line(BLUE, BUILDINGS).is_empty(), "without a headquarters nothing more is constructed")
	check_eq(world.stored_for(BLUE), before + paid, "what was paid comes back")
	world.destroy_building(refinery)
	check_eq(world.storage_for(BLUE), 0, "with the refinery gone nothing can be stored")
	check_eq(world.stored_for(BLUE), 0, "and what was in store is lost")


# --- the light tank --------------------------------------------------------------------------

func test_the_light_tank() -> void:
	for team: String in ["blue", "red"]:
		var tank := _unit("tank", team)
		check(tank != null and tank.sprites != null, "%s has a light tank with a sprite sheet" % team)
		check_eq(tank.sprites.get_size(), Vector2(tank.sprite_size.x * 8, tank.sprite_size.y * 3), "8 facings by 3 poses")
		check(tank.attack_range > _unit("infantry", team).attack_range, "it hits from further away than a soldier")
		check(tank.max_health > _unit("infantry", team).max_health, "and takes more")
		check(tank.cost > 0 and not tank.is_harvester(), "it is for sale and is not a harvester")
	var world := _world()
	var tank := world.add_unit(_unit("tank"), BLUE, Vector2i(12, 3))
	var soldier := world.add_unit(_unit("infantry", "red"), RED, Vector2i(16, 3))
	world.order_stop([soldier.id])
	world.order_attack([tank.id], soldier.id)
	check(_until(world, func() -> bool: return soldier.health < soldier.type.max_health, 5.0), "it shoots")
	check(SimWorld._cells_apart(tank.cell, soldier.cell) > 1, "from a distance")


# --- the computer opponent -------------------------------------------------------------------

func test_building_roles() -> void:
	check_eq(ComputerOpponent.role_of(_type("headquarters")), &"headquarters", "headquarters")
	check_eq(ComputerOpponent.role_of(_type("generator")), &"power", "generator")
	check_eq(ComputerOpponent.role_of(_type("refinery")), &"refinery", "refinery")
	check_eq(ComputerOpponent.role_of(_type("barracks")), &"barracks", "barracks")
	check_eq(ComputerOpponent.role_of(_type("workshop", "red")), &"factory", "workshop")


func test_skirmish_start() -> void:
	for path: String in SKIRMISHES:
		var def := load(path) as MissionDef
		check(def.skirmish and def.has_base() and not def.practice, "%s is a skirmish with a base" % path)
		var mission := Mission.new(def)
		var world := mission.world
		check(mission.computer != null and mission.opponent == null, "the enemy is the computer, not the script")
		for team in 2:
			check_eq(world.building_count(team), 2, "side %d starts with a headquarters and a refinery" % team)
			check_eq(world.fighter_count(team), 3, "and three soldiers")
			check_eq(world.stored_for(team), 600, "and 600 Orichalcum")
			for building in world.buildings:
				if building.team == team:
					for cell in building.cells():
						check(world.map.is_buildable(cell), "its buildings stand on building ground")
		check(mission.enemy_headquarters_id != 0 and mission.enemy_refinery_id != 0, "the enemy's base is set up")
		var harvesters := 0
		for unit in world.units:
			if unit.type.is_harvester():
				harvesters += 1
		check_eq(harvesters, 2, "each side has a harvester")
		var deposit := world.deposits[0]
		check(world.shroud_for(RED).is_explored(deposit.cells[0]), "both sides know where the rock is")
		check(world.shroud_for(BLUE).is_explored(deposit.cells[0]), "both sides know where the rock is")
		check(not world.shroud_for(BLUE).is_explored(def.map.starts[1]), "but not where the other side is")


func test_the_computer_builds_harvests_and_trains() -> void:
	var mission := Mission.new(load(SKIRMISHES[0]))
	var world := mission.world
	var start_ore := world.ore_left()
	var roles := {}
	var placed_ok := true
	for i in 240 * SimWorld.TICKS_PER_SECOND:
		mission.tick()
		for building in world.buildings:
			if building.team == RED:
				roles[ComputerOpponent.role_of(building.type)] = true
				for cell in building.cells():
					placed_ok = placed_ok and world.map.is_buildable(cell) and world.shroud_for(RED).is_explored(cell)
	for role: StringName in [&"power", &"barracks", &"factory"]:
		check(roles.has(role), "within four minutes it has built a %s" % role)
	check(placed_ok, "everything it placed stands on building ground it has explored")
	check(world.power_made(RED) >= world.power_used(RED), "it keeps its power up")
	check(world.ore_left() < start_ore, "its harvester digs")
	check(world.fighter_count(RED) > 3, "it trains troops")
	var harvesters := 0
	for unit in world.units:
		if unit.team == RED and unit.type.is_harvester():
			harvesters += 1
	check(harvesters >= 2, "and a second harvester")


func test_the_computer_only_places_on_ground_it_has_explored() -> void:
	var world := _world()
	world.add_building(_type("headquarters", "red"), RED, Vector2i(26, 1))
	world.add_unit(_unit("infantry", "red"), RED, Vector2i(28, 6))
	var red_shroud := Shroud.new(world.size)
	world._shrouds[RED] = red_shroud     # Red has explored nothing at all
	var computer := ComputerOpponent.new(world, RED, BLUE, Vector2i(3, 3))
	check_eq(computer.find_site(_type("generator", "red")), SimWorld.NO_CELL, "with nothing explored there is nowhere to build")
	red_shroud.reveal_circle(Vector2i(27, 3), 6)
	var site := computer.find_site(_type("generator", "red"))
	check(site != SimWorld.NO_CELL and world.production.can_place(RED, _type("generator", "red"), site), "once explored it finds a site")


func test_the_computer_pays_like_the_player() -> void:
	var world := _world()
	world.add_building(_type("headquarters", "red"), RED, Vector2i(26, 1))
	world.add_unit(_unit("infantry", "red"), RED, Vector2i(28, 6))
	world.stored[RED] = 100
	var computer := ComputerOpponent.new(world, RED, BLUE, Vector2i(3, 3))
	for i in 30 * SimWorld.TICKS_PER_SECOND:
		computer.tick()
		world.tick()
	check_eq(world.stored_for(RED), 0, "it spends what it has")
	check_eq(world.building_count(RED), 1, "but with 100 it cannot finish a generator that costs 150")
	check_eq(world.production.line(RED, BUILDINGS).waiting, BuildLine.Waiting.FUNDS, "it waits for Orichalcum like anyone")


func test_the_computer_defends_its_base() -> void:
	var mission := Mission.new(load(SKIRMISHES[0]))
	var world := mission.world
	for i in 60 * SimWorld.TICKS_PER_SECOND:
		mission.tick()
	var hq := world.get_building(mission.enemy_headquarters_id)
	var spot := world.nearest_free_cell(hq.nearest_cell(world.map.starts[0]) + Vector2i(-4, 4), world.region_at(world.map.starts[0]))
	var intruder := world.add_unit(_unit("infantry"), BLUE, spot)
	check(intruder != null, "a Blue soldier turns up near Red's base")
	world.order_stop([intruder.id])
	check(mission.computer.threat() == intruder, "the computer sees the threat")
	var answered := false
	for i in 10 * SimWorld.TICKS_PER_SECOND:
		mission.tick()
		if world.get_unit(intruder.id) == null:
			answered = true
			break
	check(answered, "its soldiers come and kill the intruder")


func test_the_computer_beats_a_player_who_does_nothing() -> void:
	var mission := Mission.new(load(SKIRMISHES[0]))
	var attacked_tick := -1
	for i in 15 * 60 * SimWorld.TICKS_PER_SECOND:
		mission.tick()
		if attacked_tick < 0 and mission.computer.waves > 0:
			attacked_tick = mission.world.tick_count
		if mission.is_over():
			break
	check(attacked_tick >= roundi(ComputerOpponent.ATTACK_AFTER_SECONDS * SimWorld.TICKS_PER_SECOND),
			"it does not attack before %d seconds" % roundi(ComputerOpponent.ATTACK_AFTER_SECONDS))
	check(mission.is_over() and mission.winner == RED, "it wins within fifteen minutes")
	check_eq(mission.win_reason, &"eliminated", "by destroying everything")
	check(mission.is_beaten(BLUE), "Blue has no buildings and no troops left")


func test_two_computers_play_a_skirmish_to_the_end() -> void:
	for path: String in SKIRMISHES:
		var mission := Mission.new(load(path))
		var blue_side := ComputerOpponent.new(mission.world, BLUE, RED, mission.def.map.starts[1])
		for i in 40 * 60 * SimWorld.TICKS_PER_SECOND:
			blue_side.tick()
			mission.tick()
			if mission.is_over():
				break
		check(mission.is_over(), "%s: two computers finish a skirmish within forty minutes" % path)
		check(mission.world.buildings_lost.size() > 0, "buildings were destroyed on the way")


# --- winning and losing ------------------------------------------------------------------------

func _clear_side(world: SimWorld, team: int, keep_harvesters := false) -> void:
	for building in world.buildings.duplicate():
		if building.team == team:
			world.destroy_building(building)
	for unit in world.units:
		if unit.team == team and not (keep_harvesters and unit.type.is_harvester()):
			unit.health = 0
			world._kill(unit)


func test_a_skirmish_is_won_by_destroying_everything() -> void:
	var mission := Mission.new(load(SKIRMISHES[0]))
	var world := mission.world
	mission.tick()
	check(not mission.is_over(), "it goes on while both sides have something")
	_clear_side(world, RED, true)
	mission.tick()
	check(mission.is_over() and mission.player_won(), "the player wins once every enemy building and soldier is gone, harvesters or not")
	check_eq(mission.win_reason, &"eliminated", "by elimination")
	mission = Mission.new(load(SKIRMISHES[1]))
	world = mission.world
	for building in world.buildings.duplicate():
		if building.team == BLUE:
			world.destroy_building(building)
	mission.tick()
	check(not mission.is_over(), "a side with troops but no buildings is not beaten yet")
	_clear_side(world, BLUE)
	mission.tick()
	check(mission.is_over() and not mission.player_won(), "the player loses when nothing is left")


# --- on screen --------------------------------------------------------------------------------

func _view(path: String) -> MapView:
	MapView.requested_mission = path
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	return view


func test_skirmish_on_screen() -> void:
	var view := _view(SKIRMISHES[0])
	var mission := view.mission
	var world := view.world
	view._process(0.05)
	check(view.hud.build_panel.visible, "the skirmish has the build menu")
	check(view.hud._top_left.text.begins_with("Skirmish"), "the top bar says it is a skirmish: '%s'" % view.hud._top_left.text)
	check(view.hud._top_left.text.contains("Red 2 / 3"), "and counts their buildings and troops")
	check(view.hud.top_bar_text().contains("Orichalcum 600 / 1000"), "and shows the store")
	check(view.control_view.control == null, "there is no control area to hold")
	check(view.hint_text() != "", "a hint is shown")
	# Right-click an enemy building with soldiers selected: they attack it.
	var red_hq := world.get_building(mission.enemy_headquarters_id)
	world.shroud_for(BLUE).reveal_circle(red_hq.cell, 6)
	var soldiers: Array[int] = []
	for unit in world.units:
		if unit.team == BLUE and not unit.type.is_harvester():
			soldiers.append(unit.id)
	view.selection.set_ids(soldiers)
	view.order_at(red_hq.center() * MapData.CELL_SIZE)
	for id in soldiers:
		var unit := world.get_unit(id)
		check(unit.order == SimUnit.Order.ATTACK and unit.order_target == red_hq.id, "a right click on an enemy building attacks it")
	check(MapView.describe_building(world, red_hq).contains("Health 1200 / 1200"), "the sidebar shows a building's health")
	# A destroyed building leaves a scorch mark.
	world.destroy_building(red_hq)
	view._process(0.05)
	view.buildings_view._process(0.05)
	check_eq(view.buildings_view.ruins().size(), 1, "the destroyed building leaves a mark")
	check(view.hud._top_left.text.contains("Red 1 / 3"), "and is no longer counted")
	_clear_side(world, RED)
	view._process(0.05)
	check(view.hud.is_result_shown(), "the result is shown once Red is beaten")
	check(view.hud.result_text_shown().contains("Every enemy building and soldier is destroyed"), "with how it was won")
	check(view.hud.result_text_shown().contains("2 buildings"), "and how many buildings were destroyed")
	view.free()


func test_title_screen_offers_the_skirmish() -> void:
	var title := load("res://scripts/ui/title_screen.gd")
	check_eq(title.map_from_args(PackedStringArray(["--map=skirmish-forest"])), "skirmish-forest", "--map=skirmish-forest")
	check_eq(title.map_from_args(PackedStringArray(["--map=skirmish-desert"])), "skirmish-desert", "--map=skirmish-desert")
	check((load(title.MISSIONS["skirmish-desert"]) as MissionDef).skirmish, "it starts a skirmish")
	var node := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(node)
	check(node.get_node_or_null("Center/Box/Skirmishes/SkirmishForest") != null, "there is a button for the forest skirmish")
	check(node.get_node_or_null("Center/Box/Skirmishes/SkirmishDesert") != null, "and one for the desert skirmish")
	node.free()
