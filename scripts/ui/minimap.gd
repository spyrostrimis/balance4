class_name Minimap
extends Control
## The whole map at a glance, one colour per cell, with a frame showing what
## the camera sees. Click or drag on it to move the camera.

const BACKGROUND := Color(0.03, 0.035, 0.03)
const FRAME := Color(1, 1, 1, 0.9)

var _map: MapData
var _camera: MapCamera
var _texture: ImageTexture


func setup(map: MapData, camera: MapCamera) -> void:
	if _camera != null and _camera.view_changed.is_connected(queue_redraw):
		_camera.view_changed.disconnect(queue_redraw)
	_map = map
	_camera = camera
	_texture = ImageTexture.create_from_image(build_image(map))
	_camera.view_changed.connect(queue_redraw)
	queue_redraw()


## One pixel per cell, in each terrain's minimap colour.
static func build_image(map: MapData) -> Image:
	var size := map.get_size()
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			image.set_pixel(x, y, map.terrain_at(Vector2i(x, y)).minimap_color)
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _map == null:
		return
	draw_texture_rect(_texture, fit_rect(_map.get_size(), size), false)
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
