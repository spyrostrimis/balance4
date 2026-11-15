class_name MissionSide
extends Resource
## One side in a mission: its name and colour on screen, where it starts, what
## it has in store, and who plays it. The side's team is its place in
## MissionDef.sides: the first is the player (team 0).

## Name shown on screen, e.g. "Blue".
@export var name := ""
## Colour of the side in the HUD.
@export var color := Color.WHITE
## Which of the map's start positions is this side's (an index into MapData.starts).
@export var start := 0
## Orichalcum in its store at the start (never more than its buildings can store).
@export var orichalcum := 0
## Does it know where the Orichalcum rock is from the start? The rock is then
## revealed on its map.
@export var knows_deposits := false
## Who plays it: null for the player (or for a side that does nothing),
## otherwise an opponent (see OpponentDef).
@export var opponent: OpponentDef
