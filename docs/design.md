# Balance: design

This document records what has been decided about the game so far. It does not
add anything beyond those decisions. Where something is undecided it says so, and
the open questions are collected at the end.

**All names are provisional**, including "Balance", "Orichalcum", the faction
names, "Peacebringer", "Encouragement", "Dominion" and "The First Claim". Colours
(Blue, Red, Green) stand in for faction names that do not exist yet.

## What the game is

Balance is an original single-player 2D real-time strategy game. It is a tribute
to Dune II in gameplay and in visual character. It never uses Dune II's names,
factions, art, music or levels; everything that ships is original.

Tagline: every faction claims to seek Balance, but each defines it differently.

## Design pillars

- **Sprite-based, orthogonal, grid-based.** The battlefield is a 2D grid seen
  from almost directly above. Units and buildings are sprites.
- **Small armies.** A force is a handful of units, not a swarm. Losing a unit
  hurts. Repairing and retreating are real decisions, not afterthoughts.
- **One scarce resource.** The whole economy runs on Orichalcum (see below).
- **Modern controls on a classic design.** Box selection, control groups and
  attack-move, rather than the one-unit-at-a-time controls of early 1990s
  strategy games.
- **Single-player only.** Multiplayer is out of scope.

## Orichalcum

Orichalcum (provisional name) is the game's only resource. It is scarce and is
mined from small rock formations.

The harvester:

1. travels to a deposit as a truck,
2. transforms into a humanoid robot at the deposit,
3. extracts Orichalcum,
4. transforms back into a truck,
5. returns to a refinery to unload.

## Factions

| Faction (provisional) | Who they are | How they fight |
| --- | --- | --- |
| **Blue** | Freedom; a democratic coalition | Healing and repair, coordination |
| **Red** | Order; centralised command | Offence, swift strikes |
| **Green** | Opportunists: merchants and local lords | Ambush, stealth |
| **Palatinate / Clergy** | An ancient, covert religious order | Unpredictable |

Blue and Red each get a full campaign.

## Backstory

A just king, the Peacebringer, disbanded most of his army. A young lieutenant led
a coup and killed him. The king's son, the prince, was 17; he escaped with a
woman of the Royal Guard.

The game begins ten years later.

| Character | Role now | Age now |
| --- | --- | --- |
| The prince | Leader of Blue | 27 |
| The coup leader (the former lieutenant) | Leader of Red | 40 |
| The Royal Guard veteran who escaped with the prince | Blue's field commander | about 37 |

None of these characters has a name yet.

## Heroes

Heroes are special units with active abilities (the player triggers them) and
passive abilities (always on).

| Hero | Abilities decided so far |
| --- | --- |
| Blue leader | An area heal/repair pulse, plus "Encouragement" |
| Blue field commander | A single-target heal/repair |
| Red leader | "Dominion" (a name only; what it does is undecided) |

## Mission 1: "The First Claim"

- **Setting:** forest when playing Blue, desert when playing Red.
- **Forces:** four troops per side, plus each side's field commander.
- **Objective:** both sides contest one Orichalcum rock in the centre of the map.
- **Winning:** hold uncontested control of the area near the rock for a short
  time, or eliminate all resistance.
- **What it teaches:** selecting units, moving, attacking, using the commander's
  ability, and how control points work.
- **What it leaves out:** there is no base building in this mission.

## Planned for later

These are part of the game but come after Mission 1 is playable:

- Wandering creature hazards
- Base building
- The refinery and the Orichalcum economy
- Unit production

## Technical decisions

- Engine: Godot 4.7.2, code in GDScript.
- The simulation runs on a fixed tick, on a grid, separate from drawing.
- Terrain is drawn with `TileMapLayer`.
- Pathfinding uses `AStarGrid2D`.
- Units and buildings are data-driven: each is defined in a Godot `Resource`
  file, not hard-coded.
- Controls: box select, control groups, attack-move.
- Tests run headless from the command line.
- Sprites are produced by Blender renders and Python scripts.

## Open questions

Nothing in this section has been decided. Do not treat any guess as canon.

- **OPEN: How did the coup beat the automated orbital defences?** This is a
  deliberate, unanswered lore question.
- **OPEN: What does the Red leader's "Dominion" do?**
- **OPEN: What does "Encouragement" do exactly, and is it active or passive?**
- **OPEN: Who is Red's field commander?** Mission 1 gives each side a field
  commander, but only Blue's has been described.
- **OPEN: Final names** for the game, the resource, the factions, the characters,
  the abilities and the missions.
- **OPEN: How long is the "short time"** a side must hold the control point in
  Mission 1, and how large is the area "near" the rock?
- **OPEN: What the Palatinate / Clergy wants** and how its unpredictability shows
  up in play.
- **OPEN: What the wandering creatures are** and how they behave.
- **OPEN: Who can cross which terrain?** For now the terrain data says only
  water is impassable and only stone (forest maps) and rock (desert maps) can be
  built on. Whether forest should stop vehicles, slow infantry or hide units,
  and whether dunes should slow anything, is undecided.
- **OPEN: Are the two M1 maps the Mission 1 maps?** They are laid out like the
  mockups (a central clearing with a track to two opposite corners) but were
  made to test the map code, not designed for the mission.
