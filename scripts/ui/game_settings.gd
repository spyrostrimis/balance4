class_name GameSettings
extends Node
## The player's settings: the master, music and effects volumes, how fast the
## map scrolls, and full screen or a window. Loaded as the autoload
## "Settings"; kept in user://settings.cfg between runs. The volumes drive the
## audio buses Master, Music and Effects (default_bus_layout.tres).

const PATH := "user://settings.cfg"
const BUSES := {"master": "Master", "music": "Music", "effects": "Effects"}
## How fast the map scrolls at 1.0, in map pixels per second.
const BASE_SCROLL_SPEED := 480.0
const SCROLL_MIN := 0.5
const SCROLL_MAX := 2.0

## Volumes from 0 (silent) to 1.
var master := 0.8
var music := 0.7
var effects := 0.8
## Scroll speed as a share of BASE_SCROLL_SPEED, SCROLL_MIN to SCROLL_MAX.
var scroll_speed := 1.0
var fullscreen := true
## Where the settings are kept; tests use another file.
var path := PATH


func _ready() -> void:
	load_settings()
	apply()


## Read the settings file, keeping the defaults for anything missing.
func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	master = clampf(float(file.get_value("audio", "master", master)), 0.0, 1.0)
	music = clampf(float(file.get_value("audio", "music", music)), 0.0, 1.0)
	effects = clampf(float(file.get_value("audio", "effects", effects)), 0.0, 1.0)
	scroll_speed = clampf(float(file.get_value("controls", "scroll_speed", scroll_speed)), SCROLL_MIN, SCROLL_MAX)
	fullscreen = bool(file.get_value("display", "fullscreen", fullscreen))


func save_settings() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "master", master)
	file.set_value("audio", "music", music)
	file.set_value("audio", "effects", effects)
	file.set_value("controls", "scroll_speed", scroll_speed)
	file.set_value("display", "fullscreen", fullscreen)
	file.save(path)


## Put every setting into effect.
func apply() -> void:
	for key: String in BUSES:
		apply_volume(key)
	apply_window()


## The settings as they are when nothing has been changed.
func use_defaults() -> void:
	var fresh := GameSettings.new()
	master = fresh.master
	music = fresh.music
	effects = fresh.effects
	scroll_speed = fresh.scroll_speed
	fullscreen = fresh.fullscreen
	fresh.free()


## Change a volume ("master", "music" or "effects"), put it into effect and save.
func set_volume(key: String, value: float) -> void:
	set(key, clampf(value, 0.0, 1.0))
	apply_volume(key)
	save_settings()


func set_scroll_speed(value: float) -> void:
	scroll_speed = clampf(value, SCROLL_MIN, SCROLL_MAX)
	save_settings()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_window()
	save_settings()


## The map's scroll speed in map pixels per second.
func scroll_pixels_per_second() -> float:
	return BASE_SCROLL_SPEED * scroll_speed


func apply_volume(key: String) -> void:
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus < 0:
		return
	var value: float = get(key)
	AudioServer.set_bus_mute(bus, value <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.001)))


## Full screen, or the largest window that fits (see WindowKeys).
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen == is_full:
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable := DisplayServer.screen_get_usable_rect()
	var size := WindowKeys.windowed_size(Vector2(usable.size), Vector2(960, 540))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
