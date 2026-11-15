class_name Hint
extends Resource
## One step of a mission's hints (see MissionHints): what the hint box says
## until the player has done what it describes.
##
## The text may name values from the mission: {player} and {enemy} (the sides'
## names), {hold_seconds}, {storage} (what the player can store) and {ability}
## (the name of the commander's ability).

@export var id := &""
@export_multiline var text := ""
## The hint is done once this is true, and the next one is shown. Null: never
## done (the last hint stays).
@export var done_when: MissionCondition
