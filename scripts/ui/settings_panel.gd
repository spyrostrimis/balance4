class_name SettingsPanel
extends Panel
## The settings, on a wooden board: the three volumes, the scroll speed and
## full screen. Every change takes effect and is saved at once (see
## GameSettings). Shown from the title screen and from the pause menu.

## Back was clicked (or Esc pressed).
signal closed

const SIZE := Vector2(380, 252)
const ROWS := [["master", "Master volume"], ["music", "Music volume"], ["effects", "Effects volume"]]

var _sliders := {}
var _values := {}
var _fullscreen: Button
var _back: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", HudStyle.style("wood_panel"))
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := HudStyle.label(self, Rect2(0, 12, SIZE.x, 34), &"serif_bold", 24, HudStyle.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Settings"
	var y := 58.0
	for row: Array in ROWS:
		_slider_row(row[0], row[1], y, 0.0, 1.0, 0.05)
		y += 30.0
	_slider_row("scroll", "Scroll speed", y, GameSettings.SCROLL_MIN, GameSettings.SCROLL_MAX, 0.1)
	y += 30.0
	var name_label := HudStyle.label(self, Rect2(24, y, 140, 22), &"serif_bold", 12, HudStyle.LIGHT, true)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text = "Full screen"
	_fullscreen = HudStyle.button(self, Rect2(176, y + 1, 80, 20), "navy", "", "", false, 10)
	_fullscreen.toggle_mode = true
	_fullscreen.toggled.connect(func(on: bool) -> void:
		_fullscreen.text = "On" if on else "Off"
		var settings := _settings()
		if settings != null and settings.fullscreen != on:
			settings.set_fullscreen(on))
	var hint := HudStyle.label(self, Rect2(264, y, 100, 22), &"sans", 9, HudStyle.LIGHT_DIM, true)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.text = "or F11"
	_back = HudStyle.button(self, Rect2((SIZE.x - 120) / 2.0, SIZE.y - 42, 120, 28), "navy", "Back", "", false, 11)
	_back.focus_mode = Control.FOCUS_ALL
	_back.pressed.connect(close)
	visibility_changed.connect(_on_shown)


func _slider_row(key: String, text: String, y: float, low: float, high: float, step: float) -> void:
	var name_label := HudStyle.label(self, Rect2(24, y, 140, 22), &"serif_bold", 12, HudStyle.LIGHT, true)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text = text
	var slider := HSlider.new()
	slider.position = Vector2(176, y + 3)
	slider.size = Vector2(130, 16)
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	_style_slider(slider)
	add_child(slider)
	var value := HudStyle.label(self, Rect2(312, y, 50, 22), &"sans_bold", 10, HudStyle.GOLD, true)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(_on_slider.bind(key))
	_sliders[key] = slider
	_values[key] = value


static func _style_slider(slider: HSlider) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = HudStyle.BAR_BACK
	groove.border_color = Color("8f6a22")
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("bb9234")
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", groove)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_icon_override("grabber", HudStyle.icon("gem"))
	slider.add_theme_icon_override("grabber_highlight", HudStyle.icon("gem"))
	slider.focus_mode = Control.FOCUS_NONE


func _settings() -> GameSettings:
	return get_node_or_null("/root/Settings") as GameSettings


## Show the current settings on the controls.
func _on_shown() -> void:
	if not visible:
		return
	var settings := _settings()
	if settings == null:
		return
	for key: String in ["master", "music", "effects"]:
		(_sliders[key] as HSlider).set_value_no_signal(settings.get(key))
		_show_value(key, settings.get(key))
	(_sliders["scroll"] as HSlider).set_value_no_signal(settings.scroll_speed)
	_show_value("scroll", settings.scroll_speed)
	_fullscreen.set_pressed_no_signal(settings.fullscreen)
	_fullscreen.text = "On" if settings.fullscreen else "Off"
	_back.grab_focus()


func _on_slider(value: float, key: String) -> void:
	var settings := _settings()
	if settings != null:
		if key == "scroll":
			settings.set_scroll_speed(value)
		else:
			settings.set_volume(key, value)
	_show_value(key, value)


func _show_value(key: String, value: float) -> void:
	(_values[key] as Label).text = "%.1fx" % value if key == "scroll" else "%d%%" % roundi(value * 100.0)


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
