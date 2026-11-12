# Balance

Balance is an original single-player 2D real-time strategy game. It is a tribute
to Dune II in how it plays and how it looks: a flat, near top-down battlefield, a
grid, one scarce resource, small armies. Every name, faction, piece of art, piece
of music and level in this repository is original; nothing is taken from Dune II.

> Every faction claims to seek Balance, but each defines it differently.

**Status:** milestone M0 (Setup) is done. The project opens and runs a placeholder
title screen. There is no gameplay yet. See [docs/roadmap.md](docs/roadmap.md).

Most names in the game ("Balance", "Orichalcum", the faction names, the mission
name) are provisional and may change.

## Open and run

You need Godot 4.7.2 (standard build, not .NET).

- **Editor:** start Godot, choose *Import*, pick `project.godot` in this folder,
  then press F5 to run.
- **Command line** (from the repo root, with the Godot executable on your path
  or written out in full):

  ```bash
  godot --path .
  ```

- **Headless check** (loads the project and exits; no window):

  ```bash
  godot --headless --path . --import
  ```

  ```bash
  godot --headless --path . --script res://tests/smoke_test.gd
  ```

  The smoke test prints `SMOKE TEST PASSED` and exits with code 0 when the main
  scene loads.

The first time the project is opened Godot creates a `.godot/` cache folder. It
is ignored by git.

The game renders at 960x540 and is scaled up by whole numbers only (x2 fills a
1920x1080 window), so pixels stay square and sharp.

## Tools

| Tool | Version | Used for |
| --- | --- | --- |
| Godot | 4.7.2 stable | Engine and editor; game code is GDScript |
| Blender | 5.2 | Rendering unit and building sprites |
| Krita | any recent | Hand-painting and touching up art |
| Python | 3.14 with Pillow and numpy | Asset pipeline scripts and the mockup generators |
| git, GitHub CLI | any recent | Version control |

## Folders

| Folder | What it holds |
| --- | --- |
| `scenes/` | Godot scenes (`.tscn`). `main.tscn` is the scene the game starts in. |
| `scripts/` | GDScript code. |
| `scripts/sim/` | The game simulation: grid, units, orders, combat, economy. No drawing or input code. |
| `scripts/ui/` | Screens, HUD, input handling and anything else the player sees or clicks. |
| `data/` | Unit, building and terrain definitions, stored as Godot `Resource` files. |
| `assets/sprites/` | Unit, building and effect sprites. |
| `assets/tiles/` | Terrain tiles. |
| `assets/ui/` | HUD and menu art, fonts. |
| `assets/audio/` | Sound effects and music. |
| `tools/` | Asset pipeline scripts (Blender and Python) that produce the files in `assets/`. Not loaded by Godot. |
| `tests/` | Headless tests, run from the command line. |
| `docs/` | Design, visual style and roadmap documents. Not loaded by Godot. |
| `mockups/` | Style mockups and the scripts that generated them. Reference material only, not game code or game art. Not loaded by Godot. |

`docs/`, `tools/` and `mockups/` each contain an empty `.gdignore` file, which
tells Godot to skip the folder. Empty folders hold a `.gitkeep` file so git keeps
them; delete it once the folder has real content.

## Documents

- [docs/design.md](docs/design.md): design pillars, factions, backstory, heroes, Mission 1, open questions.
- [docs/visual-style.md](docs/visual-style.md): the approved look, with reference mockups.
- [docs/roadmap.md](docs/roadmap.md): milestones M0 to M10 and what "done" means for each.

## Roadmap in short

Each milestone ends in something playable and a push to this repository.

| Milestone | What it adds |
| --- | --- |
| M0 Setup | Repository, Godot project, docs. **Done.** |
| M1 Map | Terrain, camera scrolling, minimap. |
| M2 Units | Selection, orders, pathfinding, shroud. |
| M3 Combat | Combat and the control-point rule: a playable Mission 1. |
| M4 Economy | Harvester, refinery, storage. |
| M5 Base | Base building and production. |
| M6 Enemy AI | A computer opponent. |
| M7 Vertical slice | One complete, representative mission. |
| M8 Content | The rest of the units, buildings and terrain. |
| M9 Campaign | The Blue and Red campaigns. |
| M10 Polish | Final art, audio, balance and bug fixing. |

Multiplayer is out of scope.
