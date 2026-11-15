class_name BuildPanel
extends Control
## The build menu in the sidebar: one tab for buildings and one for each kind
## of production building the player owns, a grid of what the open tab can
## build, the tab's build queue, and the power bar. It builds its own
## controls and only reports clicks; MapView gives the orders. Like the rest
## of the HUD it is functional only; its art will be redone later.

## The player clicked something to build: the queue's key and the item.
signal build_pressed(key: StringName, item: Resource)
## The player clicked Cancel on the open tab's queue.
signal cancel_pressed(key: StringName)
## The player clicked the finished building to place it.
signal place_pressed

const GOLD := Color(0.91, 0.72, 0.29)
const TEXT := Color(0.78, 0.76, 0.68)
const DIM := Color(0.5, 0.52, 0.47)
const BAR_BACK := Color(0.16, 0.15, 0.13)
const POWER_OK := Color(0.42, 0.7, 0.95)
const POWER_LOW := Color(0.85, 0.3, 0.2)
const WIDTH := 192.0
## How many things one tab can offer: three across, two down.
const GRID := Vector2i(3, 2)
const CELL := Vector2(62, 50)
const GAP := 3.0

## The key of the open tab's queue.
var key := Production.BUILDINGS

var _tabs: Array[Button] = []
var _tab_keys: Array[StringName] = []
var _cells: Array[Button] = []
var _icons: Array[TextureRect] = []
var _names: Array[Label] = []
var _items: Array[Resource] = []
var _queue_title: Label
var _queue_bar: ColorRect
var _queue_status: Label
var _place: Button
var _cancel: Button
var _power_text: Label
var _power_bar: ColorRect
var _icon_cache := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(WIDTH, 222)
	for i in 3:
		var tab := _button(Rect2(i * 65, 0, 62, 18), "")
		tab.pressed.connect(_on_tab.bind(i))
		_tabs.append(tab)
	for i in GRID.x * GRID.y:
		var at := Vector2(i % GRID.x, i / GRID.x) * (CELL + Vector2(GAP, GAP)) + Vector2(0, 22)
		var cell := _button(Rect2(at, CELL), "")
		cell.pressed.connect(_on_cell.bind(i))
		var icon := TextureRect.new()
		icon.position = Vector2(2, 2)
		icon.size = Vector2(CELL.x - 4, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var label := _label(Rect2(0, 26, CELL.x, 24), 9, TEXT, cell)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("line_spacing", -3)
		_cells.append(cell)
		_icons.append(icon)
		_names.append(label)
	_queue_title = _label(Rect2(0, 130, WIDTH - 52, 14), 11, GOLD)
	_cancel = _button(Rect2(WIDTH - 50, 129, 50, 16), "Cancel")
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit(key))
	_rect(Rect2(0, 147, WIDTH, 8), BAR_BACK)
	_queue_bar = _rect(Rect2(1, 148, 0, 6), GOLD)
	_queue_status = _label(Rect2(0, 157, WIDTH, 14), 10, DIM)
	_place = _button(Rect2(0, 156, WIDTH, 18), "")
	_place.pressed.connect(func() -> void: place_pressed.emit())
	_power_text = _label(Rect2(0, 180, WIDTH, 14), 11, GOLD)
	_rect(Rect2(0, 196, WIDTH, 8), BAR_BACK)
	_power_bar = _rect(Rect2(1, 197, 0, 6), POWER_OK)


## The name on a queue's tab.
static func tab_name(world: SimWorld, team: int, tab_key: StringName) -> String:
	if tab_key == Production.BUILDINGS:
		return "Build"
	var maker := world.production.builder(team, tab_key)
	return maker.type.display_name if maker != null else "?"


## What a grid cell says under its picture: the name and the cost.
static func cell_text(item: Resource) -> String:
	return "%s\n%d" % [item.get("display_name"), Production.cost_of(item)]


## The first line of the queue box: what is being built and how many wait.
static func queue_title(the_line: BuildLine) -> String:
	if the_line.is_empty():
		return "Nothing in the queue"
	var text: String = the_line.current().get("display_name")
	if the_line.items.size() > 1:
		text += "  (+%d)" % (the_line.items.size() - 1)
	return text


## The second line of the queue box: why the first item is waiting, if it is.
static func queue_status(the_line: BuildLine, low_power: bool) -> String:
	if the_line.is_empty():
		return ""
	match the_line.waiting:
		BuildLine.Waiting.FUNDS: return "Waiting for Orichalcum"
		BuildLine.Waiting.PLACE: return "Ready: click here, then the ground"
		BuildLine.Waiting.ROOM: return "No room for it to come out"
		BuildLine.Waiting.BUILDER: return "The building that makes it is gone"
	return "%d%%%s" % [floori(the_line.share() * 100.0), "  (low power: half speed)" if low_power else ""]


## One line saying how much power a team makes and uses.
static func power_text(world: SimWorld, team: int) -> String:
	var text := "Power %d / %d" % [world.power_used(team), world.power_made(team)]
	return text + "  LOW" if world.is_low_power(team) else text


## Open the tab with this key, if the player has it.
func open(tab_key: StringName) -> void:
	key = tab_key


## Bring the panel up to date with a team's queues.
func refresh(world: SimWorld, team: int) -> void:
	var production := world.production
	_tab_keys = production.keys(team)
	if not _tab_keys.has(key):
		key = _tab_keys[0] if not _tab_keys.is_empty() else Production.BUILDINGS
	for i in _tabs.size():
		_tabs[i].visible = i < _tab_keys.size()
		if _tabs[i].visible:
			_tabs[i].text = tab_name(world, team, _tab_keys[i])
			_tabs[i].modulate = Color.WHITE if _tab_keys[i] == key else Color(0.6, 0.6, 0.6)
	_items = production.options(team, key)
	var the_line := production.line(team, key)
	for i in _cells.size():
		_cells[i].visible = i < _items.size()
		if not _cells[i].visible:
			continue
		var item := _items[i]
		_icons[i].texture = _icon(item)
		_names[i].text = cell_text(item)
		_cells[i].disabled = the_line.items.size() >= Production.QUEUE_LIMIT
	_queue_title.text = queue_title(the_line)
	_queue_bar.size.x = roundf((WIDTH - 2.0) * (1.0 if the_line.is_ready() else the_line.share()))
	_queue_bar.color = GOLD if the_line.waiting != BuildLine.Waiting.FUNDS else POWER_LOW
	_cancel.visible = not the_line.is_empty()
	_place.visible = the_line.is_ready()
	_place.text = "Place the %s" % the_line.current().get("display_name") if the_line.is_ready() else ""
	_queue_status.visible = not the_line.is_ready()
	_queue_status.text = queue_status(the_line, world.is_low_power(team))
	_power_text.text = power_text(world, team)
	var made := world.power_made(team)
	var used := world.power_used(team)
	_power_bar.size.x = roundf((WIDTH - 2.0) * clampf(float(used) / maxi(made, 1), 0.0, 1.0))
	_power_bar.color = POWER_LOW if used > made else POWER_OK
	_power_text.add_theme_color_override("font_color", POWER_LOW if used > made else GOLD)


## What the open tab offers, in grid order.
func items() -> Array[Resource]:
	return _items


## The keys of the tabs that are shown, in order.
func tab_keys() -> Array[StringName]:
	return _tab_keys


func _on_tab(index: int) -> void:
	if index < _tab_keys.size():
		key = _tab_keys[index]


func _on_cell(index: int) -> void:
	if index < _items.size():
		build_pressed.emit(key, _items[index])


## A small picture of a building or a unit for its grid cell.
func _icon(item: Resource) -> Texture2D:
	if _icon_cache.has(item):
		return _icon_cache[item]
	var texture: Texture2D = null
	if item is BuildingType:
		texture = (item as BuildingType).sprite
	elif item is UnitType:
		var type := item as UnitType
		var atlas := AtlasTexture.new()
		atlas.atlas = type.sprites
		atlas.region = Rect2(Vector2.ZERO, Vector2(type.sprite_size))
		texture = atlas
	_icon_cache[item] = texture
	return texture


func _label(rect: Rect2, font_size: int, color: Color, parent: Control = null) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(label)
	return label


func _rect(rect: Rect2, color: Color) -> ColorRect:
	var box := ColorRect.new()
	box.position = rect.position
	box.size = rect.size
	box.color = color
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	return box


func _button(rect: Rect2, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 10)
	var shades := {"normal": Color(0.17, 0.15, 0.12), "hover": Color(0.25, 0.21, 0.15),
			"pressed": Color(0.33, 0.27, 0.17), "disabled": Color(0.1, 0.095, 0.085)}
	for state: String in shades:
		var style := StyleBoxFlat.new()
		style.bg_color = shades[state]
		style.border_color = Color(0.42, 0.34, 0.2)
		style.set_border_width_all(1)
		style.set_content_margin_all(1)
		button.add_theme_stylebox_override(state, style)
	add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button
