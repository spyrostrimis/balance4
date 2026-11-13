# Balance: combat, the commander and Mission 1

How units fight, what the field commander can do, how the control point works
and how Mission 1 is put together. This is what milestone M3 built. Units,
move orders and the shroud are described in [units.md](units.md).

**Every name and number here is provisional.** They were chosen to make the
first mission playable and will be tuned later. The provisional choices are
collected in one table near the end.

## Fighting

Each unit type has four combat values (in its file in `data/units/`):

| Field | Meaning |
| --- | --- |
| `attack_damage` | Health taken off the target by one hit. 0 means the unit cannot attack. |
| `attack_range` | How far it can hit, in cells. 1 reaches the eight cells around it. |
| `attack_interval` | Seconds between two hits. |
| `acquire_range` | How far away it notices enemies on its own, in cells. |

Ranges are round, measured from cell to cell in the same way as the area a
unit sees.

The rules, all in `SimWorld` (`scripts/sim/sim_world.gd`):

- A unit hits only while it stands in a cell, not while it is between two
  cells. It turns to face its target. The first hit lands at once; after that
  it hits once every `attack_interval`.
- A unit whose health reaches 0 dies. It is removed from the world at once:
  its cell is free again, it can no longer be found or ordered about, and the
  selection and the control groups forget it.
- **Units pick targets on their own.** A unit with nothing to do attacks the
  nearest enemy within its `acquire_range`. If the enemy is not next to it, it
  walks up to a free cell beside it. It gives up on an enemy that gets more
  than two cells beyond that range.
- **Units fight back.** A unit that is hit goes for its attacker, even one too
  far away to notice otherwise. Idle units within six cells of the unit that
  was hit come to its help.
- A unit that was told to **move** does none of this. It walks where it was
  sent and ignores enemies until it arrives.

## Orders

| Order | What the units do |
| --- | --- |
| Move | Walk to the spot. Ignore enemies on the way. |
| Attack | Chase one enemy unit and attack it until it is dead. Other enemies are left alone meanwhile. |
| Attack-move | Walk to the spot, fight every enemy noticed on the way, then carry on. |
| Stop | Stand still. The units still fight enemies that come near. |
| Ability | The commander walks up to a unit and uses its ability on it (see below). |

## Controls

These follow the habits of modern strategy games.

| Input | What it does |
| --- | --- |
| Left click | Select the unit under the mouse; click empty ground to deselect |
| Left drag | Select every unit in the box |
| Shift + click or drag | Add to the selection (Shift + click on a selected unit removes it) |
| Right click on the ground | Move the selected units there |
| Right click on an enemy | Attack that enemy |
| A, then left click | Attack-move to the spot (or attack the enemy clicked on) |
| S | Stop |
| Q, then left click on one of your units | The commander uses its ability on that unit |
| Right click or Esc after A or Q | Cancel |
| Ctrl + 1 to 9 | Store the selection as a numbered group |
| 1 to 9 | Select that group; press twice quickly to jump the camera to it |
| Arrow keys, or mouse at a screen edge | Scroll the map |
| Click or drag on the minimap | Jump the camera |
| Esc | Back to the title screen |

The sidebar has three buttons that do the same as A, S and Q. Q works whether
or not the commander is selected. After A or Q the mouse pointer becomes a
cross and the hint box says what the next click will do.

## What the player sees

- **Enemy units** are drawn, shown on the minimap and can be clicked only
  while they stand on ground the player has explored. Explored ground stays
  revealed for good (the Dune II rule), so there is no fog that closes again.
- **Health bars** appear over every unit that has been hurt, and over selected
  units.
- **A hit** shows as a short streak and a spark on the target; the attacker
  leans into the blow and the victim flashes red for a moment.
- **A death** leaves a dark mark that fades.
- **A heal** shows as a green line from the commander, a ring and rising plus
  signs on the healed unit.
- A commander has a small gold chevron above it.

## The field commander

Heroes are units with `is_hero` set and an `ability` (a file in
`data/abilities/`). Mission 1 gives each side one hero, its field commander.

The commander is tougher and hits harder than a soldier, and has one ability,
**Mend** (provisional name): it gives health back to one other unit of its own
side. The design gives Blue's field commander a single-target heal/repair;
this is that ability.

- Press Q or the Mend button, then left-click the unit. The commander walks to
  within three cells of it and heals it.
- The ability then needs time to recharge. The button counts down.
- It cannot be used on a unit at full health, on an enemy, or on the commander
  itself.

**Red's field commander is a placeholder.** Nothing has been decided about
that character. So that the mission is the same for both sides, Red's
commander is a copy of Blue's with Red's colours: the same values and the same
Mend ability. It has no name and no story. See the open questions in
[design.md](design.md).

## The control point

The Orichalcum rock stands in the middle of both maps. It is a terrain type
(`ore_rock`) that cannot be crossed. Around it is the **control area**: a
circle drawn on the ground as a dotted ring, and as a ring on the minimap.

`ControlPoint` (`scripts/sim/control_point.gd`) applies the rule:

- A side **holds** the area while it is the only side with units inside. Its
  hold time counts up.
- While both sides have units inside, the area is **contested** and the count
  waits where it is.
- When the area is empty, or the other side takes it, the count starts again
  from zero.
- A side that holds the area for the whole hold time wins.

The ring on the ground takes the colour of the side whose time is counting and
fills up clockwise with larger dots. The sidebar shows the same as a bar and a
countdown.

## Winning and losing

A mission (`Mission`, `scripts/sim/mission.gd`) ends as soon as one of these
is true:

- one side has held the control area for the hold time, or
- one side has no units left.

The game then stops and shows VICTORY or DEFEAT with the reason, the time
played and the losses on both sides. "Play again" restarts the mission;
"Title screen" (or Esc) goes back to the title.

## Mission 1: "The First Claim"

The mission is defined in `data/missions/` (a `MissionDef` resource): the map,
the two forces, the control radius, the hold time and the opponent's timing.

| | Played as Blue | Played as Red |
| --- | --- | --- |
| File | `first_claim_blue.tres` | `first_claim_red.tres` |
| Map | Forest | Desert |
| Player | 4 Guardsmen and the Blue field commander | 4 Legionaries and the Red field commander (placeholder) |
| Opponent | 4 Legionaries and the Red field commander (placeholder) | 4 Guardsmen and the Blue field commander |

Both forces start at opposite corners. There is no base building.

**The opponent** is a short script (`ScriptedOpponent`), not the real enemy
AI, which is milestone M6. It waits, then sends half of its troops to the
control area with attack-move orders, and the other half with its commander a
little later. From then on it sends idle units at any of the player's units
inside the area. It never uses its commander's ability. A player who does
nothing loses to the hold rule; a player who takes the whole squad to the rock
and uses Mend wins comfortably.

**The hints.** A box at the bottom of the map teaches one thing at a time and
moves on when the player has done it:

1. Select your troops.
2. Right-click to move; where the rock is.
3. Attack-move (A) and attacking an enemy with a right click.
4. The commander's ability (Q).
5. The control area and the hold time.

The sidebar shows the objective, who holds the rock, the hold progress and the
number of units on each side. A bar along the top of the map shows the mission
name and the time played.

## Provisional choices

All of these are first values, kept in data so they are easy to change.

| What | Value | Where |
| --- | --- | --- |
| Guardsman, Legionary: attack | 12 damage, range 1, one hit a second | `data/units/*_infantry.tres` |
| Guardsman, Legionary: notice enemies at | 4 cells | same |
| Commander: health, speed, sight | 120, 2.5 cells/s, 5 cells | `data/units/*_commander.tres` |
| Commander: attack | 16 damage, range 1, one hit a second | same |
| Mend | heals 40, from up to 3 cells, ready again after 12 s, not on itself | `data/abilities/mend.tres` |
| Control area radius | 5 cells | `data/missions/*.tres` |
| Hold time | 45 s | same |
| Opponent sets off after | 20 s | same |
| Opponent's second wave follows after | 8 s | same |
| Contested area | the count waits (it does not reset) | `scripts/sim/control_point.gd` |
| Empty area | the count resets | same |
| Help range, chase limit, fight-back time | 6 cells, 2 cells beyond notice range, 5 s | `scripts/sim/sim_world.gd` |
| Keys | A attack-move, S stop, Q ability | `scripts/ui/map_view.gd` |
| Red's field commander | a recoloured copy of Blue's | `data/units/red_commander.tres` |

## Left out of M3

- Armour. The mockups show an armour value; hits take their full damage.
- A hold-position order and a patrol order.
- Ranged weapons with projectiles. The rules support any range, but both
  infantry types fight at range 1.
- Passive hero abilities, and the leaders' abilities.
- A mission briefing, a pause menu and sound.
- An opponent that thinks. It follows the script above.
