class_name SimTrailer
extends RefCounted
## A harvester's trailer standing on its own: the robot has unhitched it, or
## the harvester has been destroyed. While it is hitched to the truck there is
## no SimTrailer; truck and trailer are one unit.
##
## A trailer takes up its cell, cannot be attacked and cannot be destroyed.
## Its Orichalcum is the harvester's `cargo` for as long as the harvester
## lives. Once the harvester is dead the trailer is an orphan with a cargo of
## its own, and units of another side that come up to it take that cargo.

var id := 0
var team := 0
## The harvester type it belongs to (for its size and its picture).
var type: UnitType
var cell := Vector2i.ZERO
## The way the truck was facing when it was unhitched.
var facing := 0
## Id of the harvester it belongs to, or 0 for an orphan.
var owner_id := 0
## Orichalcum in an orphan. Not used while the harvester lives.
var cargo := 0


func is_orphan() -> bool:
	return owner_id == 0
