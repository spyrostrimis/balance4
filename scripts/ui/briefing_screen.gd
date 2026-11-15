class_name BriefingScreen
extends Control
## The briefing before a story mission: its name and side, the story (the
## mission's `briefing`), the objectives the player starts with, and a
## picture of the map with where the player starts. Begin (or Enter) starts
## the mission; Back (or Esc) goes back to the title screen. It briefs
## MapView.requested_mission and builds its own controls.

const SCENE := "res://scenes/briefing.tscn"
const MAP_SCENE := "res://scenes/map_view.tscn"
const TITLE_SCENE := "res://scenes/main.tscn"
const DOSSIER := Rect2(24, 24, 540, 492)
const PICTURE := Rect2(584, 24, 352, 278)

var def: MissionDef
var _begin: Button


## Brief a mission (a MissionDef file): change to the briefing scene.
static func open(tree: SceneTree, mission_path: String) -> void:
	MapView.requested_mission = mission_path
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	def = load(MapView.requested_mission) as MissionDef
	HudStyle.panel(self, Rect2(-8, -8, 976, 556), "wood_panel")
	if def == null:
		push_error("Could not load mission: %s" % MapView.requested_mission)
		return
	_build_dossier()
	_build_picture()
	var keys := HudStyle.label(self, Rect2(PICTURE.position.x, 444, PICTURE.size.x, 16), &"sans", 9, HudStyle.LIGHT_DIM, true)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.text = "Enter: begin    Esc: back"
	var back := HudStyle.button(self, Rect2(PICTURE.position.x, 466, 140, 40), "wood", "Back", "", false, 13)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(go_back)
	_begin = HudStyle.button(self, Rect2(PICTURE.end.x - 196, 466, 196, 40), "navy", "Begin the mission", "", false, 13)
	_begin.focus_mode = Control.FOCUS_ALL
	_begin.pressed.connect(begin)
	_begin.grab_focus()


func _build_dossier() -> void:
	var paper := HudStyle.panel(self, DOSSIER, "parchment")
	var heading := HudStyle.label(paper, Rect2(20, 12, 500, 16), &"serif_italic", 12, HudStyle.INK_DIM)
	heading.text = "Mission %d  -  %s  -  %s" % [def.number, def.player_side, def.map.display_name]
	var title := HudStyle.label(paper, Rect2(20, 28, 500, 34), &"serif_bold", 26, HudStyle.INK)
	title.text = def.display_name
	_rule(paper, 66.0)
	var story := HudStyle.label(paper, Rect2(20, 76, 500, 290), &"serif", 12, HudStyle.INK)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.text = def.briefing if def.briefing != "" else "No briefing has been written for this mission."
	var y := 372.0
	_rule(paper, y)
	var objectives_title := HudStyle.label(paper, Rect2(20, y + 6, 300, 18), &"serif_bold", 13, HudStyle.INK)
	objectives_title.text = "Objectives"
	y += 28.0
	for line in objective_lines(def):
		var mark := MissionHud.ObjectiveMark.new()
		mark.position = Vector2(20, y + 3)
		mark.size = Vector2(11, 11)
		paper.add_child(mark)
		var row := HudStyle.label(paper, Rect2(38, y, 482, 16), &"serif_bold", 11, HudStyle.INK)
		row.text = line
		row.clip_text = true
		y += 19.0


func _build_picture() -> void:
	var frame := HudStyle.panel(self, PICTURE, "inset")
	var image := Minimap.build_image(def.map)
	var scale := floorf(minf((PICTURE.size.x - 16) / image.get_width(), (PICTURE.size.y - 16) / image.get_height()))
	var picture_size := Vector2(image.get_width(), image.get_height()) * scale
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(image)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.position = ((PICTURE.size - picture_size) / 2.0).floor()
	picture.size = picture_size
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	var marker := StartMarker.new()
	marker.color = def.player_color
	marker.position = picture.position + (Vector2(start_cell(def)) + Vector2(0.5, 0.5)) * scale - Vector2(12, 12)
	marker.size = Vector2(24, 24)
	frame.add_child(marker)
	var caption := HudStyle.label(self, Rect2(PICTURE.position.x, PICTURE.end.y + 8, PICTURE.size.x, 18),
			&"serif_bold", 13, HudStyle.LIGHT, true)
	caption.text = def.map.display_name
	var note := HudStyle.label(self, Rect2(PICTURE.position.x, PICTURE.end.y + 28, PICTURE.size.x, 40),
			&"serif_italic", 11, HudStyle.LIGHT_DIM, true)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "You start at the %s mark. The rest of the map is unknown until your troops see it." % def.player_side.to_lower()


func _rule(parent: Control, y: float) -> void:
	var rule := ColorRect.new()
	rule.color = Color("a88a5a")
	rule.position = Vector2(20, y)
	rule.size = Vector2(500, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


## The objectives the player is given at the start (not the hidden ones).
static func objective_lines(mission_def: MissionDef) -> PackedStringArray:
	var lines := PackedStringArray()
	for objective in mission_def.objectives:
		if not objective.hidden:
			lines.append(objective.text + ("" if objective.primary else " (optional)"))
	return lines


## Where the player's side starts on the map.
static func start_cell(mission_def: MissionDef) -> Vector2i:
	var starts := mission_def.map.starts
	var index := mission_def.sides[0].start if not mission_def.sides.is_empty() else 0
	return starts[index] if index < starts.size() else Vector2i.ZERO


func begin() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


func go_back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()


## A ring in the side's colour where the player starts.
class StartMarker extends Control:
	var color := Color.WHITE
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var middle := size / 2.0
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		draw_arc(middle, 7.0 + pulse * 4.0, 0, TAU, 24, Color(color, 0.9 - pulse * 0.5), 2.0)
		draw_circle(middle, 3.5, Color.BLACK)
		draw_circle(middle, 2.5, color.lightened(0.3))
