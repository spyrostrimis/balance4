extends TestCase
## Combat in the simulation: attack values, picking targets, the orders, death,
## and the commander's ability.

const FOREST := "res://data/biomes/forest.tres"
const GUARD := "res://data/units/blue_infantry.tres"
const LEGIONARY := "res://data/units/red_infantry.tres"
const COMMANDERS := ["res://data/units/blue_commander.tres", "res://data/units/red_commander.tres"]
const BLUE := 0
const RED := 1


func _open(width: int, height: int) -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	var rows := []
	for y in height:
		rows.append(".".repeat(width))
	map.rows = PackedStringArray(rows)
	return SimWorld.new(map)


## A unit type made for one test. damage 0 gives a unit that never attacks.
func _type(health: int, damage: int, reach := 1, interval := 1.0, acquire := 4) -> UnitType:
	var type := UnitType.new()
	type.max_health = health
	type.attack_damage = damage
	type.attack_range = reach
	type.attack_interval = interval
	type.acquire_range = acquire
	return type


func _ticks(world: SimWorld, count: int) -> void:
	for i in count:
		world.tick()


## Run until `done` returns true. Returns false if it never did.
func _until(world: SimWorld, done: Callable, max_ticks := 2000) -> bool:
	for i in max_ticks:
		if done.call():
			return true
		world.tick()
	return done.call()


func test_unit_types_have_combat_values() -> void:
	for path in [GUARD, LEGIONARY] + COMMANDERS:
		var type := load(path) as UnitType
		check(type != null, "%s loads" % path)
		if type == null:
			continue
		check(type.attack_damage > 0 and type.attack_range >= 1 and type.attack_interval > 0.0, "%s can attack" % path)
		check(type.acquire_range >= type.attack_range, "%s notices enemies at least as far as it can hit" % path)
		check(type.acquire_range <= type.sight, "%s does not notice enemies it cannot see" % path)
		check_eq(type.sprites.get_size(), Vector2(8 * type.sprite_size.x, 3 * type.sprite_size.y), "%s sprite sheet" % path)
	check(not (load(GUARD) as UnitType).is_hero, "a Guardsman is not a hero")
	for path in COMMANDERS:
		var type := load(path) as UnitType
		check(type.is_hero, "%s is a hero" % path)
		check(type.ability != null and type.ability.kind == Ability.Kind.HEAL_TARGET, "%s has the heal ability" % path)
		check(type.ability.amount > 0 and type.ability.cooldown > 0.0 and type.ability.cast_range >= 1, "its ability has values")
		check(type.max_health > (load(GUARD) as UnitType).max_health, "a commander is tougher than a soldier")


func test_range_is_round() -> void:
	check(SimWorld.in_range(Vector2i(3, 3), Vector2i(4, 4), 1), "range 1 reaches a diagonal neighbour")
	check(not SimWorld.in_range(Vector2i(3, 3), Vector2i(5, 3), 1), "but not two cells away")
	check(SimWorld.in_range(Vector2i(0, 0), Vector2i(2, 1), 2), "range 2 reaches (2, 1)")
	check(not SimWorld.in_range(Vector2i(0, 0), Vector2i(2, 2), 2), "but not (2, 2)")


func test_facing_toward() -> void:
	check_eq(SimWorld.facing_toward(Vector2i(0, 5)), 0, "south")
	check_eq(SimWorld.facing_toward(Vector2i(-3, 0)), 2, "west")
	check_eq(SimWorld.facing_toward(Vector2i(0, -1)), 4, "north")
	check_eq(SimWorld.facing_toward(Vector2i(4, 0)), 6, "east")
	check_eq(SimWorld.facing_toward(Vector2i(3, 3)), 7, "south-east")
	check_eq(SimWorld.facing_toward(Vector2i(-2, -2)), 3, "north-west")
	check_eq(SimWorld.facing_toward(Vector2i(5, 1)), 6, "mostly east counts as east")


func test_attack_takes_health_at_a_steady_pace() -> void:
	var world := _open(8, 5)
	var attacker := world.add_unit(_type(100, 10), BLUE, Vector2i(2, 2))
	var dummy := world.add_unit(_type(1000, 0), RED, Vector2i(3, 1))
	_ticks(world, 1)
	check_eq(dummy.health, 990, "the first hit lands at once")
	check_eq(attacker.facing, 5, "the attacker faces its target (north-east)")
	check_eq(attacker.last_attack_tick, 1, "the hit is recorded for drawing")
	check_eq(dummy.last_hurt_tick, 1, "and so is the hurt")
	_ticks(world, 99)
	check_eq(dummy.health, 950, "one hit a second: five hits in 100 ticks")
	check_eq(attacker.health, 100, "a unit with no attack does no harm")
	check(attacker.is_settled(), "the attacker stands still while it fights")
	var hits := world.effects.filter(func(e: Dictionary) -> bool: return e["kind"] == &"hit")
	check(not hits.is_empty(), "recent hits are listed for the UI")
	_ticks(world, 60)
	check(world.effects.all(func(e: Dictionary) -> bool: return world.tick_count - int(e["tick"]) <= SimWorld.EFFECT_TICKS),
			"old effects are dropped")


func test_idle_units_fight_enemies_that_come_near() -> void:
	var world := _open(12, 6)
	var blue := world.add_unit(load(GUARD), BLUE, Vector2i(2, 2))
	var red := world.add_unit(load(LEGIONARY), RED, Vector2i(5, 2))
	check(_until(world, func() -> bool: return world.units.size() == 1), "two soldiers in sight of each other fight to the death")
	var survivor: SimUnit = world.units[0]
	var loser := red if survivor == blue else blue
	check(survivor.health < survivor.type.max_health, "the survivor was hurt too")
	check(loser.dead and loser.health == 0, "the loser is dead")
	check(world.get_unit(loser.id) == null, "it can no longer be found by id")
	check(world.unit_at(loser.cell) == null and world.is_free(loser.cell), "its cell is free again")
	check_eq(world.team_size(loser.team), 0, "its team has nobody left")
	check_eq(world.losses.get(loser.team, 0), 1, "the loss is counted")
	check_eq(world.removed_count, 1, "one unit removed")
	check(SimWorld.in_range(survivor.cell, loser.cell, 1), "they fought next to each other")


func test_enemies_out_of_sight_are_left_alone() -> void:
	var world := _open(16, 4)
	var blue := world.add_unit(load(GUARD), BLUE, Vector2i(1, 1))
	var red := world.add_unit(load(LEGIONARY), RED, Vector2i(12, 1))
	_ticks(world, 200)
	check_eq(blue.cell, Vector2i(1, 1), "blue stays put")
	check_eq(red.cell, Vector2i(12, 1), "red stays put")
	check(blue.health == 60 and red.health == 60, "nobody is hurt")


func test_attack_order_sticks_to_its_target() -> void:
	var world := _open(14, 7)
	var hero := world.add_unit(_type(1000, 30), BLUE, Vector2i(1, 3))
	var near := world.add_unit(_type(300, 1), RED, Vector2i(5, 3))
	var far := world.add_unit(_type(90, 1), RED, Vector2i(10, 3))
	world.order_attack([hero.id], far.id)
	check_eq(hero.order, SimUnit.Order.ATTACK, "the order is recorded")
	check(_until(world, func() -> bool: return far.dead), "the target is hunted down and killed")
	check_eq(near.health, 300, "the enemy passed on the way was left alone")
	check(hero.health < 1000, "although it hit back")
	world.tick()
	check_eq(hero.order, SimUnit.Order.NONE, "the order ends when the target is dead")
	check(_until(world, func() -> bool: return near.dead), "then the unit fights the enemy next to it on its own")

	# An attack order on nothing, or for a unit that cannot attack, does nothing.
	var dummy := world.add_unit(_type(50, 0), BLUE, Vector2i(1, 1))
	var other := world.add_unit(_type(50, 0), RED, Vector2i(12, 6))
	world.order_attack([dummy.id], other.id)
	check_eq(dummy.order, SimUnit.Order.NONE, "a unit with no attack ignores an attack order")
	world.order_attack([hero.id], 9999)
	check_eq(hero.order, SimUnit.Order.NONE, "an attack order on a unit that does not exist is ignored")


func test_move_order_ignores_enemies() -> void:
	var world := _open(14, 5)
	var blue := world.add_unit(load(GUARD), BLUE, Vector2i(1, 2))
	var dummy := world.add_unit(_type(40, 0), RED, Vector2i(6, 1))
	world.order_move([blue.id], Vector2i(12, 2))
	check(_until(world, func() -> bool: return blue.is_settled() and blue.order == SimUnit.Order.NONE), "the walk ends")
	check_eq(blue.cell, Vector2i(12, 2), "the unit arrived")
	check_eq(dummy.health, 40, "and did not touch the enemy it passed")


func test_attack_move_fights_on_the_way_and_carries_on() -> void:
	var world := _open(14, 5)
	var blue := world.add_unit(load(GUARD), BLUE, Vector2i(1, 2))
	var dummy := world.add_unit(_type(40, 0), RED, Vector2i(6, 1))
	world.order_attack_move([blue.id], Vector2i(12, 2))
	check_eq(blue.order, SimUnit.Order.ATTACK_MOVE, "the order is recorded")
	check(_until(world, func() -> bool: return dummy.dead), "the enemy met on the way is killed")
	check(blue.cell != Vector2i(12, 2), "before the unit reaches its destination")
	check(_until(world, func() -> bool: return blue.is_settled() and blue.order == SimUnit.Order.NONE), "the walk ends")
	check_eq(blue.cell, Vector2i(12, 2), "then the unit carries on to where it was sent")


func test_units_fight_back() -> void:
	var world := _open(14, 5)
	var archer := world.add_unit(_type(500, 5, 6, 1.0, 6), RED, Vector2i(10, 2))
	var victim := world.add_unit(_type(500, 20, 1, 1.0, 2), BLUE, Vector2i(4, 2))
	world.tick()
	check_eq(victim.health, 495, "the long-range unit hits from six cells away")
	check_eq(victim.target_id, archer.id, "the victim turns on its attacker, though it is too far to notice otherwise")
	check(_until(world, func() -> bool: return archer.health < 500, 400), "it walks over and hits back")


func test_idle_units_help_a_comrade_under_attack() -> void:
	var world := _open(20, 5)
	var brute := world.add_unit(_type(1000, 1, 1, 1.0, 1), RED, Vector2i(6, 2))
	var victim := world.add_unit(_type(500, 10, 1, 1.0, 2), BLUE, Vector2i(5, 2))
	var helper := world.add_unit(_type(500, 10, 1, 1.0, 2), BLUE, Vector2i(2, 2))
	var walker := world.add_unit(_type(500, 10, 1, 1.0, 2), BLUE, Vector2i(3, 4))
	var far := world.add_unit(_type(500, 10, 1, 1.0, 2), BLUE, Vector2i(14, 2))
	world.order_move([walker.id], Vector2i(0, 4))
	world.tick()
	check_eq(helper.target_id, brute.id, "an idle unit near a comrade that is hit goes for the attacker")
	check_eq(walker.target_id, 0, "a unit that was told to move does not")
	check_eq(far.target_id, 0, "nor does a unit too far away")
	_ticks(world, 100)
	check(SimWorld.in_range(helper.cell, brute.cell, 1), "the helper walks up to the attacker")
	check(brute.health < 1000 - 5 * 10, "and hits it as well")
	check_eq(far.cell, Vector2i(14, 2), "the far unit has not moved")


func test_a_unit_told_to_move_does_not_turn_round() -> void:
	var world := _open(14, 5)
	var archer := world.add_unit(_type(500, 5, 6, 1.0, 6), RED, Vector2i(10, 2))
	var runner := world.add_unit(_type(500, 20, 1, 1.0, 2), BLUE, Vector2i(6, 2))
	world.order_move([runner.id], Vector2i(0, 2))
	check(_until(world, func() -> bool: return runner.is_settled() and runner.order == SimUnit.Order.NONE, 400), "the walk ends")
	check_eq(runner.cell, Vector2i(0, 2), "the unit went where it was told")
	check(runner.health < 500, "although it was shot at on the way")
	check_eq(archer.health, 500, "and it did not hit back while walking")


func test_stop_order() -> void:
	var world := _open(14, 5)
	var blue := world.add_unit(load(GUARD), BLUE, Vector2i(1, 2))
	world.order_attack_move([blue.id], Vector2i(12, 2))
	_ticks(world, 20)
	world.order_stop([blue.id])
	_ticks(world, 20)
	check(blue.is_settled(), "a stopped unit stands still")
	check_eq(blue.order, SimUnit.Order.NONE, "and has no order")
	check(blue.cell.x < 12, "short of where it was going")


func test_a_dead_unit_frees_its_cell_and_the_selection() -> void:
	var world := _open(8, 4)
	var killer := world.add_unit(_type(100, 500), RED, Vector2i(2, 1))
	var victim := world.add_unit(load(GUARD), BLUE, Vector2i(3, 1))
	var friend := world.add_unit(load(GUARD), BLUE, Vector2i(7, 3))
	var selection := Selection.new()
	selection.set_ids([victim.id, friend.id])
	selection.assign_group(1)
	world.tick()
	check(victim.dead, "one hit kills")
	check(not world.units.has(victim), "the dead unit is gone from the world")
	check_eq(world.units.size(), 2, "the others are still there")
	check(world.effects.any(func(e: Dictionary) -> bool: return e["kind"] == &"death" and e["team"] == BLUE), "the death is listed for the UI")
	selection.prune(world)
	check_eq(selection.ids, [friend.id] as Array[int], "the selection forgets the dead unit")
	check(selection.groups[1].size() == 1 and selection.groups[1][0] == friend.id, "and so does the control group")
	# Orders that name the dead unit are harmless.
	world.order_move([victim.id], Vector2i(0, 0))
	world.order_attack([friend.id], victim.id)
	check_eq(friend.order, SimUnit.Order.NONE, "nothing can be sent after a dead unit")
	# The cell can be used again.
	check(world.add_unit(load(GUARD), BLUE, Vector2i(3, 1)) != null, "another unit can stand where it died")


func test_fights_never_put_two_units_in_one_cell() -> void:
	var world := _open(16, 10)
	for i in 5:
		world.add_unit(load(GUARD), BLUE, Vector2i(2, 2 + i))
		world.add_unit(load(LEGIONARY), RED, Vector2i(13, 2 + i))
	var blue_ids: Array = []
	var red_ids: Array = []
	for unit in world.units:
		(blue_ids if unit.team == BLUE else red_ids).append(unit.id)
	world.order_attack_move(blue_ids, Vector2i(13, 4))
	world.order_attack_move(red_ids, Vector2i(2, 4))
	for tick in 3000:
		var cells := {}
		for unit in world.units:
			check(not cells.has(unit.cell), "two units share cell %s at tick %d" % [unit.cell, tick])
			check(world.unit_at(unit.cell) == unit, "cell %s does not point back at its unit" % unit.cell)
			cells[unit.cell] = true
		if world.team_size(BLUE) == 0 or world.team_size(RED) == 0:
			break
		world.tick()
	check(world.team_size(BLUE) == 0 or world.team_size(RED) == 0, "a five-a-side battle ends with one side dead")
	check(world.team_size(BLUE) + world.team_size(RED) > 0, "and somebody is left standing")


func test_commander_heals_one_unit() -> void:
	var world := _open(16, 5)
	var commander := world.add_unit(load(COMMANDERS[0]), BLUE, Vector2i(1, 2))
	var guard := world.add_unit(load(GUARD), BLUE, Vector2i(10, 2))
	var ability := commander.type.ability
	check_eq(world.ability_problem(commander.id, guard.id), "That unit is not wounded", "a healthy unit cannot be healed")
	check(not world.order_ability(commander.id, guard.id), "so the order is refused")
	guard.health = 5
	check_eq(world.ability_problem(commander.id, guard.id), "", "a wounded one can")
	check(world.order_ability(commander.id, guard.id), "the order is accepted")
	check_eq(commander.order, SimUnit.Order.ABILITY, "and recorded")
	check(_until(world, func() -> bool: return guard.health > 5, 400), "the commander walks over and heals")
	check_eq(guard.health, 5 + ability.amount, "by the ability's amount")
	check(SimWorld.in_range(commander.cell, guard.cell, ability.cast_range), "from within the ability's range")
	check(not SimWorld.in_range(commander.cell, guard.cell, 1), "without walking all the way up")
	check_eq(commander.order, SimUnit.Order.NONE, "the order is finished")
	check(world.effects.any(func(e: Dictionary) -> bool: return e["kind"] == &"heal"), "the heal is listed for the UI")
	check_eq(commander.ability_ticks_left, ability.cooldown_ticks(), "the ability starts to recharge")
	check(world.ability_problem(commander.id, guard.id).contains("not ready"), "it cannot be used again at once")
	check(not world.order_ability(commander.id, guard.id), "so a second order is refused")
	_ticks(world, ability.cooldown_ticks())
	check_eq(commander.ability_ticks_left, 0, "after the cooldown it is ready")
	check(world.order_ability(commander.id, guard.id), "and can be used again")
	_ticks(world, 5)
	check_eq(guard.health, guard.type.max_health, "healing never goes above full health")


func test_ability_targets() -> void:
	var world := _open(12, 5)
	var commander := world.add_unit(load(COMMANDERS[0]), BLUE, Vector2i(1, 2))
	var enemy := world.add_unit(_type(50, 0), RED, Vector2i(9, 2))
	var guard := world.add_unit(load(GUARD), BLUE, Vector2i(2, 2))
	commander.health = 10
	enemy.health = 10
	check(world.ability_problem(commander.id, commander.id) != "", "the commander cannot heal itself")
	check(world.ability_problem(commander.id, enemy.id) != "", "nor an enemy")
	check(world.ability_problem(guard.id, commander.id) != "", "a soldier has no ability")
	check(world.ability_problem(commander.id, 9999) != "", "nor can a unit that does not exist be healed")
	check(not world.order_ability(commander.id, enemy.id), "such orders are refused")
	check_eq(commander.order, SimUnit.Order.NONE, "and change nothing")
