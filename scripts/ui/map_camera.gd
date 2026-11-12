class_name MapCamera
extends Camera2D
## The camera over the map. Its position is the top-left corner of what is
## shown, in map pixels. It scrolls with the arrow keys and when the mouse
## touches a screen edge, and it never shows anything outside the map.

signal view_changed

## Scroll speed in map pixels per second.
@export var scroll_speed := 480.0
## How close to a screen edge (in pixels) the mouse must be to scroll.
@export var edge_margin := 2.0

## Size of the map in pixels.
var map_size := Vector2.ZERO
## Size of the part of the screen that shows the map (the screen minus the sidebar).
var view_size := Vector2.ZERO
## Size of the whole screen, for edge scrolling.
var screen_size := Vector2.ZERO

var _top_left := Vector2.ZERO
var _mouse_seen := false
var _mouse_inside := true


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


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_seen = true
		_mouse_inside = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_mouse_inside = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		_mouse_inside = true


func _process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction == Vector2.ZERO and _mouse_seen and _mouse_inside:
		direction = edge_direction(get_viewport().get_mouse_position(), screen_size, edge_margin).normalized()
	if direction != Vector2.ZERO:
		set_top_left(_top_left + direction * scroll_speed * delta)
