class_name ControlView
extends Node2D
## Draws the control area on the map: a dotted ring around the Orichalcum rock.
## The ring takes the colour of the side whose hold time is counting, and fills
## up clockwise from the top with larger dots as that time passes. While both
## sides are inside, the dots alternate between the two colours.

const CELL := MapData.CELL_SIZE
const NEUTRAL := Color(0.93, 0.9, 0.78)
## How many dots the ring is made of.
const DOTS := 96

var control: ControlPoint
## Team -> colour.
var team_colors := {}


func setup(p_control: ControlPoint, p_team_colors := {}) -> void:
	control = p_control
	team_colors = p_team_colors
	visible = control != null
	queue_redraw()


## Colour of the ring: the owner's colour, or a neutral one while nobody's time is counting.
static func ring_color(p_control: ControlPoint, p_team_colors: Dictionary) -> Color:
	if p_control.owner == ControlPoint.NOBODY:
		return NEUTRAL
	return p_team_colors.get(p_control.owner, NEUTRAL)


## How many of the ring's dots are filled in for the hold time so far.
static func filled_dots(p_control: ControlPoint) -> int:
	if p_control.owner == ControlPoint.NOBODY:
		return 0
	return clampi(roundi(p_control.progress() * DOTS), 0, DOTS)


func _process(_delta: float) -> void:
	if control != null:
		queue_redraw()


func _draw() -> void:
	if control == null:
		return
	var center := control.center * CELL
	var radius := control.radius * CELL
	var color := ring_color(control, team_colors)
	var filled := filled_dots(control)
	var others: Array = team_colors.keys().filter(func(team: int) -> bool: return team != control.owner)
	for i in DOTS:
		var angle := -PI / 2.0 + TAU * i / DOTS
		var point := (center + Vector2(cos(angle), sin(angle)) * radius).round()
		var dot := color
		if control.contested and i % 2 == 1 and not others.is_empty():
			dot = team_colors[others[0]]
		if i < filled:
			draw_rect(Rect2(point - Vector2.ONE, Vector2(3, 3)), dot)
		else:
			draw_rect(Rect2(point, Vector2(2, 2)), dot)
