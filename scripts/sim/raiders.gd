class_name Raiders
extends RefCounted
## The enemy of a practice mission with a raid in it. Like ScriptedOpponent it
## is a short script, not a real opponent: after a delay its units go for the
## other side's harvesters, fighting whatever they meet on the way, and once a
## harvester is destroyed they walk up to the trailer it left behind and take
## the Orichalcum in it.

## How often it looks at its units, in ticks.
const THINK_TICKS := 20

var world: SimWorld
var team := 1
var delay_ticks := 0


func _init(p_world: SimWorld, p_team: int, delay_seconds: float) -> void:
	world = p_world
	team = p_team
	delay_ticks = roundi(delay_seconds * SimWorld.TICKS_PER_SECOND)


func tick() -> void:
	if world.tick_count < delay_ticks or (world.tick_count - delay_ticks) % THINK_TICKS != 0:
		return
	for unit in world.units:
		if unit.team != team or unit.dead or unit.order != SimUnit.Order.NONE or unit.target_id != 0:
			continue
		var loot := _nearest_orphan(unit.cell)
		if loot != null:
			world.order_move([unit.id], loot.cell)      # it stops beside the trailer and takes what is in it
			continue
		var prey := _nearest_harvester(unit.cell)
		if prey != null and not SimWorld.in_range(unit.cell, prey.cell, unit.type.acquire_range):
			world.order_attack_move([unit.id], prey.cell)


func _nearest_orphan(from: Vector2i) -> SimTrailer:
	var best: SimTrailer = null
	for trailer in world.trailers:
		if not trailer.is_orphan() or trailer.team == team:
			continue
		if best == null or (trailer.cell - from).length_squared() < (best.cell - from).length_squared():
			best = trailer
	return best


func _nearest_harvester(from: Vector2i) -> SimUnit:
	var best: SimUnit = null
	for other in world.units:
		if other.team == team or other.dead or not other.type.is_harvester():
			continue
		if best == null or (other.cell - from).length_squared() < (best.cell - from).length_squared():
			best = other
	return best
