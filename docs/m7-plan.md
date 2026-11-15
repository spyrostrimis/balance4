# Balance: M7 plan

**Status: agreed on 2026-11-15.** The user made four decisions (marked
**Decided**) and approved the rest of the plan as proposed. The decisions
about the game are recorded in [design.md](design.md); the "Done means" list
is in [roadmap.md](roadmap.md). As everywhere, names and numbers stay
provisional, and the mission's story is a starting point that can change as
the mission is built.

## What M7 is for

The roadmap's outline: one mission at the quality the whole game should
reach, with final-quality art, sound, HUD and briefing, heroes with active and
passive abilities, and base building, that someone who has never seen the
game can start, play and finish without help.

M7 is where the game stops being a set of systems and becomes something a
stranger can pick up. Everything M8 to M10 add is more of what M7 proves.

## What the M0-M6 audit found that M7 depends on

The audit after M6 (all 191 tests pass; every "Done means" of M0-M6 is met)
found these gaps. They decide the shape of M7:

1. **Missions cannot be scripted.** `MissionDef` is a fixed template: two
   sides, one troop type and one commander each, win rules chosen by flags
   (`practice`, `skirmish`, control point), hints hard-coded per mission type
   (`MissionHints`). There are no triggers, reinforcements, messages,
   objectives in sequence, units or buildings placed by hand, or rules for a
   hero's death.
2. **Mission 1 has no base building**, by design, but M7 asks for base
   building *and* heroes. So the slice is a new mission.
3. **Open design questions block heroes**: what the Blue leader's pulse and
   "Encouragement" do, who Red's field commander is, what "Dominion" does.
   No passive ability exists yet.
4. **There is no game build** (no export presets), so a stranger cannot
   start the game.
5. **There is no sound** and no plan for where it comes from.
6. **The HUD art is not final**, and parts of the approved layout (hero
   portrait, Objectives and Menu buttons) were never built. The roadmap says
   "final" for M7 and again for M10.
7. **Repair does not exist**, though it is a design pillar and Blue's
   identity.

## Proposed scope

### The mission

**Decided:** the slice is a new Mission 2, played as Blue only. The rest of
this section was approved as proposed; the story is a starting point.

**Mission 2, "Holding the Claim"** (provisional), played **as Blue only**, on
a **new hand-made forest map**. Red's version waits for the Red campaign (M9).
Playing one side halves the art, writing and testing, and avoids the open
questions about Red's heroes.

Story beat: after Mission 1 took the rock, the prince arrives with
a small convoy to hold it. Red, camped across the river, means to take it
back before Blue can dig in.

| Phase | What happens | What it teaches |
| --- | --- | --- |
| 1. Arrival | The prince, the field commander, a few Guardsmen and a construction convoy arrive. Objective: set up the headquarters on the marked rock. | Selecting, moving, the heroes |
| 2. Dig in | Build a refinery and a generator; the harvester starts work. A Red scout party probes. | Base building, power, harvesting |
| 3. First assault | A timed Red attack (with warning). Objective: the prince must survive; the base must hold. | Production, defending, the leader's pulse, repair |
| 4. Strike back | Reinforcements arrive. Objective: destroy Red's forward camp across the river. | Attacking a base, attack-move, abilities |

Length: 20 to 30 minutes for a first-time player. One difficulty.

Winning: destroy the forward camp. Losing: either of Blue's heroes dies
(decided, see below), or the headquarters and every soldier is lost.

Red in this mission has **no hero** (so Red's open questions do not block
M7). Its forward camp is pre-built and produces units; its attacks are
scripted waves plus the existing computer opponent's defence. It does not
build new buildings.

### Heroes

| Hero | Active | Passive |
| --- | --- | --- |
| Blue field commander (exists) | Mend: heal one unit (exists) | None in M7 |
| Blue leader, the prince (new) | **Decided:** an area pulse that heals troops and repairs vehicles nearby, **not buildings**. Within 3 cells, 30 s recharge (provisional numbers; name provisional). | **Decided:** *Encouragement*, passive: own units near him move 5% faster and attack 5% faster. "Near" is within 4 cells (provisional). |

- **Decided: when the player loses any hero, the player loses the mission.**
  This is a rule of every mission. Enemy heroes are not covered by it: losing
  one does not lose the enemy the mission, unless that mission's objectives
  say so.
- Heroes get a **portrait** in the top-left corner (the approved layout); a
  click on it selects the hero, a double click centres the camera on them.
- `Ability` grows from one kind (`HEAL_TARGET`) to: target, area (around the
  hero) and passive aura. The computer opponent does not need to use
  abilities in M7 (Red has no hero).

### Repair

- **Decided:** the prince's pulse repairs vehicles as well as healing troops,
  but not buildings.
- **Decided: building repair.** Select a building of your own
  (buildings become selectable) and click Repair; it is repaired a little at
  a time and paid for in Orichalcum, as in Dune II. Selling is left out.
  Without this, a damaged building can never be mended.

### Mission scripting (technical, needed whatever the mission is)

A mission becomes a small set of data resources instead of flags:

- **Placed forces**: units and buildings for any side at given cells.
- **Objectives**: a list, shown in an Objectives panel, each primary or
  secondary, each with a completion and a failure condition.
- **Triggers**: *when* (time passed, an area entered by a side, a unit or
  building destroyed, an objective done, a building of a type placed, a store
  above an amount) *then* (show a message with a portrait, add or complete an
  objective, spawn reinforcements, reveal an area, send a side's units
  somewhere, win, lose).
- **Hints** become triggers too, so each mission teaches its own things.
- Mission 1, the trials and the skirmish are rewritten in the new form and
  must behave as before (their tests stay green).
- More than two sides is **not** in M7, but the format must not rule it out.

### The map

Hand-made in the existing text format (`data/maps/*.tres`), checked by the
same reachability test as the generated maps. A river with two fords, the
Orichalcum rock, building ground for Blue's base and Red's camp. Tiled is not
needed yet; a map-making tool is an M8/M9 question.

### HUD, briefing and menus

- **HUD redesign**, mockups first: the user does not like the v8 HUD and
  asked to return to it. Two or three mockup variants in the approved v4 look;
  build only what is approved. Top bar with Objectives and Menu buttons, hero
  portraits, the sidebar laid out as approved, a message box for mission
  talk.
- **Briefing screen** before the mission (text, a map picture, the
  objectives) and a **debriefing** after it.
- **Title screen**: Play (Mission 1, Mission 2), Practice (the trials and the
  skirmish), Settings, Quit. The developer buttons move under Practice.
- **Settings**: master, music and effects volume; scroll speed; full screen.
  Reachable from the title and the pause menu. Saved between runs.

### Art at final quality, for what is in the mission

- The prince (unit sprite and portrait), the field commander's portrait,
  the convoy if it is a unit.
- A pass over every unit and building that appears in the mission, and the
  map's terrain, against the approved v4 look.
- Effects: the tank's shell and muzzle flash, the pulse, repair sparks.

### Sound

**Decided: placeholder sound and music in M7.** The real sound is dealt with
later (M10 or after). M7 builds the plumbing so that swapping the files in is
all that is left:

- **Placeholder effects** for UI clicks, selecting and acknowledging orders,
  each weapon's hit, deaths, explosions, building placed, construction and
  training done, low power, the harvester changing shape, the abilities and
  mission messages. Simple generated tones and noises, made by a script in
  `tools/`, so they are original and free of licences.
- **Placeholder music**: one loop for the menus, one for the mission.
- Every sound is named in data (which event plays which file), so real
  sounds replace them without code changes.
- Audio buses (master, music, effects) wired to the settings.

### A build a stranger can run

- `export_presets.cfg` for Windows, a script that builds `Balance.exe`
  into a git-ignored folder, and a check that it starts.
- **The acceptance test is a real person** who has never seen the game,
  playing the exported build without help while the user watches. Whatever
  stops them is fixed before M7 is done.

## Proposed "Done means"

- Mission 2 can be played as Blue from the title screen, through a briefing,
  to a win or a loss, and ends in a debriefing.
- Missions are defined by placed forces, objectives and triggers; Mission 1,
  the trials and the skirmish work as before in the new form.
- The prince and the field commander each have an active ability; the
  prince's Encouragement works as a passive. Losing any of the player's
  heroes loses the mission.
- The prince's pulse heals troops and repairs vehicles. Buildings can be
  selected and repaired for Orichalcum.
- The HUD follows a newly approved mockup and shows hero portraits,
  objectives and mission messages.
- Every action in the mission has a placeholder sound; there is placeholder
  menu and mission music; volumes can be set.
- A Windows build is exported and starts on a machine without Godot.
- A first-time player finishes the mission from the exported build without
  help.
- The project opens and runs with no errors, and the headless tests pass.

## Proposed order of work

Each step ends in something playable and a push, as for every milestone.

| Step | What | Depends on |
| --- | --- | --- |
| M7.1 | Decisions below agreed and recorded in design.md. **Done** | the user |
| M7.2 | Mission scripting; existing missions ported; tests. **Done**: see [missions.md](missions.md) | M7.1 (scope only) |
| M7.3 | Abilities (area, passive), the prince, the hero death rule, building selection and repair. **Done**: see [heroes.md](heroes.md) | M7.1 |
| M7.4 | The map and Mission 2, with placeholder art and no sound. **Done**: see [mission2.md](mission2.md) | M7.2, M7.3 |
| M7.5 | HUD mockups, approval, then the new HUD, portraits, messages, briefing, title and settings. **Done**: mockup v12 D approved and built (portraits, message box, objectives list); briefing and debriefing; title screen with Play, Practice, Settings and Quit; settings saved in `user://settings.cfg`, with Master, Music and Effects audio buses | approval of the mockups |
| M7.6 | Final art pass and effects. **Done**: Blender portraits for the Prince, the Field Commander and the scout; the tank's muzzle flash, shell and blast, exploding vehicles, a richer pulse; units, buildings and terrain checked against v4 | M7.4 |
| M7.7 | Placeholder sound and music, audio buses, volume settings. **Done**: see [sound.md](sound.md) | M7.4 |
| M7.8 | Windows export and the first-time player test; fix what it finds | everything |

M7.5 to M7.7 can overlap once M7.4 is playable.

## Decisions

| # | Question | Answer |
| --- | --- | --- |
| 1 | Which mission is the slice? | **Decided:** a new Mission 2 |
| 2 | Blue only, or Blue and Red? | **Decided:** Blue only; Red's version in M9 |
| 3 | What do the prince's pulse and "Encouragement" do? | **Decided:** pulse (active) heals troops and repairs vehicles nearby, not buildings. Encouragement (passive): own units near him move and attack 5% faster |
| 4 | Does a hero's death lose the mission? | **Decided:** losing any of the player's heroes loses the mission; enemy heroes only if the mission's objectives say so |
| 5 | Where does sound come from? | **Decided:** placeholders in M7; real sound in M10 or later |
| 6 | What does "final quality" mean in M7, given M10 is "final art"? | **Decided:** M7 sets the bar for everything in Mission 2; M10 brings the rest up to it and fixes what playtests find |
| 7 | Building repair and selectable buildings in M7? | **Decided:** repair yes (paid in Orichalcum), selling no |
| 8 | Who is the first-time player for the acceptance test? | **Decided:** someone the user knows who has not seen the game |
| 9 | The pulse's range and recharge, the reach of Encouragement, the prince's name | **Decided (provisional numbers):** pulse within 3 cells, 30 s recharge; Encouragement within 4 cells; names stay provisional |

## Recorded for later milestones (not M7)

From the audit, so that nothing is lost:

- **M8**: faction differences beyond colour; Red's heroes once designed; a
  third side (Green, creatures) in the mission format; armour for troops;
  rally points; a map-making workflow (text maps or Tiled).
- **M9**: saving during a mission, as well as between missions; the Red
  version of Mission 2.
- **M10**: the real sound effects and music (replacing M7's placeholders);
  key rebinding, game speed, difficulty levels, fog of war over
  ground no longer watched (if wanted), taking back one's own orphaned
  trailer, selling buildings.
- **Any time**: run the headless tests on GitHub for every push; tag each
  milestone's commit.
