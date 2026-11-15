class_name BuildPanel
extends Control
## The build menu in the sidebar: one tab for buildings and one for each kind
## of production building the player owns, a grid of what the open tab can
## build, the tab's build queue, and the power bar. It builds its own
## controls (styled by HudStyle) and only reports clicks; MapView gives the
## orders.

## The player clicked something to build: the queue's key and the item.
signal build_pressed(key: StringName, item: Resource)
## The player clicked Cancel on the open tab's queue.
signal cancel_pressed(key: StringName)
## The player clicked the finished building to place it.
signal place_pressed

const WIDTH := 192.0
## How many things one tab can offer: three across, two down.
const GRID := Vector2i(3, 2)
const CELL := Vector2(61, 56)
const GAP := 4.0
const TAB_HEIGHT := 18.0
const QUEUE_Y := 148.0

## The key of the open tab's queue.
var key := Production.BUILDINGS

var _tabs: Array[Button] = []
var _tab_keys: Array[StringName] = []
var _cells: Array[Button] = []
var _icons: Array[TextureRect] = []
var _names: Array[Label] = []
var _costs: Array[Label] = []
var _items: Array[Resource] = []
var _queue_title: Label
var _queue_bar: HudStyle.Bar
var _queue_status: Label
var _place: Button
var _cancel: Button
var _power_text: Label
var _power_bar: HudStyle.Bar
var _icon_cache := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(WIDTH, 212)
	for i in 3:
		var tab := HudStyle.button(self, Rect2(i * (CELL.x + GAP), 0, CELL.x, TAB_HEIGHT), "wood", "", "castle")
		tab.pressed.connect(_on_tab.bind(i))
		_tabs.append(tab)
	for i in GRID.x * GRID.y:
		var at := Vector2(i % GRID.x, i / GRID.x) * (CELL + Vector2(GAP, 6.0)) + Vector2(0, TAB_HEIGHT + 6.0)
		var cell := HudStyle.button(self, Rect2(at, CELL), "inset")
		cell.pressed.connect(_on_cell.bind(i))
		var icon := TextureRect.new()
		icon.position = Vector2(4, 4)
		icon.size = Vector2(CELL.x - 8, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		var label := HudStyle.label(cell, Rect2(0, CELL.y - 16, CELL.x, 13), &"sans", 9, HudStyle.LIGHT_DIM, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		var cost := HudStyle.label(cell, Rect2(CELL.x - 30, 3, 27, 12), &"sans_bold", 9, HudStyle.GOLD)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.1, 0.07, 0.05, 0.85)
		back.set_corner_radius_all(3)
		cost.add_theme_stylebox_override("normal", back)
		_cells.append(cell)
		_icons.append(icon)
		_names.append(label)
		_costs.append(cost)
	HudStyle.panel(self, Rect2(0, QUEUE_Y, WIDTH, 64), "parchment")
	_queue_title = HudStyle.label(self, Rect2(8, QUEUE_Y + 3, 132, 14), &"serif_bold", 10, HudStyle.INK)
	_queue_title.clip_text = true
	_cancel = HudStyle.button(self, Rect2(WIDTH - 50, QUEUE_Y + 4, 44, 14), "wood", "Cancel", "", false, 8)
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit(key))
	_queue_bar = HudStyle.bar(self, Rect2(8, QUEUE_Y + 20, WIDTH - 16, 6), HudStyle.PROGRESS)
	_queue_status = HudStyle.label(self, Rect2(8, QUEUE_Y + 27, WIDTH - 16, 13), &"sans", 9, HudStyle.INK_DIM)
	_place = HudStyle.button(self, Rect2(6, QUEUE_Y + 28, WIDTH - 12, 15), "navy", "", "", false, 9)
	_place.pressed.connect(func() -> void: place_pressed.emit())
	_power_text = HudStyle.label(self, Rect2(8, QUEUE_Y + 42, WIDTH - 16, 12), &"sans", 9, HudStyle.INK)
	_power_bar = HudStyle.bar(self, Rect2(8, QUEUE_Y + 55, WIDTH - 16, 5), HudStyle.POWER)


## The name on a queue's tab.
static func tab_name(world: SimWorld, team: int, tab_key: StringName) -> String:
	if tab_key == Production.BUILDINGS:
		return "Build"
	var maker := world.production.builder(team, tab_key)
	return maker.type.display_name if maker != null else "?"


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
			_tabs[i].tooltip_text = tab_name(world, team, _tab_keys[i])
			_tabs[i].icon = HudStyle.icon(tab_icon(world, team, _tab_keys[i]))
			_style_tab(_tabs[i], _tab_keys[i] == key)
	_items = production.options(team, key)
	var the_line := production.line(team, key)
	for i in _cells.size():
		_cells[i].visible = i < _items.size()
		if not _cells[i].visible:
			continue
		var item := _items[i]
		_icons[i].texture = _icon(item)
		_names[i].text = item.get("display_name")
		_costs[i].text = str(Production.cost_of(item))
		_cells[i].tooltip_text = "%s: %d Orichalcum" % [item.get("display_name"), Production.cost_of(item)]
		_cells[i].disabled = the_line.items.size() >= Production.QUEUE_LIMIT
	_queue_title.text = queue_title(the_line)
	_queue_bar.value = 1.0 if the_line.is_ready() else the_line.share()
	_queue_bar.color = HudStyle.PROGRESS if the_line.waiting != BuildLine.Waiting.FUNDS else HudStyle.HEALTH_BAD
	_cancel.visible = not the_line.is_empty()
	_place.visible = the_line.is_ready()
	_place.text = "Place the %s" % the_line.current().get("display_name") if the_line.is_ready() else ""
	_queue_status.visible = not the_line.is_ready()
	_queue_status.text = queue_status(the_line, world.is_low_power(team))
	_power_text.text = power_text(world, team)
	var made := world.power_made(team)
	var used := world.power_used(team)
	_power_bar.value = clampf(float(used) / maxi(made, 1), 0.0, 1.0)
	_power_bar.color = HudStyle.HEALTH_BAD if used > made else HudStyle.POWER
	_power_text.add_theme_color_override("font_color", HudStyle.INK_RED if used > made else HudStyle.INK)


## The icon on a queue's tab: a castle for buildings, a helmet for troops,
## a wheel for vehicles.
static func tab_icon(world: SimWorld, team: int, tab_key: StringName) -> String:
	if tab_key == Production.BUILDINGS:
		return "castle"
	var maker := world.production.builder(team, tab_key)
	if maker != null:
		for unit_type: UnitType in maker.type.produces:
			if unit_type.is_harvester() or unit_type.sprite_size.x > 24:
				return "wheel"
	return "helm"


func _style_tab(tab: Button, open_now: bool) -> void:
	var kind := "navy" if open_now else "wood"
	tab.add_theme_stylebox_override("normal", HudStyle.style(kind, 2.0))
	tab.add_theme_stylebox_override("hover", HudStyle.style(kind + "_hover", 2.0))


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
	if not _icon_cache.has(item):
		_icon_cache[item] = MissionHud.picture_of(item)
	return _icon_cache[item]
