class_name PlacementView
extends Node2D
## Shows where a finished building would stand while the player is choosing
## the place: the building's picture, faint, and a green or red square on
## every cell it would cover.

const CELL := MapData.CELL_SIZE
const GOOD := Color(0.4, 0.9, 0.4, 0.38)
const BAD := Color(0.95, 0.25, 0.2, 0.45)

var world: SimWorld
var team := SimWorld.PLAYER_TEAM
## The building being placed, or null when nothing is.
var type: BuildingType
## The top-left cell it would cover.
var cell := Vector2i.ZERO


## The top-left cell of a building whose middle is put under a point on the map.
static func cell_for(p_type: BuildingType, map_point: Vector2) -> Vector2i:
	var corner := map_point - Vector2(p_type.footprint - Vector2i.ONE) * CELL / 2.0
	return MapData.cell_at_pixel(corner)


## Can one cell of the footprint be built on by a team?
static func cell_ok(p_world: SimWorld, p_team: int, covered: Vector2i) -> bool:
	return p_world.can_build_on(covered) and p_world.shroud_for(p_team).is_explored(covered)


func show_at(p_world: SimWorld, p_type: BuildingType, map_point: Vector2) -> void:
	world = p_world
	type = p_type
	cell = cell_for(p_type, map_point)
	visible = true
	queue_redraw()


func stop() -> void:
	type = null
	visible = false
	queue_redraw()


func _draw() -> void:
	if world == null or type == null:
		return
	var fits := world.production.can_place(team, type, cell)
	if type.sprite != null:
		draw_texture(type.sprite, Vector2(cell * CELL - type.sprite_origin), Color(1, 1, 1, 0.75 if fits else 0.35))
	for y in type.footprint.y:
		for x in type.footprint.x:
			var covered := cell + Vector2i(x, y)
			draw_rect(Rect2(Vector2(covered * CELL), Vector2(CELL, CELL)), GOOD if cell_ok(world, team, covered) else BAD)
