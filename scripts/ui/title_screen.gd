extends Control
## Placeholder title screen. It exists so the project has something to run
## and will be replaced by the real menu later.

const MILESTONE := "M0 Setup"

@onready var _status: Label = $Center/Box/Status


func _ready() -> void:
	var version: String = Engine.get_version_info()["string"]
	_status.text = "%s  |  placeholder title screen  |  Godot %s" % [MILESTONE, version]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
