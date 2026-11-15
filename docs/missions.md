# Balance: how a mission is made

A mission is data: one `MissionDef` file in `data/missions/`, made of small
parts whose scripts are in `scripts/sim/missions/`. This format came with
milestone M7 (step M7.2, see [m7-plan.md](m7-plan.md)). Mission 1, the three
trials and the skirmish are written in it.

`Mission` (`scripts/sim/mission.gd`) plays a `MissionDef`: it sets up the
world, then on every tick lets the opponents think, advances the world,
updates the control area, checks the objectives and fires the triggers.

## The parts of a mission

| Field | What it is |
| --- | --- |
| `id`, `number`, `display_name` | Its internal name, its number in the campaign, its name on screen |
| `kind` | Story, practice or skirmish. This only decides what the HUD shows and how the mission is named; the rules come from the objectives |
| `map` | The map (`data/maps/`) |
| `sides` | The sides (`MissionSide`); the first is the player's |
| `forces` | What is on the map at the start (`Placement`) |
| `ore_richness` | How many times richer than usual the Orichalcum rock is |
| `control_radius`, `hold_seconds` | The control area around the map's control point; a hold time of 0 means there is none |
| `objectives` | What the player must do (`Objective`) |
| `triggers` | What happens during the mission (`MissionTrigger`) |
| `hints` | What the message box teaches when nobody is talking (`HintList`, shared files in `data/hints/`) |
| `briefing` | The story told on the briefing screen before a story mission |
| `debriefing_won`, `debriefing_lost` | What the debriefing says after a win and after a loss |
| `next_mission` | The mission that follows a win (its file), offered on the debriefing; empty for none |

`MissionDef.problems()` lists what is wrong with a mission's data (a
placement for a side that does not exist, a start position the map has not
got, two objectives with one id); a test checks every mission file with it.

### Sides

A `MissionSide` has a name and colour for the HUD, which of the map's start
positions is its own, the Orichalcum in its store at the start (never more
than its buildings can hold), whether it knows where the rock is from the
start, and who plays it:

| `opponent` | Who plays the side |
| --- | --- |
| none | The player (the first side), or nobody |
| `RushOpponentDef` | Mission 1's script (`ScriptedOpponent`): after a delay, sends its force to the control area in two waves |
| `RaidersDef` | The raid trial's raiders (`Raiders`): after a delay, go for the harvesters and their trailers |
| `ComputerOpponentDef` | The computer opponent of the skirmish (`ComputerOpponent`) |
| `CampOpponentDef` | The same in camp mode: it harvests, trains, defends and repairs, but never attacks (Mission 2's Red camp) |

### Placed forces

A `Placement` puts units or one building on the map: its side, its type (a
unit type or a building type), how many units, and where: around the side's
start, around a given cell, or beside the side's refinery (where harvesters
stand). Buildings go down first, on the free building ground nearest to
their spot, then units, on the free cells nearest to theirs, facing the
control area.

A placement can carry a **tag**, a name that conditions and actions use to
find what it placed: "everything tagged `forward_camp` is gone", "send the
units tagged `second_wave`". Several placements can share a tag.

### Objectives

An `Objective` has an id, the text the HUD shows, whether it is primary or
secondary, whether it is hidden at the start, a condition for being done and
one for having failed.

- An objective is checked only while it is shown. A hidden one is shown by
  an `ObjectiveAction`.
- Done or failed, it stays so.
- **The player wins when every primary objective is done**, for the reason
  of the last one done.
- **The player loses as soon as a primary objective fails.**
- Secondary objectives do not decide the outcome.
- A mission with no primary objective that can be done (a practice mission)
  goes on until the player leaves it.
- Whatever the objectives say, **losing any of the player's heroes loses the
  mission** (see [heroes.md](heroes.md)).

### Triggers

A `MissionTrigger` fires once: when its condition first becomes true (or at
the start, if it has none), after an optional delay, it runs its actions in
order.

| Action | What it does |
| --- | --- |
| `MessageAction` | Shows a message in the message box for eight seconds, with who says it and their portrait (its own `portrait`, or else that of the player's hero with the speaker's name) |
| `ObjectiveAction` | Shows a hidden objective, and says so in a message |
| `GiveAction` | Puts Orichalcum into a side's store, as far as it fits |
| `ReinforceAction` | Puts more units or buildings on the map (placements) |
| `RevealAction` | Lifts the shroud for a side around a cell |
| `SendAction` | Sends a side's units (those with a tag, or all its fighters) somewhere with attack-move: to a cell, or to where a tagged unit stands (e.g. the Prince) |
| `EndAction` | Ends the mission: a side wins, for a reason |

### Conditions

Objectives, triggers and hints decide with conditions. A condition carries a
reason (`hold`, `eliminated`, ...), which the result screen puts into words
when that condition decides the mission.

| Condition | True when |
| --- | --- |
| `TimeCondition` | The mission has run for so many seconds |
| `DefeatCondition` | A side has no units left, or (in a base game) no buildings and no troops |
| `HoldCondition` | A side has held the control area for the hold time |
| `GoneCondition` | Everything placed under a tag is destroyed |
| `AreaCondition` | A side has so many units (or units with a tag) near a cell |
| `BuildingCondition` | A side has so many buildings (of a type) |
| `StoreCondition` | A side has so much Orichalcum in store |
| `ObjectiveCondition` | An objective is done (or has failed) |
| `EventCondition` | The player has done something: selected, moved, attacked, used an ability, harvested, built, placed, trained |
| `AllCondition`, `AnyCondition` | All, or any, of several conditions |

### Hints

A `HintList` (`data/hints/`) is the hints' steps in order, shown in the
message box while no character is talking. Each `Hint`
has a text and a condition; the box shows the first step not yet done, and a
step once done stays done. The last step has no condition and stays up. A
text may name values from the mission: `{player}`, `{enemy}`,
`{hold_seconds}`, `{storage}` and `{ability}`. Missions that teach the same
things share a list.

## The missions so far

| Mission | Sides and who plays them | Objective |
| --- | --- | --- |
| Mission 1 (`first_claim_*`) | The player; the rush script | Done: the enemy has no units left, or the player holds the rock. Failed: the player has no units left, or the enemy holds the rock |
| Harvest trial (`harvest_trial_*`) | The player; nobody | None that can be done |
| Raid trial (`raid_trial_*`) | The player; raiders | None that can be done |
| Base trial (`base_trial_*`) | The player; nobody | None that can be done |
| Skirmish (`skirmish_*`) | The player; the computer | Done: the enemy has no buildings and no troops. Failed: the player has none |
| Mission 2 (`holding_the_claim_blue`) | The player; Red's camp (camp mode), and triggers that bring scouts and an assault | Five objectives, four shown one after another: see [mission2.md](mission2.md) |
| Hero trial (`hero_trial_blue`) | The player; nobody, but triggers bring three attacks | Hidden until the last attack: beat it off (everything tagged `wave1` to `wave3` gone) |

They play exactly as before the format changed; the tests that check their
outcome and timing are unchanged.

## Editing a mission

The files are Godot text resources and can be edited in the Godot editor's
inspector, which shows every part with its fields, or by hand. A new
condition or action is a small script in `scripts/sim/missions/` that
extends `MissionCondition` (with `check()`) or `MissionAction` (with
`run()`).
