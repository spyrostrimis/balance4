# Balance: Orichalcum, the harvester and the refinery

How Orichalcum gets from the rock into the store, and how a harvester defends
what it has dug. This is what milestone M4 built. Units and orders are
described in [units.md](units.md), fighting in [combat.md](combat.md), terrain
in [terrain.md](terrain.md).

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

- A robot digs into the formation from where it stands: the cell nearest to
  it is emptied first, then the next nearest.
- A cell that has been emptied is **spent**. It is drawn as bare, broken rock
  with the crystals gone, and turns grey on the minimap. It stays rock:
  nothing can walk across it.
- When every cell is spent the deposit has **run out**. Nothing brings it
  back.

## The harvester: truck, robot and trailer

The harvester is one unit made of two parts: a **cab** that can stand up as a
robot, and a **trailer** that holds the Orichalcum. Hitched together they are
a truck. Its values are in `data/units/*_harvester.tres`.

1. It drives to the deposit as a truck and parks beside rock that still holds
   Orichalcum.
2. The cab unfolds into a robot and steps off. The trailer stays where the
   truck stopped.
3. The robot digs until the pack on its back is full (25), walks back to the
   trailer and tips the pack into it. It does this until the trailer is full
   (100) or the deposit has run out.
4. The robot steps back onto the trailer and folds into a truck.
5. The truck drives to its side's nearest refinery, stops beside it and
   unloads.

Then it goes back for more, on its own, until the deposit has run out. If
there is another deposit with Orichalcum that it can reach, it moves on to
that one. With nothing left to fetch it unloads what it has and waits for
orders.

Details:

- **One health bar, one cargo bar.** Truck and robot are the same unit and
  share its health. The cargo bar is the trailer's: it is drawn on the truck
  while they are hitched and on the trailer while it stands on its own. What
  is in the robot's pack is not cargo yet.
- **The trailer** standing on its own (`SimTrailer`) takes up its cell,
  cannot be selected, cannot be attacked and cannot be destroyed.
- The robot digs from the free cell beside the Orichalcum nearest to its
  trailer. As the rock is eaten away that cell moves, and the robot has
  further to carry. When it would have to walk more than three cells, it
  hitches up and parks the trailer nearer.
- A robot that gets a new order (move, stop, another rock, the refinery)
  first walks back to its trailer and becomes a truck. What is in its pack
  goes into the trailer. Only a truck drives across the map.
- Several harvesters can work one deposit; each parks its own trailer.
- A harvester with a load and no refinery to take it to waits where it is.
- The truck is drawn empty, or with a heap of ore once the trailer is at
  least half full; so is the trailer on its own.

`SimUnit.job` says which of these steps a harvester is on; the rules are in
`SimWorld` under "Orichalcum" and "truck, robot and trailer".

## Guarding the trailer

A harvester never attacks on its own account and takes no attack orders. It
fights only to defend its trailer.

- **A truck that is hit** stops, unfolds and stands guard beside its trailer.
- **A robot at work** stops work as soon as an enemy that can fight comes
  within four cells of the trailer or of itself, walks back to the trailer
  and stands guard. It makes no difference whether the trailer is empty or
  full.
- **On guard** the robot stays on a cell beside its trailer, on the side the
  enemy is on, and hits any enemy that comes within reach. It does not chase.
- **Other sides' harvesters are no threat.** They never attack, so nobody
  guards against them.
- Two seconds after the last enemy has gone the robot goes back to digging,
  or hitches up and carries on with its trip.
- A truck that has been **told to move** does not unfold when it is hit: it
  drives on. This is how the player pulls a harvester out of a fight.

The robot is hard to destroy and hits weakly, so that the player has time to
send help:

| | Truck | Robot |
| --- | --- | --- |
| Health | 180, shared | 180, shared |
| Armour | none | stops 70% of every hit (a soldier's 12 becomes 4) |
| Attack | none | 10, range 1, every 1.5 seconds |

One or two soldiers lose against a robot. Three destroy it, and it takes two
of them with it.

## The trailer of a destroyed harvester

- If the trailer is **empty**, it disappears with its harvester.
- Otherwise it stays where it stands as an **orphan**: a slow gold ring is
  drawn around it and it is a gold dot on the minimap. What the robot had in
  its pack is lost.
- **A unit of another side that stands next to an orphan takes its
  Orichalcum.** A side with a refinery puts it straight into its store, as
  far as it fits (the trailer stays with the rest); a side without storage
  takes all of it. An emptied orphan is gone.
- This also applies to a truck destroyed on the road with cargo on board.

Taking a trailer this way needs no refinery and no transport. That is a
deliberate simplification for now; it will be worked on later. A side cannot
yet take back its own orphaned trailer.

## The refinery and storage

The refinery is the first building (`BuildingType`, `data/buildings/`;
`SimBuilding` in the simulation). It covers 3 by 2 cells. Units cannot enter
the cells a building covers and plan their paths around it. Buildings stand
only on ground that can be built on (stone in the forest, rock in the desert).

- A truck beside a refinery of its own side hands over its cargo. The
  Orichalcum goes into its side's **store**.
- **Storage has a limit**: the sum of the `storage` of a side's buildings. One
  refinery stores 800.
- **When the store is full the harvester waits** beside the refinery with
  what it still carries, and unloads as soon as there is room. Nothing is
  lost.

In M4 the refinery is put on the map by the mission, on the nearest ground to
the player's start that it fits on. Placing buildings, their cost, their
health and attacking them come with M5. Nothing can be bought yet, so the
store only fills.

## Controls

| Input | What it does |
| --- | --- |
| Right click on the Orichalcum rock, with harvesters selected | They start harvesting it |
| Right click on your refinery, with harvesters selected | They unload there now, then go back to work |
| Right click anywhere else, S | Move and stop, as for any unit (a robot hitches up first) |
| Right click on an orphaned enemy trailer | The selected units walk up to it and take its Orichalcum |

Other units in the same selection walk to the spot that was clicked. The rock
and the refinery must be on ground the player has explored. A harvester sent
with A (attack-move) or at an enemy just moves.

## What the player sees

- **The top bar** shows the store: `Orichalcum 350 / 800`, with `(full)` when
  it is. It appears as soon as the player has storage, so Mission 1 does not
  show it.
- **The sidebar** shows, for a selected harvester, its robot's attack and
  armour, its cargo (and pack) and what it is doing; for the cell under the
  mouse, the Orichalcum in a rock cell and in the whole rock, the refinery's
  storage, or a trailer and its cargo.
- A digging robot swings its arms and chips of ore fly off the rock. Ore
  flies from its pack into the trailer, and from an unloading truck into the
  refinery. A guarding robot swings at its enemy.

## The practice missions

M4's playable results are **practice missions**, started from the title
screen or with `-- --map=<name>`. They are not part of the campaign, and
Mission 1 is unchanged: it has no base and no harvesters.

| | Harvest trial | Raid trial |
| --- | --- | --- |
| Start with | `harvest-forest`, `harvest-desert` | `raid-forest`, `raid-desert` |
| Files | `harvest_trial_blue.tres`, `harvest_trial_red.tres` | `raid_trial_blue.tres`, `raid_trial_red.tres` |
| Player | A refinery and two harvesters | The same, and three soldiers |
| Opponent | None | Three soldiers, who set off after 45 seconds |

Blue plays on the forest map, Red on the desert map. A practice mission
(`practice` in `MissionDef`) has no control ring and no way to win or lose;
Esc leaves it. The rock is on the player's map from the start.

- **Harvest trial.** The hints teach two things: select a harvester, and
  right-click the rock. After that the harvesters work alone. In a little
  over two minutes the store is full at 800 and both harvesters wait at the
  refinery with a full trailer.
- **Raid trial.** The raiders (`Raiders`, `scripts/sim/raiders.gd`, a short
  script like Mission 1's opponent) go for the harvesters, and walk up to the
  trailer of any they destroy. Left alone, they destroy one harvester and
  take its cargo, and the second harvester finishes them. With the player's
  soldiers sent to help at the first blow, nobody is lost.

## Provisional choices

| What | Value | Where |
| --- | --- | --- |
| Orichalcum in one rock cell | 50 | `data/terrain/*_ore_rock.tres` |
| Harvester: health, sight | 180, 4 cells | `data/units/*_harvester.tres` |
| Truck: speed | 3.5 cells/s | same |
| Robot: speed | 2 cells/s | same |
| Trailer and pack | 100 and 25 | same |
| Robot: digs, fills the trailer | 20 a second, 50 a second | same |
| Truck: unloads | 50 a second | same |
| Changing shape | 1 s | same |
| Robot: armour, attack | 70%, 10 every 1.5 s, range 1 | same |
| Robot: notices enemies | within 4 cells | same (`acquire_range`) |
| Back to work after an attack | 2 s after the last enemy has gone | `SimWorld.CALM_TICKS` |
| Furthest the robot carries | 3 cells, then the trailer is moved | `SimWorld.REPARK_CELLS` |
| Refinery: size, storage | 3 by 2 cells, 800 | `data/buildings/*_refinery.tres` |
| A full store | the harvester waits | decided |
| Spent rock | stays impassable | `scripts/sim/sim_world.gd` |
| Taking an orphaned trailer | standing next to it is enough | same |
| The raid | three raiders after 45 s | `data/missions/raid_trial_*.tres` |

## The art

The truck is the one from the approved mockups, with the team colour added to
the rims of its end boards. Its robot shape, the trailer on its own and the
refinery are new, in the same manner. `tools/render_units.py` renders them.
`tools/make_units.py` packs the harvester's sheet (8 facings by 6 rows: empty
truck, loaded truck, halfway, the two halves of the robot's swing, the robot
standing) and the trailer's (8 facings by 2 rows: empty, loaded).
`tools/make_buildings.py` puts the refinery on its foundation of concrete
plates. The trailer is rendered where it sits in the truck, so that the two
pictures line up when the robot steps off. The spent rock is
`ore_rock_spent.png`, made by `tools/make_tiles.py` with the same outline as
the rock.

## Left out of M4

- Spending Orichalcum, and placing, damaging or destroying buildings (M5).
- A harvester or refinery for the opponent (M6).
- Taking back one's own orphaned trailer, and a proper way to carry stolen
  Orichalcum home.
- Storage buildings other than the refinery.
- Selecting buildings.
- Sound.
