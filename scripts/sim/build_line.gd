class_name BuildLine
extends RefCounted
## One build queue of one side: either the buildings its headquarters is
## constructing, or the units one kind of production building is turning out.
## The first item is the one being built; the others wait their turn.
## Production fills these in and advances them.

## Why the first item is not getting on, if it is not.
enum Waiting {
	## It is being built.
	NOTHING,
	## The side cannot pay for the next bit of it.
	FUNDS,
	## A finished building waits for the player to put it on the map.
	PLACE,
	## A finished unit has no free cell to come out on.
	ROOM,
	## The building that does the work is gone.
	BUILDER,
}

## The BuildingType or UnitType of each item, first one first.
var items: Array[Resource] = []
## Ticks of work done on the first item, and Orichalcum paid for it so far.
var progress := 0
var paid := 0
var waiting := Waiting.NOTHING


func is_empty() -> bool:
	return items.is_empty()


## The item being built, or null.
func current() -> Resource:
	return items[0] if not items.is_empty() else null


## How far the first item is, 0 to 1.
func share() -> float:
	if items.is_empty():
		return 0.0
	return clampf(float(progress) / Production.ticks_of(items[0]), 0.0, 1.0)


## Is the first item a finished building waiting to be placed?
func is_ready() -> bool:
	return waiting == Waiting.PLACE
