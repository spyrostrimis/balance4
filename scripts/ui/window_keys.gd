class_name WindowKeys
extends Node
## Always loaded (an autoload): F11 or Alt+Enter switches between full screen
## and a window, on every screen of the game.
##
## The game draws at 960x540 and is scaled up by whole steps only, so pixels
## stay sharp. A 1920x1080 monitor fits exactly 2x in full screen, but a
## window loses some height to its title bar and the taskbar and drops to 1x.
## That is why the game starts in full screen, unless the player chose a
## window last time.


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## Switch, and remember the choice in the settings (see GameSettings).
func toggle_fullscreen() -> void:
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings != null:
		settings.set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)


## The largest whole multiple of the game's size that fits on the screen with
## room for a title bar.
static func windowed_size(usable: Vector2, base: Vector2) -> Vector2i:
	const TITLE_BAR := 40.0
	var scale := maxi(1, floori(minf(usable.x / base.x, (usable.y - TITLE_BAR) / base.y)))
	return Vector2i(base * scale)
