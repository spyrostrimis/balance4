# Balance: units, orders and shroud

How units are defined, how the simulation moves them, and how the player
commands them. This is what milestone M2 built.

## Unit types

Each kind of unit is one small file in `data/units/` (a `UnitType` resource):

| Field | Meaning |
| --- | --- |
| `id` | Internal name, e.g. `blue_infantry` |
| `display_name`, `role` | What the sidebar shows, e.g. "Guardsman", "Blue Infantry" |
| `max_health` | Health when undamaged |
| `speed` | Cells per second |
| `sight` | How many cells around itself the unit reveals |
| `minimap_color` | Colour of its dot on the minimap |
| `sprites`, `sprite_size`, `sprite_anchor` | Its sprite sheet and where its feet are in each sprite |

The two unit types so far (names and numbers are provisional):

| Unit | Side | Health | Speed | Sight |
| --- | --- | --- | --- | --- |
| Guardsman | Blue infantry | 60 | 2.5 cells/s | 4 cells |
| Legionary | Red infantry | 60 | 2.5 cells/s | 4 cells |

On the forest map the player leads five Guardsmen; on the desert map, five
Legionaries. Each map lists its start positions.

## The simulation

`SimWorld` (`scripts/sim/sim_world.gd`) holds the map and the units and applies
the rules. It knows nothing about the screen, the mouse or the clock.

- **Fixed tick.** The world advances in steps of 1/20 of a second. The screen
  redraws as often as it can and places each unit between its last and next
  position, so movement looks smooth, but the rules only ever run on ticks. The
  same orders therefore always give the same result.
- **One unit per cell.** A unit occupies exactly one cell. When it starts a
  step it immediately occupies the cell it is walking into, so no two units
  ever aim for the same cell.
- **Eight directions.** Units step to any of the eight neighbouring cells. A
  diagonal step takes 1.4 times as long, and is only allowed if both cells
  beside the diagonal are passable (no cutting corners around water).

## Move orders and pathfinding

`order_move(units, target)` sends units to a cell.

- Each unit gets its **own destination**: the unit nearest the target goes to
  the target itself and the others take the nearest free cells around it.
- If the target cannot be reached (water, or land cut off by water), the units
  go to the nearest cell that can.
- Paths are found with Godot's `AStarGrid2D` over the terrain.
- **Other units:** a unit standing still is treated as an obstacle and walked
  around. A unit that is itself on the move is waited for briefly; if it stays
  in the way the walker plans a detour. Two units of the same side walking
  straight into each other in a narrow passage change places. A unit that is
  blocked for good gives up and stops rather than trying for ever.
- If another unit has settled on a unit's destination, it picks the nearest
  free cell instead.
- A new order replaces the old one. The unit finishes the step it is in first.

## Shroud

Each side has a `Shroud`: the set of cells it has explored. Everything else is
hidden under black.

- A unit reveals a round area of `sight` cells around itself when it appears
  and every time it steps into a new cell.
- Explored cells stay visible for good. There is no fog that closes again
  behind the units; that is the Dune II rule.
- The minimap shows only explored cells. Units of other sides would be drawn
  only on explored cells.
- The edge of the explored area is ragged, not square: it uses the same
  half-cell-shifted border tiles as the terrain (see [terrain.md](terrain.md)).

## Selecting and commanding

| Input | What it does |
| --- | --- |
| Left click | Select the unit under the mouse; click empty ground to deselect |
| Left drag | Select every unit in the box |
| Shift + click or drag | Add to the selection (Shift + click on a selected unit removes it) |
| Right click | Send the selected units there |
| Ctrl + 1 to 9 | Store the selection as a numbered group |
| 1 to 9 | Select that group; press twice quickly to jump the camera to it |

A selected unit shows a ring at its feet and its health bar. The sidebar shows
the selected unit's name, role and health, or a count when several are selected.
A right click leaves a brief marker on the ground.

Attack-move comes with combat in M3.

## How units are drawn

`UnitsView` (`scripts/ui/units_view.gd`) draws every unit each frame, the ones
further down the screen last so they overlap the ones behind them. A unit's
sprite sheet has eight columns (the direction it faces) and three rows
(standing, and the two halves of a walking step).

## Where the sprites come from

1. `tools/render_units.py` runs in Blender. It builds each unit from simple
   shapes, and renders it from eight sides in three poses, plus a shadow pass,
   at four times the final size. The models and lighting are those of the
   approved mockups.
2. `tools/make_units.py` shrinks the renders, reduces them to 20 colours, adds
   per-pixel grit like the terrain, and gives each sprite a soft dark rim and a
   tight contact shadow so it sits on the ground. It packs the result into one
   sheet per unit in `assets/sprites/units/`.

The raw renders go to `tools/_raw/`, which is scratch space and is not kept in
git.
