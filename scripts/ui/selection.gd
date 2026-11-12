class_name Selection
extends RefCounted
## Which units the player has selected, and the numbered control groups.

signal changed

## Ids of the selected units, in the order they were selected.
var ids: Array[int] = []
## Control groups: number (1 to 9) -> array of unit ids.
var groups := {}


func is_empty() -> bool:
	return ids.is_empty()


func has(id: int) -> bool:
	return ids.has(id)


## Select exactly these units.
func set_ids(new_ids: Array) -> void:
	var unique: Array[int] = []
	for id in new_ids:
		if not unique.has(id):
			unique.append(id)
	if unique != ids:
		ids = unique
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
	set_ids(ids.filter(alive))
	for number in groups:
		groups[number] = (groups[number] as Array).filter(alive)
