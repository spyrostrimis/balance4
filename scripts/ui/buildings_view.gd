class_name BuildingsView
extends Node2D
## Draws the buildings of a SimWorld, each on its foundation, and answers
## "which building is under this point". Buildings are flat and are drawn
## under the units. A damaged building shows a health bar and smokes; one
## that is hit flashes; one that is destroyed goes up in an explosion and
## leaves a scorch mark on the ground for the rest of the mission.

const CELL := MapData.CELL_SIZE
const HURT_TINT := Color(1.0, 0.62, 0.55)
const HURT_TICKS := 2
const HEALTH_BACK := Color(0.07, 0.07, 0.06)
const HEALTH_FULL := Color(0.36, 0.72, 0.3)
const HEALTH_LOW := Color(0.85, 0.3, 0.2)
const FIRE := Color(1.0, 0.72, 0.3)
const FIRE_DEEP := Color(0.9, 0.32, 0.12)
const SMOKE := Color(0.3, 0.28, 0.25)
const SCORCH := Color(0.08, 0.06, 0.05, 0.55)
const TARGET_MARK := Color(1.0, 0.45, 0.35)
## How long an explosion lasts, in seconds, and a target marker.
const BLAST_SECONDS := 1.2
const MARK_SECONDS := 0.6
## A building below this share of its health smokes.
const SMOKE_BELOW := 0.5

var world: SimWorld
## Team whose shroud decides which buildings are visible.
var viewer_team := SimWorld.PLAYER_TEAM

## Destroyed buildings: [footprint rect in cells, seconds since]. They leave scorch marks.
var _ruins: Array = []
var _seen_wrecks := 0
## Building just picked as a target: [building id, seconds left].
var _mark := [0, 0.0]
var _clock := 0.0


func setup(p_world: SimWorld) -> void:
	world = p_world
	_ruins.clear()
	_seen_wrecks = world.wreck_log.size()
	_mark = [0, 0.0]
	queue_redraw()


## Where a building's picture is drawn, in map pixels.
static func picture_position(building: SimBuilding) -> Vector2:
	return Vector2(building.cell * CELL - building.type.sprite_origin)


## The building under a point on the map that `p_viewer_team` can see. Null if none.
static func building_at_point(p_world: SimWorld, point: Vector2, p_viewer_team: int) -> SimBuilding:
	var building := p_world.building_at(MapData.cell_at_pixel(point))
	if building == null or not p_world.is_building_visible_to(building, p_viewer_team):
		return null
	return building


## Should a building's health bar be drawn? Only when it is damaged.
static func shows_health(building: SimBuilding) -> bool:
	return building.health < building.type.max_health


## Briefly mark a building that has just been picked as a target.
func mark(building_id: int) -> void:
	_mark = [building_id, MARK_SECONDS]


## The scorch marks of destroyed buildings, as rectangles in cells.
func ruins() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for ruin: Array in _ruins:
		out.append(ruin[0])
	return out


func _process(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	_mark[1] = maxf(0.0, _mark[1] - delta)
	for ruin: Array in _ruins:
		ruin[1] += delta
	while _seen_wrecks < world.wreck_log.size():
		_ruins.append([world.wreck_log[_seen_wrecks], 0.0])
		_seen_wrecks += 1
	queue_redraw()      # the shroud may have lifted off one, and fires flicker


func _draw() -> void:
	if world == null:
		return
	var shroud := world.shroud_for(viewer_team)
	for ruin: Array in _ruins:
		var area: Rect2i = ruin[0]
		if shroud.is_explored(area.position):
			_draw_scorch(area)
	for building in world.buildings:
		if building.type.sprite == null or not world.is_building_visible_to(building, viewer_team):
			continue
		var tint := HURT_TINT if world.tick_count - building.last_hurt_tick < HURT_TICKS else Color.WHITE
		draw_texture(building.type.sprite, picture_position(building), tint)
	for building in world.buildings:
		if not world.is_building_visible_to(building, viewer_team):
			continue
		var share := float(building.health) / building.type.max_health
		if share < SMOKE_BELOW:
			_draw_fire(building, share)
		if shows_health(building):
			_draw_health(building, share)
		if _mark[1] > 0.0 and _mark[0] == building.id:
			var fade: float = _mark[1] / MARK_SECONDS
			draw_rect(Rect2(Vector2(building.cell * CELL), Vector2(building.type.footprint * CELL)).grow(2.0 + 4.0 * (1.0 - fade)),
					Color(TARGET_MARK, fade), false, 1.0)
	for ruin: Array in _ruins:
		if ruin[1] < BLAST_SECONDS and shroud.is_explored((ruin[0] as Rect2i).position):
			_draw_blast(ruin[0], ruin[1] / BLAST_SECONDS)


func _draw_health(building: SimBuilding, share: float) -> void:
	var width := float(building.type.footprint.x * CELL) - 16.0
	var top_left := Vector2(building.cell * CELL) + Vector2(8, -6)
	draw_rect(Rect2(top_left - Vector2.ONE, Vector2(width + 2, 5)), HEALTH_BACK)
	var filled := roundf(width * clampf(share, 0.0, 1.0))
	if filled > 0.0:
		draw_rect(Rect2(top_left, Vector2(maxf(filled, 1.0), 3)), HEALTH_FULL if share >= SMOKE_BELOW else HEALTH_LOW)


## Flames and a column of smoke over a badly damaged building: more of both the worse it is.
func _draw_fire(building: SimBuilding, share: float) -> void:
	var fires := 1 if share > 0.25 else 2
	for i in fires:
		var h := TerrainView.cell_hash(building.cell + Vector2i(i * 7, i * 3))
		var spot := Vector2(building.cell * CELL) + Vector2(12 + h % maxi(1, building.type.footprint.x * CELL - 24),
				14 + (h / 7) % maxi(1, building.type.footprint.y * CELL - 24))
		var beat := _clock * 7.0 + i * 1.7
		for k in 5:
			var rise := fmod(_clock * 0.7 + k * 0.2 + i * 0.13, 1.0)
			var puff := spot + Vector2(sin(beat * 0.25 + k) * 2.0 + rise * 8.0, -4.0 - rise * 30.0)
			draw_circle(puff, 3.0 + rise * 6.0, Color(SMOKE, 0.6 * (1.0 - rise)))
		var flick := 0.5 + 0.5 * sin(beat)
		var flick2 := 0.5 + 0.5 * sin(beat * 1.6 + 1.0)
		draw_circle(spot, 5.0 + flick, Color(FIRE_DEEP, 0.9))
		draw_circle(spot + Vector2(-2, -3), 3.5 + flick2, Color(FIRE_DEEP, 0.9))
		draw_circle(spot + Vector2(1, -2), 3.0 + flick, Color(FIRE, 0.95))
		draw_circle(spot + Vector2(0, -5 - flick2 * 2.0), 1.5 + flick2, Color(1.0, 0.93, 0.7, 0.95))


## The dark mark a destroyed building leaves: blotches over its footprint.
func _draw_scorch(area: Rect2i) -> void:
	for y in area.size.y:
		for x in area.size.x:
			var cell := area.position + Vector2i(x, y)
			if world.building_at(cell) != null:
				continue
			var h := TerrainView.cell_hash(cell)
			var middle := Vector2(cell * CELL) + Vector2(16, 16) + Vector2(h % 9 - 4, (h / 9) % 9 - 4)
			draw_circle(middle, 11.0 + h % 5, SCORCH)
			draw_circle(middle + Vector2((h / 81) % 11 - 5, (h / 7) % 11 - 5), 5.0, Color(SCORCH, 0.4))


## A building going up: a flash, a ring of fire and flying debris. `t` runs from 0 to 1.
func _draw_blast(area: Rect2i, t: float) -> void:
	var middle := (Vector2(area.position) + Vector2(area.size) / 2.0) * CELL
	var size := maxf(area.size.x, area.size.y) * CELL * 0.5
	var fade := 1.0 - t
	if t < 0.15:
		draw_circle(middle, size * (0.6 + t * 3.0), Color(1.0, 0.95, 0.75, 0.8 * (1.0 - t / 0.15)))
	draw_circle(middle, size * (0.3 + 0.7 * t), Color(FIRE_DEEP, 0.55 * fade))
	draw_circle(middle, size * (0.2 + 0.4 * t), Color(FIRE, 0.7 * fade))
	for i in 10:
		var h := TerrainView.cell_hash(area.position + Vector2i(i, i * 3))
		var angle := TAU * i / 10.0 + float(h % 100) / 100.0
		var fly := Vector2(cos(angle), sin(angle) * 0.7) * size * (0.3 + 1.1 * t) + Vector2(0, 30.0 * t * t - 18.0 * t)
		draw_rect(Rect2((middle + fly).round(), Vector2(2, 2)), Color(0.2, 0.17, 0.14, fade))
	for k in 3:
		var rise := t * (0.6 + k * 0.2)
		draw_circle(middle + Vector2(k * 6 - 6, -rise * size), size * 0.35 * (0.5 + t), Color(SMOKE, 0.45 * fade))
