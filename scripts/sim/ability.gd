class_name Ability
extends Resource
## Something a hero can do when the player tells it to. Defined in data/abilities/*.tres.

enum Kind {
	## Give health back to one unit of the hero's own side.
	HEAL_TARGET,
}

## Short internal name, e.g. &"mend".
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
## One line saying what it does.
@export var description := ""
@export var kind := Kind.HEAL_TARGET
## How much it does (for a heal: health given back).
@export var amount := 40
## How close the hero must be to the target, in cells.
@export var cast_range := 3
## Seconds before it can be used again.
@export var cooldown := 12.0
## Can the hero use it on itself?
@export var can_target_self := false


func cooldown_ticks() -> int:
	return maxi(1, roundi(cooldown * SimWorld.TICKS_PER_SECOND))
