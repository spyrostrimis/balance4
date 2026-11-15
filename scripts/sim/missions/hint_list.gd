class_name HintList
extends Resource
## The hints of a mission, in order. Kept in a file of its own so that
## missions that teach the same things share one (data/hints/).

@export var hints: Array[Hint] = []
