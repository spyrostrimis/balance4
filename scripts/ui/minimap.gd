class_name Minimap
extends Control
## The whole map at a glance, one colour per cell, with a frame showing what
## the camera sees. Unexplored cells are black; units are coloured dots.
## Click or drag on it to move the camera.

const BACKGROUND := Color(0.03, 0.035, 0.03)
const UNEXPLORED := Color(0.027, 0.031, 0.027)
const FRAME := Color(1, 1, 1, 0.9)

var _map: MapData
var _camera: MapCamera
var _world: SimWorld
var _team := SimWorld.PLAYER_TEAM
var _texture: ImageTexture
var _shroud_version := -1


## world is optional: without it the minimap shows the bare map.
func setup(map: MapData, camera: MapCamera, world: SimWorld = null, team := SimWorld.PLAYER_TEAM) -> void:
	if _camera != null and _camera.view_changed.is_connected(queue_redraw):
		_camera.view_changed.disconnect(queue_redraw)
	_map = map
	_camera = camera
	_world = world
	_team = team
	_texture = null
	_refresh_texture()
	_camera.view_changed.connect(queue_redraw)
	queue_redraw()


## One pixel per cell, in each terrain's minimap colour; black where the shroud (if given) still covers it.
static func build_image(map: MapData, shroud: Shroud = null) -> Image:
	var size := map.get_size()
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if shroud != null and not shroud.is_explored(cell):
				image.set_pixel(x, y, UNEXPLORED)
			else:
				image.set_pixel(x, y, map.terrain_at(cell).minimap_color)
	return image


## Where the map is drawn inside a box: as large as fits, at a whole number of
## pixels per cell when the box allows it, centred.
static func fit_rect(map_cells: Vector2i, box: Vector2) -> Rect2:
	if map_cells.x <= 0 or map_cells.y <= 0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var scale := minf(box.x / map_cells.x, box.y / map_cells.y)
	if scale >= 1.0:
		scale = floorf(scale)
	var size := Vector2(map_cells) * scale
	return Rect2(((box - size) / 2.0).floor(), size)


## Point on the map (in map pixels) under a point of this control.
func local_to_map(local: Vector2) -> Vector2:
	var rect := fit_rect(_map.get_size(), size)
	return (local - rect.position) / rect.size * Vector2(_map.get_pixel_size())


## Point of this control over a point on the map (in map pixels).
func map_to_local(map_point: Vector2) -> Vector2:
	var rect := fit_rect(_map.get_size(), size)
	return rect.position + map_point / Vector2(_map.get_pixel_size()) * rect.size


func _refresh_texture() -> void:
	var shroud: Shroud = _world.shroud_for(_team) if _world != null else null
	var version := shroud.version if shroud != null else 0
	if _texture != null and version == _shroud_version:
		return
	_shroud_version = version
	var image := build_image(_map, shroud)
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)


func _process(_delta: float) -> void:
	if _world != null:
		_refresh_texture()
		queue_redraw()      # units move


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _map == null:
		return
	var rect := fit_rect(_map.get_size(), size)
	draw_texture_rect(_texture, rect, false)
	if _world != null:
		var cell_size := rect.size / Vector2(_map.get_size())
		var shroud := _world.shroud_for(_team)
		for unit in _world.units:
			if unit.team != _team and not shroud.is_explored(unit.cell):
				continue
			var dot := rect.position + Vector2(unit.cell) * cell_size
			draw_rect(Rect2(dot, cell_size.max(Vector2(2, 2))), unit.type.minimap_color)
	var view := _camera.get_view_rect()
	var top_left := map_to_local(view.position).round()
	var bottom_right := map_to_local(view.end).round()
	draw_rect(Rect2(top_left + Vector2(0.5, 0.5), bottom_right - top_left - Vector2.ONE), FRAME, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if _map == null:
		return
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	var pressed := button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed
	var dragged := motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if pressed or dragged:
		_camera.center_on(local_to_map((event as InputEventMouse).position))
		accept_event()
