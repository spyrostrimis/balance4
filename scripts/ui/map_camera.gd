class_name MapCamera
extends Camera2D
## The camera over the map. Its position is the top-left corner of what is
## shown, in map pixels. It scrolls with WASD or the arrow keys, when the
## mouse is near a screen edge, and by dragging the map with the middle mouse
## button held down. It never shows anything outside the map.

signal view_changed

## Scroll speed in map pixels per second.
@export var scroll_speed := 480.0
## How close to a screen edge (in pixels) the mouse must be to scroll.
@export var edge_margin := 8.0

## Size of the map in pixels.
var map_size := Vector2.ZERO
## Size of the part of the screen that shows the map (the screen minus the sidebar).
var view_size := Vector2.ZERO
## Size of the whole screen, for edge scrolling.
var screen_size := Vector2.ZERO

var _top_left := Vector2.ZERO
var _mouse_seen := false
var _mouse_inside := true
## Is the map being dragged with the middle mouse button?
var _panning := false
var _pan_start_mouse := Vector2.ZERO
var _pan_start_top_left := Vector2.ZERO


func _init() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT


func setup(p_map_size: Vector2, p_view_size: Vector2, p_screen_size: Vector2) -> void:
	map_size = p_map_size
	view_size = p_view_size
	screen_size = p_screen_size
	set_top_left(_top_left)


## The part of the map on screen, in map pixels.
func get_view_rect() -> Rect2:
	return Rect2(position, view_size)


func set_top_left(top_left: Vector2) -> void:
	_top_left = clamp_top_left(top_left, map_size, view_size)
	var snapped_position := _top_left.round()
	if snapped_position != position:
		position = snapped_position
	view_changed.emit()


## Move so that a point on the map is in the middle of the view (or as close as the map edge allows).
func center_on(map_point: Vector2) -> void:
	set_top_left(map_point - view_size / 2.0)


## Keep the view inside the map. A map smaller than the view sits at the top-left.
static func clamp_top_left(top_left: Vector2, p_map_size: Vector2, p_view_size: Vector2) -> Vector2:
	var limit := (p_map_size - p_view_size).max(Vector2.ZERO)
	return top_left.clamp(Vector2.ZERO, limit)


## Scroll direction for a mouse position: -1, 0 or 1 on each axis.
static func edge_direction(mouse: Vector2, p_screen_size: Vector2, margin: float) -> Vector2:
	var direction := Vector2.ZERO
	if mouse.x <= margin:
		direction.x = -1.0
	elif mouse.x >= p_screen_size.x - 1.0 - margin:
		direction.x = 1.0
	if mouse.y <= margin:
		direction.y = -1.0
	elif mouse.y >= p_screen_size.y - 1.0 - margin:
		direction.y = 1.0
	return direction


## Where the view's top-left corner goes while the map is dragged: the map
## follows the mouse, so the spot that was grabbed stays under it.
static func pan_top_left(start_top_left: Vector2, start_mouse: Vector2, mouse: Vector2) -> Vector2:
	return start_top_left - (mouse - start_mouse)


## Scroll direction from WASD and the arrow keys: -1, 0 or 1 on each axis.
## WASD go by key position, so they sit under the same fingers on any keyboard layout.
static func key_direction() -> Vector2:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT):
		return direction     # Ctrl and Alt combinations are not scrolling
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.y += 1.0
	return direction.clamp(-Vector2.ONE, Vector2.ONE)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_seen = true
		_mouse_inside = true
		if _panning:
			set_top_left(pan_top_left(_pan_start_top_left, _pan_start_mouse, event.position))
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_MIDDLE and not button.pressed:
		_panning = false


## The middle button pressed on the map (not on the sidebar, which takes its own clicks) starts dragging it.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_MIDDLE and button.pressed:
		_panning = true
		_pan_start_mouse = button.position
		_pan_start_top_left = _top_left


## Is the map being dragged with the middle mouse button?
func is_panning() -> bool:
	return _panning


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_mouse_inside = false
		_panning = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		_mouse_inside = true


func _process(delta: float) -> void:
	if _panning:
		return
	var direction := key_direction().normalized()
	if direction == Vector2.ZERO and _mouse_seen and _mouse_inside:
		direction = edge_direction(get_viewport().get_mouse_position(), screen_size, edge_margin).normalized()
	if direction != Vector2.ZERO:
		set_top_left(_top_left + direction * scroll_speed * delta)
