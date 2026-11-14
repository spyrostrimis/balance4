class_name BuildingsView
extends Node2D
## Draws the buildings of a SimWorld, each on its foundation, and answers
## "which building is under this point". Buildings are flat and are drawn
## under the units.

const CELL := MapData.CELL_SIZE

var world: SimWorld
## Team whose shroud decides which buildings are visible.
var viewer_team := SimWorld.PLAYER_TEAM


func setup(p_world: SimWorld) -> void:
	world = p_world
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


func _process(_delta: float) -> void:
	if world != null and not world.buildings.is_empty():
		queue_redraw()      # the shroud may have lifted off one


func _draw() -> void:
	if world == null:
		return
	for building in world.buildings:
		if building.type.sprite != null and world.is_building_visible_to(building, viewer_team):
			draw_texture(building.type.sprite, picture_position(building))
