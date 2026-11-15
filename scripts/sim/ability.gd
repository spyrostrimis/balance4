class_name Ability
extends Resource
## Something a hero can do. An active ability is used when the player tells
## the hero to (UnitType.ability); a passive one is always on
## (UnitType.passive). Defined in data/abilities/*.tres.

enum Kind {
	## Active: give health back to one unit of the hero's own side.
	HEAL_TARGET,
	## Active: give health back to every unit of the hero's own side within
	## `cast_range` cells of the hero, the hero included (troops are healed,
	## vehicles repaired; buildings are not).
	HEAL_AREA,
	## Passive: the hero's own units within `cast_range` cells of it (not the
	## hero itself) move and attack `amount` percent faster.
	HASTE_AURA,
}

## Short internal name, e.g. &"mend".
@export var id: StringName
## Name shown to the player.
@export var display_name := ""
## One line saying what it does.
@export var description := ""
@export var kind := Kind.HEAL_TARGET
## How much it does: health given back for a heal, percent faster for a haste aura.
@export var amount := 40
## For a heal on one unit: how close the hero must be to it. For an area or an
## aura: how far it reaches. In cells.
@export var cast_range := 3
## Seconds before it can be used again.
@export var cooldown := 12.0
## Can the hero use it on itself?
@export var can_target_self := false
## The key that uses it, e.g. "Q". Every active ability has its own.
@export var key := "Q"


func cooldown_ticks() -> int:
	return maxi(1, roundi(cooldown * SimWorld.TICKS_PER_SECOND))


## Is it used on one unit the player picks (rather than at once, around the hero)?
func needs_target() -> bool:
	return kind == Kind.HEAL_TARGET


func is_passive() -> bool:
	return kind == Kind.HASTE_AURA
