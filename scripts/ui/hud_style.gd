class_name HudStyle
extends RefCounted
## The look of the HUD and the menus: fonts, colours, and panels and buttons
## made from the pictures in assets/ui (drawn by tools/make_hud.py, after the
## approved mockup v12 D). Everything here builds controls; nothing keeps state
## except the caches.

## Screen layout, in screen pixels at 960x540.
const TOP := 28.0                      ## height of the top bar, which spans the whole screen
const SIDEBAR_X := 752.0               ## where the sidebar starts
const SIDE_X := 760.0                  ## where the sidebar's contents start
const SIDE_WIDTH := 192.0

## Ink on parchment, and text on wood.
const INK := Color("33200e")
const INK_DIM := Color("6a4c2a")
const INK_RED := Color("7a1c12")
const INK_GREEN := Color("2a5a1c")
const LIGHT := Color("f2e6c4")
const LIGHT_DIM := Color("c8b898")
const GOLD := Color("e8bf6c")
const SHADOW := Color("140a04")
const HEALTH := Color("4a9a3a")
const HEALTH_LOW := Color("c8902a")
const HEALTH_BAD := Color("b83a2a")
const PROGRESS := Color("c8902a")
const POWER := Color("3a6ac8")
const BAR_BACK := Color("2a1a0c")

## Nine-slice pictures: PIECE pixels square, with PAD transparent pixels round the rim.
const PIECE_MARGIN := 16.0
const PIECE_PAD := 3.0

static var _fonts := {}
static var _styles := {}
static var _icons := {}


## A font by kind: &"serif", &"serif_bold", &"serif_italic", &"sans" or
## &"sans_bold". The serif is Georgia and the sans Verdana, taken from the
## system (they come with Windows); elsewhere Godot's own font stands in.
static func font(kind: StringName) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var system := SystemFont.new()
	match kind:
		&"serif", &"serif_bold", &"serif_italic":
			system.font_names = PackedStringArray(["Georgia", "DejaVu Serif", "serif"])
		_:
			system.font_names = PackedStringArray(["Verdana", "DejaVu Sans", "sans-serif"])
	system.font_weight = 700 if String(kind).ends_with("_bold") else 400
	system.font_italic = kind == &"serif_italic"
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	system.hinting = TextServer.HINTING_NORMAL
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_fonts[kind] = system
	return system


## A stylebox from the picture assets/ui/panel_<name>.png.
static func style(name: String, content_margin := 4.0) -> StyleBoxTexture:
	var key := "%s/%s" % [name, content_margin]
	if _styles.has(key):
		return _styles[key]
	var box := StyleBoxTexture.new()
	box.texture = load("res://assets/ui/panel_%s.png" % name)
	box.set_texture_margin_all(PIECE_MARGIN)
	box.set_expand_margin_all(PIECE_PAD)
	box.set_content_margin_all(content_margin)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_styles[key] = box
	return box


## An icon from assets/ui/icons, 18x18.
static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load("res://assets/ui/icons/%s.png" % name)
	return _icons[name]


static func panel(parent: Control, rect: Rect2, kind := "parchment", blocks_mouse := true) -> Panel:
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", style(kind))
	box.position = rect.position
	box.size = rect.size
	box.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_mouse else Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


## A label. `on_wood` gives light text with a dark shadow; otherwise ink.
static func label(parent: Control, rect: Rect2, kind: StringName, size: int, color: Color, on_wood := false) -> Label:
	var text := Label.new()
	text.position = rect.position
	text.size = rect.size
	text.add_theme_font_override("font", font(kind))
	text.add_theme_font_size_override("font_size", size)
	text.add_theme_color_override("font_color", color)
	if on_wood:
		text.add_theme_color_override("font_shadow_color", SHADOW)
		text.add_theme_constant_override("shadow_offset_x", 1)
		text.add_theme_constant_override("shadow_offset_y", 1)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(text)
	return text


## A button in one of the styles: "navy" (commands), "wood" (quiet), or
## "inset" (the build grid). With an icon name it shows that icon; `stacked`
## puts the icon above the text.
static func button(parent: Control, rect: Rect2, kind: String, text := "", icon_name := "", stacked := false,
		font_size := 10) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.position = rect.position
	b.size = rect.size
	b.clip_text = true
	b.add_theme_font_override("font", font(&"sans_bold" if kind != "inset" else &"sans"))
	b.add_theme_font_size_override("font_size", font_size)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var piece := kind
		match state:
			"hover": piece = kind + "_hover"
			"pressed": piece = kind + ("_pressed" if kind != "wood" else "_hover")
			"disabled": piece = kind + ("_disabled" if kind != "wood" else "")
		var box: StyleBox = StyleBoxEmpty.new() if state == "focus" else style(piece, 2.0)
		b.add_theme_stylebox_override(state, box)
	var light := kind != "inset"
	b.add_theme_color_override("font_color", LIGHT if light else LIGHT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", LIGHT)
	b.add_theme_color_override("font_disabled_color", Color(LIGHT_DIM, 0.6))
	b.add_theme_color_override("font_outline_color", SHADOW)
	b.add_theme_constant_override("outline_size", 2 if light else 0)
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if stacked or text == "" else HORIZONTAL_ALIGNMENT_LEFT
		if stacked:
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
		b.add_theme_constant_override("h_separation", 3)
	parent.add_child(b)
	return b


## A small icon picture.
static func icon_rect(parent: Control, at: Vector2, name: String) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = icon(name)
	picture.position = at
	picture.size = Vector2(18, 18)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture


## A thin bar on a dark groove, filled to `value` (0 to 1).
class Bar extends Control:
	var value := 0.0:
		set(v):
			if v != value:
				value = v
				queue_redraw()
	var color := HudStyle.HEALTH:
		set(c):
			if c != color:
				color = c
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), HudStyle.BAR_BACK)
		var w := roundf((size.x - 2.0) * clampf(value, 0.0, 1.0))
		if w <= 0.0:
			return
		draw_rect(Rect2(1, 1, w, size.y - 2.0), color)
		draw_rect(Rect2(1, 1, w, 1), color.lightened(0.35))


static func bar(parent: Control, rect: Rect2, color := HEALTH) -> Bar:
	var b := Bar.new()
	b.position = rect.position
	b.size = rect.size
	b.color = color
	parent.add_child(b)
	return b


## The colour of a health bar for a share of health left.
static func health_color(share: float) -> Color:
	if share > 0.6:
		return HEALTH
	return HEALTH_LOW if share > 0.3 else HEALTH_BAD
