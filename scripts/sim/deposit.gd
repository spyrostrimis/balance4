class_name Deposit
extends RefCounted
## One Orichalcum deposit: a formation of ore-bearing rock cells that touch
## each other. Every cell starts with the amount its terrain type gives it.
## Harvesters stand beside the formation and dig into it from where they
## stand: the cell nearest to them is emptied first, then the next. A cell
## that is empty is "spent"; it stays rock that cannot be crossed. When every
## cell is spent the deposit has run out.

const NO_CELL := Vector2i(-1, -1)

var id := 0
var cells: Array[Vector2i] = []
## Orichalcum in the whole deposit at the start, and what is left of it.
var capacity := 0
var amount := 0
## Cells that have been emptied, in the order it happened. SimWorld gives every
## deposit the same array, so the UI has one list to follow.
var spent_log: Array[Vector2i] = []

var _left := PackedInt32Array()     # per cell, in the order of `cells`
var _slot := {}                     # cell -> its position in `cells`


func add_cell(cell: Vector2i, ore: int) -> void:
	_slot[cell] = cells.size()
	cells.append(cell)
	_left.append(ore)
	capacity += ore
	amount += ore


func has_cell(cell: Vector2i) -> bool:
	return _slot.has(cell)


## Orichalcum left in one cell. 0 for a cell that is not part of the deposit.
func left_at(cell: Vector2i) -> int:
	return _left[_slot[cell]] if _slot.has(cell) else 0


## Has this cell of the deposit been emptied?
func is_spent(cell: Vector2i) -> bool:
	return _slot.has(cell) and _left[_slot[cell]] == 0


func is_empty() -> bool:
	return amount == 0


## How many of its cells still hold Orichalcum.
func live_cells() -> int:
	var count := 0
	for left in _left:
		if left > 0:
			count += 1
	return count


## The cell with Orichalcum in it that is nearest to a cell, or NO_CELL once
## the deposit has run out.
func nearest_live_cell(from: Vector2i) -> Vector2i:
	var best := NO_CELL
	var best_distance := 0
	for i in cells.size():
		if _left[i] == 0:
			continue
		var distance := (cells[i] - from).length_squared()
		if best == NO_CELL or distance < best_distance:
			best = cells[i]
			best_distance = distance
	return best


## Take up to `want` Orichalcum out of the deposit for a harvester standing at
## `from`. Returns how much it got, and the cell it came from last in
## `dug_cell` (an array of one, filled in if anything was taken).
func take(from: Vector2i, want: int, dug_cell: Array[Vector2i] = []) -> int:
	var got := 0
	while got < want and amount > 0:
		var cell := nearest_live_cell(from)
		var slot: int = _slot[cell]
		var part := mini(want - got, _left[slot])
		_left[slot] -= part
		amount -= part
		got += part
		if _left[slot] == 0:
			spent_log.append(cell)
		if dug_cell.is_empty():
			dug_cell.append(cell)
		else:
			dug_cell[0] = cell
	return got
