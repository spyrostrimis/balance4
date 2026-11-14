# Balance: Orichalcum, the harvester and the refinery

How Orichalcum gets from the rock into the store. This is what milestone M4
built. Units and orders are described in [units.md](units.md), fighting in
[combat.md](combat.md), terrain in [terrain.md](terrain.md).

**Every name and number here is provisional.** They were chosen so that the
loop can be played and watched, and will be tuned later. The provisional
choices are collected in one table near the end.

## Deposits

A terrain type with an `ore` value above 0 is ore-bearing. So far that is the
Orichalcum rock (`ore_rock`), which holds 50 per cell. When a map is loaded,
`SimWorld` groups ore-bearing cells that touch (a side or a corner) into
**deposits** (`Deposit`, `scripts/sim/deposit.gd`). Both maps have one: the
formation in the middle, 20 cells (1000 Orichalcum) in the forest and 21 cells
(1050) in the desert.

- A harvester stands beside the formation and digs into it from where it
  stands: the cell nearest to it is emptied first, then the next nearest.
- A cell that has been emptied is **spent**. It is drawn as bare, broken rock
  with the crystals gone, and turns grey on the minimap. It stays rock:
  nothing can walk across it.
- When every cell is spent the deposit has **run out**. Nothing brings it
  back.

## The harvester

The harvester is a unit type with a `cargo_capacity` (see the fields in
`data/units/*_harvester.tres`). It cannot attack. It does what the design
describes:

1. It drives to the deposit as a truck and stops on a free cell beside it.
2. It unfolds into a robot.
3. It digs until its hold is full or the deposit has run out.
4. It folds back into a truck.
5. It drives to its side's nearest refinery, stops beside it and unloads.

Then it goes back for more, on its own, until the deposit has run out. If
there is another deposit with Orichalcum that it can reach, it moves on to
that one. With nothing left to fetch it unloads what it has and waits for
orders.

Details:

- Only a truck drives and only a robot digs. A robot that gets a new order
  (move, stop, another rock, the refinery) first folds up, which takes a
  second.
- Several harvesters can work one deposit; each needs its own cell beside it.
  A harvester that finds every cell taken waits and looks again.
- A harvester with a load and no refinery to take it to waits where it is.
- The hold shows on the map: the truck is drawn empty, or with a heap of ore
  once it is at least half full, and a gold bar under its health bar shows the
  cargo.

`SimUnit.job` says which of these steps a harvester is on; the rules are in
`SimWorld` under "Orichalcum".

## The refinery and storage

The refinery is the first building (`BuildingType`, `data/buildings/`;
`SimBuilding` in the simulation). It covers 3 by 2 cells. Units cannot enter
the cells a building covers and plan their paths around it. Buildings stand
only on ground that can be built on (stone in the forest, rock in the desert).

- A harvester beside a refinery of its own side hands over its cargo. The
  Orichalcum goes into its side's **store**.
- **Storage has a limit**: the sum of the `storage` of a side's buildings. One
  refinery stores 800.
- **What does not fit is lost** (the Dune II rule). The harvester still
  empties its hold. The HUD counts what was lost.

In M4 the refinery is put on the map by the mission, on the nearest ground to
the player's start that it fits on. Placing buildings, their cost, their
health and attacking them come with M5. Nothing can be bought yet, so the
store only fills.

## Controls

| Input | What it does |
| --- | --- |
| Right click on the Orichalcum rock, with harvesters selected | They start harvesting it |
| Right click on your refinery, with harvesters selected | They unload there now, then go back to work |
| Right click anywhere else, S | Move and stop, as for any unit (a robot folds up first) |

Other units in the same selection walk to the spot that was clicked. The rock
and the refinery must be on ground the player has explored.

## What the player sees

- **The top bar** shows the store: `Orichalcum 350 / 800`, with `(full)` when
  it is. It appears as soon as the player has storage, so Mission 1 does not
  show it.
- **The sidebar** shows, for a selected harvester, its cargo and what it is
  doing; for the cell under the mouse, the Orichalcum in a rock cell and in
  the whole rock, or the refinery's storage.
- A digging robot swings its arms and chips of ore fly off the rock. An
  unloading truck sends ore across to the refinery.

## The harvest trial

M4's playable result is a **practice mission**, started from the title screen
("Harvest trial") or with `-- --map=harvest-forest` or `--map=harvest-desert`.
It is not part of the campaign and Mission 1 is unchanged.

| | As Blue | As Red |
| --- | --- | --- |
| File | `harvest_trial_blue.tres` | `harvest_trial_red.tres` |
| Map | Forest | Desert |
| Player | A refinery and two harvesters | A refinery and two harvesters |
| Opponent | None | None |

A practice mission (`practice` in `MissionDef`) has no opponent, no control
ring and no way to win or lose; Esc leaves it. The rock is on the player's map
from the start. The hints teach two things: select a harvester, and
right-click the rock. After that the harvesters work alone. In about two
minutes the store is full at 800, and the rest of the rock is lost to the full
store as it runs out, so both rules can be seen in one sitting.

## Provisional choices

| What | Value | Where |
| --- | --- | --- |
| Orichalcum in one rock cell | 50 | `data/terrain/*_ore_rock.tres` |
| Harvester: health, speed, sight | 150, 3.5 cells/s, 4 cells | `data/units/*_harvester.tres` |
| Harvester: hold | 100 | same |
| Harvester: digs, unloads | 20 a second, 50 a second | same |
| Harvester: changing shape | 1 s | same |
| Refinery: size, storage | 3 by 2 cells, 800 | `data/buildings/*_refinery.tres` |
| A full store | deliveries are lost | `scripts/sim/sim_world.gd` |
| Spent rock | stays impassable | same |
| The trial | two harvesters, no opponent, no end | `data/missions/harvest_trial_*.tres` |

## The art

The harvester truck is the one from the approved mockups; its robot shape and
the refinery are new, in the same manner. `tools/render_units.py` renders
them, `tools/make_units.py` packs the harvester's sheet (8 facings by 5 rows:
empty truck, loaded truck, halfway, and the two halves of the robot's swing)
and `tools/make_buildings.py` puts the refinery on its foundation of concrete
plates. The spent rock is `ore_rock_spent.png`, made by `tools/make_tiles.py`
with the same outline as the rock.

## Left out of M4

- Spending Orichalcum, and placing, damaging or destroying buildings (M5).
- A harvester or refinery for the opponent (M6).
- Storage buildings other than the refinery.
- Selecting buildings.
- Sound.
