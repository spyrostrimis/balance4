class_name Objective
extends Resource
## Something the player has to do (or must not let happen) in a mission.
##
## The player wins when every primary objective is done, and loses as soon as
## a primary objective has failed. An objective is checked only once it is
## shown; a hidden one is shown by an ObjectiveAction. Secondary objectives
## do not decide the outcome.

@export var id := &""
## What the HUD says, e.g. "Destroy Red's forward camp."
@export var text := ""
@export var primary := true
## Hidden at the start; shown later by an ObjectiveAction.
@export var hidden := false
## Done once this is true (and then for good). Null: never done.
@export var done_when: MissionCondition
## Failed once this is true (and then for good). Null: cannot fail.
@export var failed_when: MissionCondition
