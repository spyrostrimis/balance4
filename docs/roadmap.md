# Balance: roadmap

Each milestone ends in something that can be played or run, and in a push to the
GitHub repository. A milestone is done only when everything in its "Done means"
list is true.

Two rules apply to every milestone:

- The project opens and runs with no errors.
- The headless tests pass.

The order of the milestones and the headline content of each are agreed. The
detailed "Done means" lists are a working draft: those for M1 to M6 follow the
agreed content closely, and those for **M7 to M10 are a first outline** that will
be firmed up as those milestones get closer.

## M0 Setup (done)

Get a working, empty project into version control.

Done means:

- The git repository exists with `main` as its branch and is pushed to GitHub.
- A Godot 4.7.2 project opens and runs a placeholder title screen with no errors.
- The game renders at 960x540 with whole-number scaling and sharp pixels.
- The folder layout is in place and explained in the README.
- The README and the design, visual style and roadmap documents are written.
- The style mockups are in the repository.

## M1 Map (done)

A map you can look around.

Done means:

- A map is drawn from terrain data using `TileMapLayer`, with the forest terrain
  types (grass, dirt, stone, forest, water) and the desert ones (sand, dunes,
  rock, hardpan), in the approved style.
- Terrain types are defined as data, including which ones can be walked on and
  built on.
- The camera scrolls with the keyboard and at the screen edges and stops at the
  map border.
- A minimap shows the whole map and the current view, and clicking it moves the
  camera.
- Playable result: open the game and scroll around one forest map and one desert
  map.

What was built is described in [terrain.md](terrain.md). Left for later
milestones: the top bar, the hero portrait and the rest of the sidebar (only the
minimap is in place); the Orichalcum rock in the middle of the maps (added in
M3, mined from M4); shroud (M2).

## M2 Units (done)

Units you can command.

Done means:

- Units exist on the grid and are simulated on a fixed tick.
- Units are defined as data (`Resource` files).
- Selection works: click, box select, control groups.
- Move orders work, with pathfinding (`AStarGrid2D`) around impassable terrain
  and other units.
- Shroud hides unexplored parts of the map and is lifted by units.
- Playable result: move a small squad around a map and explore it.

What was built is described in [units.md](units.md). Left for later milestones:
attack-move and anything to fight (M3), vehicles and the harvester (M4), and
rules for which units can cross which terrain (decided and applied in M3).

## M3 Combat: a playable Mission 1 (done)

Fighting, and the first real mission.

Done means:

- Units can attack, take damage and die. Attack-move works.
- The field commander's ability works.
- The control-point rule works: a side wins by holding uncontested control near
  the point for a short time.
- Eliminating all resistance also wins.
- Playable result: Mission 1, "The First Claim" (provisional name), can be played
  from start to a win or a loss, as Blue on the forest map and as Red on the
  desert map, against an opponent that at least moves and fights. There is no
  base building in it.

What was built is described in [combat.md](combat.md). M3 also applied two
design decisions: one unit per cell is now a rule, and units walk on flat
ground only (trees, water and the Orichalcum rock block them). Left for later
milestones: armour, a hold-position order, ranged weapons with projectiles,
the leaders and passive abilities, a briefing, a pause menu and sound (M7 and
later); the rock as a deposit that can be mined (M4); an opponent that thinks
rather than follows a script (M6). Red's field commander is a placeholder
until that character is designed, and every combat number is provisional.

## M4 Economy (done)

Orichalcum flows.

Done means:

- Orichalcum deposits exist on the map and run out.
- The harvester drives to a deposit as a truck, transforms into a robot,
  extracts, transforms back and returns to a refinery.
- The refinery turns deliveries into stored Orichalcum, and storage has a limit.
- The HUD shows the current amount.
- Playable result: a harvester earns Orichalcum on its own once sent to a
  deposit.

What was built is described in [economy.md](economy.md). The playable result
is a practice mission, the "Harvest trial": a refinery, two harvesters and no
opponent, on either map. Mission 1 is unchanged. M4 also brought the first
building (the refinery, put on the map by the mission). A harvester waits at
a full store with its load; mined-out rock stays impassable (provisional).

After M4 was first played the harvester became a truck in two parts: the cab
is the robot, and the trailer stays where the truck stopped and is filled by
the robot. The robot guards its trailer against enemies, and the trailer of a
destroyed harvester can be taken by the enemy. A second practice mission, the
"Raid trial", shows this: the same base, three soldiers and three raiders. Left for later milestones: spending Orichalcum, and placing and
placing buildings (M5); destroying buildings, and an opponent that harvests
(M6).

## M5 Base building and production

Spend what you earn.

Done means:

- Buildings can be placed, only on rock ground.
- Buildings are defined as data and cost Orichalcum.
- Production buildings build units through a build queue.
- The sidebar build grid, preview and queue work.
- Power is tracked and shown on the power bar.
- Playable result: start with a small base, harvest, build more buildings and
  produce units.

What was built is described in [base.md](base.md). The playable result is a
third practice mission, the "Base trial": a headquarters, a refinery, one
harvester and 500 Orichalcum, on either map. M5 brought four more buildings
(headquarters, generator, barracks, workshop), build queues that are paid for
bit by bit, placing with a preview, and power: a side that uses more than it
makes builds at half speed. Left for M6, because they need an opponent to
mean anything: buildings with health that can be attacked and destroyed, and
combat vehicles for the workshop.

## M6 Enemy AI

Someone to play against.

Done means:

- A computer opponent harvests, builds a base, produces units, attacks and
  defends.
- It plays by the same rules as the player.
- Playable result: a full skirmish against the computer, from first building to a
  win or a loss.

## M7 Vertical slice (outline)

One mission at the quality the whole game should reach.

Done means:

- One complete mission with final-quality art, sound, HUD and briefing.
- It includes heroes with active and passive abilities, and base building.
- Someone who has never seen the game can start it, play it and finish it
  without help.

## M8 Content (outline)

Everything the campaigns need.

Done means:

- The full set of units and buildings for Blue and Red exists and is playable.
- Green and the Palatinate / Clergy exist as far as the campaigns need them.
- Wandering creature hazards exist.
- All terrain sets needed by the campaigns exist.

## M9 Campaign (outline)

The story, start to finish.

Done means:

- The Blue campaign and the Red campaign can each be played from the first
  mission to the last.
- Missions have briefings and tell the story.
- Progress is saved between missions.

## M10 Polish (outline)

Make it good.

Done means:

- The HUD art is revisited and final.
- Audio is complete: sound effects and music, all original.
- Missions and units are balanced and the known bugs are fixed.
- There is an options menu, and a build that runs on a clean Windows machine.

## Out of scope

- Multiplayer.
