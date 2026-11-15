# Balance: base building and production

How Orichalcum is spent: constructing buildings, placing them, producing
units, and power. This is what milestone M5 built. Where the Orichalcum comes
from is in [economy.md](economy.md).

**Every name and number here is provisional.** The provisional choices are
collected in one table near the end.

## The buildings

Buildings are data: one `BuildingType` file each in `data/buildings/`, for
Blue and for Red. The two sides' buildings differ only in colour so far.

| Building | Size | Cost | Build time | Power | What it does |
| --- | --- | --- | --- | --- | --- |
| Headquarters | 2 by 2 | not for sale | | makes 30 | Constructs the other buildings. Stores 200. |
| Generator | 2 by 2 | 150 | 8 s | makes 100 | Makes power. |
| Refinery | 3 by 2 | 400 | 15 s | uses 30 | Harvesters unload here. Stores 800. |
| Barracks | 2 by 2 | 200 | 10 s | uses 20 | Trains infantry (60, 6 s). |
| Workshop | 3 by 2 | 400 | 15 s | uses 40 | Builds harvesters (300, 12 s) and, since M6, light tanks (300, 14 s). |

A building type lists what it `builds` (which makes it a headquarters) and
what it `produces` (which makes it a production building). Unit types carry
their own `cost` and `build_seconds`.

## Build queues

A side has one queue for buildings, worked by its headquarters, and one
queue for each kind of production building it owns, worked by the first
building of that kind. The rules are in `Production`
(`scripts/sim/production.gd`); a queue is a `BuildLine`.

- A queue holds up to five items. The first is being built; the others wait.
- **An item is paid for bit by bit while it is built**, not when it is
  queued. If the store runs dry the work stops and carries on when more
  Orichalcum comes in.
- **Cancel** takes the last item out of a queue. Whatever was paid for it
  comes back.
- The queues of a side all work at the same time.
- More buildings of one kind do not speed its queue up, and units always come
  out of the first one.

## Placing a building

A finished building waits in its queue, and holds the queue up, until the
player puts it on the map.

- Buildings stand **only on building ground**: stone in the forest, rock in
  the desert. Every cell the building covers must be building ground that the
  player has explored, with no building, unit or trailer on it.
- Buildings may touch each other, and need not be near the headquarters.
- A placed building works at once. Units plan their paths around it.

## Producing units

A finished unit comes out on the free cell nearest to the front (the bottom
edge) of its production building. If there is no free cell within four cells
of it, the unit waits inside until there is. A new harvester sets off for the
nearest Orichalcum rock on its own.

## Power

Every building makes or uses power (see the table). A side that **uses more
power than it makes is low on power, and all its queues build at half
speed**. Nothing else changes, and nothing costs more.

## The build menu

In a mission with a base the sidebar shows the build menu (`BuildPanel`,
`scripts/ui/build_panel.gd`) in place of the objective box and the list of
controls.

- **Tabs.** "Build" for buildings, and one tab for each kind of production
  building the player owns, named after it.
- **The grid** shows what the open tab can build, each with its picture, name
  and cost. A click adds one to that tab's queue.
- **The queue box** names what is being built and how many wait behind it,
  with a progress bar and a line that says how far it is or what it is
  waiting for (Orichalcum, room to come out, or to be placed). Cancel takes
  the last item out.
- **Placing.** When a building is ready the queue box turns into a button,
  "Place the Generator". Click it (or the building in the grid), then the
  map: the building is shown faintly under the mouse, with a green or red
  square on every cell it would cover. A left click on a spot where every
  square is green places it. A right click or Esc leaves placing; the
  building stays ready.
- **Power** is shown as "Power used / made" with a bar under the queue box,
  and again in the top bar. It turns red and says LOW when more is used than
  made.

The sidebar describes the building under the mouse: its storage, the power it
makes or uses, and what it constructs or produces.

## The base trial

M5's playable result is a third practice mission, started from the title
screen ("Base trial") or with `-- --map=base-forest` or `--map=base-desert`.

| | As Blue | As Red |
| --- | --- | --- |
| File | `base_trial_blue.tres` | `base_trial_red.tres` |
| Map | Forest | Desert |
| Start | Headquarters, refinery, one harvester, 500 Orichalcum | The same |
| Opponent | None | None |

The rock in this mission is three times as rich as usual (150 a cell), so
that there is enough to build a base with. The hints lead through sending
the harvester out, building and placing a generator, and building a barracks
and training a soldier. There is nothing to win or lose: it has no opponent.
The game against an opponent with a base of its own is the skirmish, added
in M6 (see [skirmish.md](skirmish.md)).

## Provisional choices

| What | Value | Where |
| --- | --- | --- |
| Building and unit costs, build times, power | see the table above | `data/buildings/*.tres`, `data/units/*.tres` |
| Names: Headquarters, Generator, Barracks, Workshop | | same |
| Paying | bit by bit while building | `scripts/sim/production.gd` |
| Queue length | 5 | `Production.QUEUE_LIMIT` |
| Low power | all queues at half speed | `Production.tick` |
| Where buildings may stand | any free, explored building ground | `Production.can_place` |
| Several production buildings of one kind | one queue; units come out of the first | `Production.builder` |
| A new harvester | goes to the nearest rock on its own | `Production._advance` |
| The base trial: start, richness of the rock | 500 Orichalcum, three times | `data/missions/base_trial_*.tres` |

## The art

The four new buildings are rendered by `tools/render_units.py` and put on
their foundations by `tools/make_buildings.py`, like the refinery: flat, low,
grey, with the team colour on roofs, bands and flags. The headquarters is a
square keep with corner turrets; the generator a round furnace whose core
glows with Orichalcum; the barracks a hall with a drill yard; the workshop a
hall with a wide door, an apron and a crane. The build menu itself is
functional only, like the rest of the HUD.

## Left out of M5

- Attacking, damaging, repairing and selling buildings. Buildings have no
  health yet; that comes with the opponent in M6. (Done in M6, apart from
  repairing and selling: see [skirmish.md](skirmish.md).)
- Combat vehicles. The workshop builds only harvesters so far. (M6 added the
  light tank.)
- Rally points, and choosing which building a unit comes out of.
- Requirements between buildings (everything can be built from the start).
- Sound.
