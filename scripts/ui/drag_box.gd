class_name DragBox
extends Control
## The rectangle drawn while the player drags to select units. Screen pixels.

const LINE := Color(1, 1, 1, 0.9)
const FILL := Color(1, 1, 1, 0.08)

var _rect := Rect2()
var _shown := false


func show_rect(rect: Rect2) -> void:
	_rect = rect.abs()
	_shown = true
	queue_redraw()


func hide_rect() -> void:
	if _shown:
		_shown = false
		queue_redraw()


func _draw() -> void:
	if not _shown or _rect.size.x < 1.0 or _rect.size.y < 1.0:
		return
	var box := Rect2(_rect.position.round(), _rect.size.round())
	draw_rect(box, FILL)
	draw_rect(Rect2(box.position + Vector2(0.5, 0.5), box.size - Vector2.ONE), LINE, false, 1.0)
