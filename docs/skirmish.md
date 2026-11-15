# Balance: the enemy AI and the skirmish

What milestone M6 built: buildings that can be attacked and destroyed, the
workshop's light tank, the computer opponent, and the skirmish, a full game
against the computer from the first building to a win or a loss. How bases
are built is in [base.md](base.md); how Orichalcum is mined in
[economy.md](economy.md); how units fight in [combat.md](combat.md).

**Every name and number here is provisional.** The provisional choices are
collected in one table near the end.

## Destroying buildings

Every building now has health (`max_health` in its `BuildingType`).

| Building | Health |
| --- | --- |
| Headquarters | 1200 |
| Refinery, Workshop | 900 |
| Barracks | 700 |
| Generator | 600 |

- **Attacking.** A right click on an enemy building sends the selected units
  to attack it (harvesters stay out of it). Attack-move (F) and a left click
  on an enemy building does the same. A unit goes up to the building and hits
  the cell of it nearest to itself.
- **On their own.** A fighter that is standing idle or on attack-move goes for
  an enemy building it notices, but **units come first**: as soon as an enemy
  unit comes near, it turns on that unit and goes back to the building once
  the unit is dealt with. Troops on attack-move therefore wreck everything
  they pass in an enemy base.
- **Defenders.** When a building is hit, idle fighters of its side within six
  cells go after the attacker, as they do for a comrade that is hit.
- **Destroyed.** At 0 health a building is gone. Its cells can be walked
  on again and units plan their paths through them. What its side has in
  store beyond the storage it has left is lost (losing the refinery loses
  most of the store). A queue that has no building left to work it is emptied
  and what was paid for the item being built comes back; losing the
  headquarters stops all construction for good, since it cannot be rebuilt.
- **On screen.** A damaged building shows a health bar above it, flashes when
  it is hit, and burns once it is below half health (two fires below a
  quarter). A destroyed building goes up in an explosion and leaves a scorch
  mark for the rest of the mission. The sidebar shows a building's health.

Buildings could not be repaired in M6. Since M7 they can, for Orichalcum,
by the player and by the computer: see [heroes.md](heroes.md). They cannot
be sold.

## The light tank

The workshop now builds a light tank as well as harvesters. It is the first
unit that fights at a distance.

| | Light tank | (Infantry, for comparison) |
| --- | --- | --- |
| Cost, build time | 300, 14 s | 60, 6 s |
| Health | 240 | 60 |
| Speed | 3 cells a second | 2.5 |
| Sight, notices enemies at | 5 cells, 5 cells | 4, 4 |
| Attack | 30 damage, range 3, every 2 s | 12, range 1, every second |

Blue's and Red's tanks differ only in colour. It shoots without a visible
shell (the hit spark is drawn on the target, as for every hit). The sprite
sheet, `assets/sprites/units/tank_<team>.png`, is rendered by
`tools/render_units.py` (`light_tank`) and packed by `tools/make_units.py`:
8 facings by 3 poses (standing, and the two halves of a turn of the tracks),
36 by 36 pixels.

## The computer opponent

`ComputerOpponent` (`scripts/sim/computer_opponent.gd`) plays one side.

**It plays by the same rules as the player.** It has no money, units or
buildings of its own beyond what the mission gives each side. It queues what
it wants in its side's build queues and pays for it bit by bit out of its own
store; it waits when the store is empty; it places finished buildings with
the same check as the player (free, explored building ground); it builds at
half speed when short of power; and it moves and fights with the same orders
the player gives (attack-move, attack, harvest). What it knows that a player
would not is listed under "Simplifications" below.

It looks at the world once a second and works through these, in order:

1. **Base.** When nothing is being constructed it queues the next building
   on its list: a generator, a barracks, a workshop, a second generator, a
   second refinery (only once its store is three-quarters full), a second
   barracks, a third generator. Before anything that would leave it short of
   power, or whenever it is short, it builds a generator first. A finished
   building is placed on the free site nearest to its headquarters (within 14
   cells), keeping clear of the two rows in front of every building, where
   units come out and harvesters unload, and keeping a cell of room around
   each building where it can. A building that fits nowhere is cancelled and
   paid back.
2. **Economy.** It keeps two harvesters. Idle harvesters are sent to the
   rock. While it has a workshop and fewer than two harvesters, it saves for
   a harvester and queues nothing else, so that losing its harvesters does
   not starve it for good.
3. **Army.** It trains troops at its barracks and tanks at its workshop, one
   at a time each, as long as it has fewer than 16 fighters and either has
   150 in store or is not constructing anything.
4. **Defence.** An enemy unit within 9 cells of one of its buildings, or an
   enemy fighter within 6 cells of one of its harvesters or trailers, is a
   threat. Every soldier at home (not out on an attack) is sent at the
   threat nearest to its headquarters.
5. **Attack.** Soldiers at home gather on a rally cell 6 cells from its
   headquarters, towards the middle of the map. After 2 minutes 30 seconds,
   once it has 5 soldiers at home, they set off together with attack-move for the
   nearest enemy building it has seen, or the enemy's start if it has seen
   none. Each wave is 2 larger than the last, up to 12. Soldiers of a wave
   that have nothing left to fight move on to the next target.

It never uses a hero's ability (the skirmish has no heroes). Since M7 it
repairs damaged buildings (see [heroes.md](heroes.md)).

### Simplifications

- It knows where the enemy started (the other start position of the map), as
  a player who knows the map does.
- Once it has explored the enemy's start and sees nothing more of the enemy,
  it is told where the enemy's remaining buildings and units are, so that a
  game always comes to an end.
- It has one level of difficulty.

## The skirmish

M6's playable result is a skirmish against the computer, started from the
title screen ("Skirmish") or with `-- --map=skirmish-forest` or
`--map=skirmish-desert`.

| | As Blue | As Red |
| --- | --- | --- |
| File | `skirmish_blue.tres` | `skirmish_red.tres` |
| Map | Forest | Desert |
| Each side starts with | Headquarters, refinery, one harvester, three soldiers, 600 Orichalcum | The same |
| The computer plays | Red, from the other corner | Blue, from the other corner |

- Both sides know where the Orichalcum rock is; neither knows where the other
  is. The rock is eight times as rich as usual (400 a cell), and it is the
  only one, so the two sides compete for it.
- **Winning and losing.** A side that has no buildings and no troops left
  has lost. Harvesters do not count. There is no control area to hold.
- The top bar shows the sides and how many buildings and troops each has
  (for example "Blue 5 / 4   Red 6 / 0": buildings / troops), the store, the
  power and the time. The sidebar has the build menu, as in the base trial.
- The hints teach what the base trial does (sending the harvester out,
  building and placing, training), then how to attack the enemy's base.
- The result screen gives the time and the units and buildings lost and
  destroyed on each side.

A player who does nothing is beaten in about five and a half minutes. Two
computer opponents playing each other finish a game in ten to fifteen
minutes on either map; that is checked by the headless tests.

## Provisional choices

| What | Value | Where |
| --- | --- | --- |
| Building health | see the table above | `data/buildings/*.tres` |
| Units prefer units to buildings | always, except with an order to attack the building | `SimWorld._pick_target` |
| Store beyond the remaining storage when a building is lost | lost | `SimWorld.destroy_building` |
| A queue whose building is gone | emptied, the item being built paid back | `Production.drop_orphaned_lines` |
| Light tank: name, cost, numbers | see the table above | `data/units/*_tank.tres` |
| The computer's building list | see "Base" above | `ComputerOpponent.BASE_PLAN` |
| Harvesters it keeps, army limit, reserve | 2, 16, 150 | `ComputerOpponent` |
| First attack, first wave, growth, largest wave | after 150 s, 5, +2, 12 | same |
| Defence ranges | 9 cells from a building, 6 from a harvester | same |
| How far from its headquarters it builds | 14 cells | same |
| Skirmish start | headquarters, refinery, harvester, 3 soldiers, 600 | `data/missions/skirmish_*.tres` |
| Richness of the rock in a skirmish | eight times | same |
| Losing a skirmish | no buildings and no troops left (harvesters do not count) | `Mission.is_beaten` |

## Left out of M6

- Repairing and selling buildings, and rebuilding a headquarters. (Repairing
  came in M7.)
- Difficulty levels, and a choice of map, side or starting money.
- Heroes in the skirmish, and the computer using hero abilities.
- Fog of war over ground that has been explored but is no longer watched:
  once explored, ground stays visible, enemy units on it included.
- Shells and muzzle flashes for the tank, and sound.
