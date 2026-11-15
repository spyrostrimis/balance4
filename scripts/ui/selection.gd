class_name Selection
extends RefCounted
## Which units (or which one building) the player has selected, and the
## numbered control groups. A building is selected on its own: selecting
## units lets go of it, and selecting it lets go of the units.

signal changed

## Ids of the selected units, in the order they were selected.
var ids: Array[int] = []
## Id of the selected building, or 0.
var building_id := 0
## Control groups: number (1 to 9) -> array of unit ids.
var groups := {}


## Is nothing selected: no unit and no building?
func is_empty() -> bool:
	return ids.is_empty() and building_id == 0


## Select one building (and no units).
func set_building(id: int) -> void:
	if building_id == id and ids.is_empty():
		return
	building_id = id
	ids = []
	changed.emit()


func has(id: int) -> bool:
	return ids.has(id)


## Select exactly these units.
func set_ids(new_ids: Array) -> void:
	var unique: Array[int] = []
	for id in new_ids:
		if not unique.has(id):
			unique.append(id)
	if unique != ids or (building_id != 0 and not unique.is_empty()):
		ids = unique
		if not unique.is_empty():
			building_id = 0
		changed.emit()


## Add units to the selection.
func add_ids(more_ids: Array) -> void:
	var combined: Array = ids.duplicate()
	combined.append_array(more_ids)
	set_ids(combined)


## Add a unit if it is not selected, remove it if it is.
func toggle(id: int) -> void:
	var next: Array = ids.duplicate()
	if next.has(id):
		next.erase(id)
	else:
		next.append(id)
	set_ids(next)


func clear() -> void:
	var had_building := building_id != 0
	building_id = 0
	if had_building and ids.is_empty():
		changed.emit()
	set_ids([])


## Remember the current selection as group `number`.
func assign_group(number: int) -> void:
	groups[number] = ids.duplicate()


## Select group `number`. Returns false (and changes nothing) if the group is empty or unset.
func recall_group(number: int) -> bool:
	var group: Array = groups.get(number, [])
	if group.is_empty():
		return false
	set_ids(group)
	return true


## Forget units that no longer exist.
func prune(world: SimWorld) -> void:
	var alive := func(id: int) -> bool: return world.get_unit(id) != null
	if building_id != 0 and world.get_building(building_id) == null:
		building_id = 0
		changed.emit()
	set_ids(ids.filter(alive))
	for number in groups:
		groups[number] = (groups[number] as Array).filter(alive)
