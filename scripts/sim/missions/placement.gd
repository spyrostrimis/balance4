class_name Placement
extends Resource
## Units or a building put on the map by a mission: at the start, or later as
## reinforcements (see ReinforceAction).

enum At {
	## Around the side's start position.
	START,
	## Around `cell`.
	CELL,
	## Beside the side's first refinery (where its harvesters stand).
	REFINERY,
}

## The side it belongs to (its place in MissionDef.sides).
@export var team := 0
## A UnitType or a BuildingType.
@export var type: Resource
## How many units. A building is always one.
@export var count := 1
@export var at := At.START
## The cell for At.CELL.
@export var cell := Vector2i.ZERO
## A name that conditions and actions use to find what was placed, e.g.
## &"forward_camp". Several placements may share one.
@export var tag := &""


func is_building() -> bool:
	return type is BuildingType
