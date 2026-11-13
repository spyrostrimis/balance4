class_name UnitsView
extends Node2D
## Draws the units of a SimWorld: sprites, selection rings, health bars, the
## marks left by hits, heals and deaths, and the markers that show where an
## order was given. Also answers "which unit is under this point" and "which
## units are in this box".

const CELL := MapData.CELL_SIZE
## Where a unit's feet are inside its cell, in pixels from the cell's top-left.
const FEET := Vector2(16, 19)
## Centre of a unit's body, relative to its feet. Used for clicking and box selection.
const BODY := Vector2(0, -6)
## A click this close to a unit's body (in pixels) selects it.
const PICK_RADIUS := 9.0
const RING := Color(1, 1, 1, 0.95)
const HEALTH_BACK := Color(0.07, 0.07, 0.06)
const HEALTH_FULL := Color(0.36, 0.72, 0.3)
const HEALTH_LOW := Color(0.85, 0.3, 0.2)
const MOVE_MARK := Color(0.75, 1.0, 0.7)
const ATTACK_MARK := Color(1.0, 0.45, 0.35)
const HIT_SPARK := Color(1.0, 0.94, 0.7)
const HEAL_GLOW := Color(0.6, 1.0, 0.75)
const HERO_MARK := Color(0.95, 0.78, 0.3)
const HURT_TINT := Color(1.0, 0.5, 0.45)
const MARKER_SECONDS := 0.45
## How many ticks each walking pose is shown.
const STEP_TICKS := 4
## For how many ticks after a hit the attacker leans into it and the victim flashes.
const LUNGE_TICKS := 3
const HURT_TICKS := 2
## How long the marks of a hit, a heal and a death stay, in ticks.
const HIT_TICKS := 4
const HEAL_TICKS := 14
const DEATH_TICKS := 18
## One pixel step for each facing, 0 south to 7 south-east.
const FACING_STEP: Array[Vector2] = [
	Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1),
	Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
]

var world: SimWorld
var selection: Selection
## Team whose shroud decides which units are visible.
var viewer_team := SimWorld.PLAYER_TEAM
## How far we are between the last simulation tick and the next, 0 to 1.
var alpha := 0.0

var _markers: Array = []      # [position, seconds left, colour, unit id or 0]


func setup(p_world: SimWorld, p_selection: Selection) -> void:
	world = p_world
	selection = p_selection
	_markers.clear()
	queue_redraw()


## Where a unit's feet are on the map, in pixels.
static func feet_position(unit: SimUnit, p_alpha := 0.0) -> Vector2:
	return (unit.visual_cell(p_alpha) * CELL + FEET).round()


## The unit of a team whose body is nearest to a point on the map, within clicking distance. Null if none.
static func unit_at_point(p_world: SimWorld, point: Vector2, team: int, p_alpha := 0.0) -> SimUnit:
	var best: SimUnit = null
	var best_distance := PICK_RADIUS
	for unit in p_world.units:
		if unit.team != team or unit.dead:
			continue
		var distance := (feet_position(unit, p_alpha) + BODY).distance_to(point)
		if distance <= best_distance:
			best = unit
			best_distance = distance
	return best


## The unit of any other team that `viewer_team` can see and whose body is
## nearest to a point on the map, within clicking distance. Null if none.
static func enemy_at_point(p_world: SimWorld, point: Vector2, p_viewer_team: int, p_alpha := 0.0) -> SimUnit:
	var best: SimUnit = null
	var best_distance := PICK_RADIUS
	for unit in p_world.units:
		if unit.team == p_viewer_team or unit.dead or not p_world.is_visible_to(unit, p_viewer_team):
			continue
		var distance := (feet_position(unit, p_alpha) + BODY).distance_to(point)
		if distance <= best_distance:
			best = unit
			best_distance = distance
	return best


## Ids of a team's units whose body is inside a rectangle on the map.
static func units_in_rect(p_world: SimWorld, rect: Rect2, team: int, p_alpha := 0.0) -> Array[int]:
	var out: Array[int] = []
	var box := rect.abs().grow(1.0)
	for unit in p_world.units:
		if unit.team == team and not unit.dead and box.has_point(feet_position(unit, p_alpha) + BODY):
			out.append(unit.id)
	return out


## Which sprite of the sheet shows a unit right now: (facing column, pose row).
static func sprite_frame(unit: SimUnit, tick: int) -> Vector2i:
	var pose := 0
	if unit.is_moving():
		pose = 1 + ((tick + unit.id * 3) / STEP_TICKS) % 2
	return Vector2i(unit.facing, pose)


## Should a unit's health bar be drawn? Always when selected, otherwise only when it is hurt.
static func shows_health(unit: SimUnit, chosen: bool) -> bool:
	return chosen or unit.health < unit.type.max_health


## Show a short-lived marker where a move order was given.
func add_move_marker(map_point: Vector2) -> void:
	_markers.append([map_point.round(), MARKER_SECONDS, MOVE_MARK, 0])


## Show a short-lived marker where an attack-move order was given.
func add_attack_move_marker(map_point: Vector2) -> void:
	_markers.append([map_point.round(), MARKER_SECONDS, ATTACK_MARK, 0])


## Show a short-lived marker on a unit that has been picked as a target (of an attack, or of an ability).
func add_target_marker(unit_id: int, friendly := false) -> void:
	_markers.append([Vector2.ZERO, MARKER_SECONDS, HEAL_GLOW if friendly else ATTACK_MARK, unit_id])


func _process(delta: float) -> void:
	for marker in _markers:
		marker[1] -= delta
	_markers = _markers.filter(func(m: Array) -> bool: return m[1] > 0.0)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for marker in _markers:
		var age: float = 1.0 - marker[1] / MARKER_SECONDS
		var colour: Color = marker[2]
		var at: Vector2 = marker[0]
		if marker[3] != 0:
			var marked := world.get_unit(marker[3])
			if marked == null:
				continue
			at = feet_position(marked, alpha)
		_draw_ring(at, Vector2(9, 5) * (1.0 - 0.6 * age), Color(colour, 1.0 - age))
	for effect in world.effects:
		if effect["kind"] == &"death":
			_draw_death(effect)
	var visible_units: Array[SimUnit] = []
	for unit in world.units:
		if not unit.dead and world.is_visible_to(unit, viewer_team):
			visible_units.append(unit)
	# Units further down the screen are drawn later, so they overlap the ones behind them.
	visible_units.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var ay := a.visual_cell(alpha).y
		var by := b.visual_cell(alpha).y
		return ay < by or (ay == by and a.id < b.id))
	for unit in visible_units:
		var feet := feet_position(unit, alpha)
		var chosen := selection != null and selection.has(unit.id)
		if chosen:
			_draw_ring(feet, Vector2(6, 3), RING)
		var type := unit.type
		var frame := sprite_frame(unit, world.tick_count)
		var source := Rect2(Vector2(frame * type.sprite_size), Vector2(type.sprite_size))
		var at := feet - Vector2(type.sprite_anchor)
		if world.tick_count - unit.last_attack_tick < LUNGE_TICKS:
			at += FACING_STEP[unit.facing] * 2.0        # lean into the blow
		var tint := HURT_TINT if world.tick_count - unit.last_hurt_tick < HURT_TICKS else Color.WHITE
		draw_texture_rect_region(type.sprites, Rect2(at, Vector2(type.sprite_size)), source, tint)
		if type.is_hero:
			_draw_hero_mark(feet + Vector2(0, -23))
		if shows_health(unit, chosen):
			_draw_health(feet + Vector2(-7, -19), float(unit.health) / type.max_health)
	var shroud := world.shroud_for(viewer_team)
	for effect in world.effects:
		var where := Vector2i((effect["to"] as Vector2).round())
		if effect["team"] != viewer_team and not shroud.is_explored(where):
			continue
		match effect["kind"]:
			&"hit": _draw_hit(effect)
			&"heal": _draw_heal(effect)


## Age of an effect in ticks, counting the part of a tick that has passed.
func _age(effect: Dictionary) -> float:
	return world.tick_count - int(effect["tick"]) + alpha


func _body_at(cell: Vector2) -> Vector2:
	return (cell * CELL + FEET + BODY).round()


func _draw_hit(effect: Dictionary) -> void:
	var age := _age(effect)
	if age >= HIT_TICKS:
		return
	var from := _body_at(effect["from"])
	var to := _body_at(effect["to"])
	var fade := 1.0 - age / HIT_TICKS
	if age < 2.0:
		draw_line(from.lerp(to, 0.35), to, Color(HIT_SPARK, 0.85), 1.0)
	var reach := 2.0 + age
	for step: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1).normalized(), Vector2(1, -1).normalized()]:
		draw_line(to - step * reach, to + step * reach, Color(HIT_SPARK, fade), 1.0)


func _draw_heal(effect: Dictionary) -> void:
	var age := _age(effect)
	if age >= HEAL_TICKS:
		return
	var from := _body_at(effect["from"])
	var to := _body_at(effect["to"])
	var fade := 1.0 - age / HEAL_TICKS
	if age < 5.0:
		draw_line(from, to, Color(HEAL_GLOW, 0.8 * (1.0 - age / 5.0)), 1.0)
	_draw_ring(to + Vector2(0, 6), Vector2(4, 2) + Vector2(6, 3) * (age / HEAL_TICKS), Color(HEAL_GLOW, fade))
	for i in 3:
		var plus := to + Vector2(-6 + i * 6, 2 - age * 1.2 - (i % 2) * 3)
		draw_line(plus + Vector2(-2, 0), plus + Vector2(3, 0), Color(HEAL_GLOW, fade), 1.0)
		draw_line(plus + Vector2(0, -2), plus + Vector2(0, 3), Color(HEAL_GLOW, fade), 1.0)


func _draw_death(effect: Dictionary) -> void:
	var age := _age(effect)
	if age >= DEATH_TICKS:
		return
	var where := Vector2i((effect["to"] as Vector2).round())
	if effect["team"] != viewer_team and not world.shroud_for(viewer_team).is_explored(where):
		return
	var feet := ((effect["to"] as Vector2) * CELL + FEET).round()
	var fade := 1.0 - age / DEATH_TICKS
	var points := PackedVector2Array()
	for i in 12:
		var angle := TAU * i / 12.0
		points.append(feet + Vector2(cos(angle) * 7.0, sin(angle) * 3.5))
	draw_colored_polygon(points, Color(0.12, 0.05, 0.04, 0.55 * fade))
	_draw_ring(feet, Vector2(7, 3.5) + Vector2(4, 2) * (age / DEATH_TICKS), Color(0.85, 0.3, 0.2, fade))


func _draw_ring(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 17:
		var angle := TAU * i / 16.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, color, 1.0)


func _draw_health(top_left: Vector2, share: float) -> void:
	draw_rect(Rect2(top_left - Vector2.ONE, Vector2(16, 4)), HEALTH_BACK)
	var width := maxf(1.0, roundf(14.0 * clampf(share, 0.0, 1.0)))
	draw_rect(Rect2(top_left, Vector2(width, 2)), HEALTH_FULL if share > 0.35 else HEALTH_LOW)


## A small gold chevron above a hero, so it can be found in a crowd.
func _draw_hero_mark(tip: Vector2) -> void:
	draw_polyline(PackedVector2Array([tip + Vector2(-3, -3), tip, tip + Vector2(3, -3)]), HERO_MARK, 1.0)
