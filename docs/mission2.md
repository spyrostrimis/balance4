# Balance: Mission 2, "Holding the Claim"

The vertical slice of milestone M7 (see [m7-plan.md](m7-plan.md)): the first
mission with base building and both of Blue's heroes. Step M7.4 built it
with placeholder art and no sound; M7.5 gave it the new HUD, the briefing
and the debriefing, M7.6 the portraits and the effects, M7.7 placeholder
sound and music. Played as Blue only; Red's version waits for the Red
campaign (M9).

**The name, the story and every number are provisional.**

Start it from the title screen (Play, then "Mission 2: Holding the Claim",
which shows its briefing first; winning Mission 1 as Blue leads on to it too) or with
`-- --map=mission-2`. The file is
`data/missions/holding_the_claim_blue.tres`, its hints
`data/hints/holding_the_claim.tres`; it is made only of the parts described
in [missions.md](missions.md).

## The story so far

Mission 1 took the Orichalcum rock. Now the Prince arrives with a small
force and a convoy to hold it. Red, camped across the river, means to take
it back before Blue can dig in.

## The map: River Fords

`data/maps/forest_02.tres`, 64 by 48 cells, made by `tools/make_maps.py`
(`river_fords_map`) like the other maps, and checked by it: both sides can
reach each other and the rocks, and the river can be crossed only at the
fords.

- **South-west:** where Blue arrives, at the end of a track. North of it, a
  wide patch of stony building ground: Blue's base site.
- **The middle-west:** Blue's Orichalcum rock, in a clearing.
- **The river** runs from the north edge to the south edge, east of the
  rock. It can be crossed only at **two fords**, one in the north and one in
  the south, each reached by a track.
- **North-east:** Red's forward camp on its own stony ground, with a smaller
  rock of Red's just south of it.

## How it plays

| Phase | What happens |
| --- | --- |
| Arrival | Blue starts with the Prince, the Field Commander, four Guardsmen, a light tank and a harvester. The Field Commander says where to go; the base site is shown on the map. |
| Setting up | When the Prince reaches the site, the convoy unpacks a headquarters and a refinery and brings 700 Orichalcum. New objective: build a Generator and a Barracks. |
| Probing | 75 seconds later three Red scouts cross the southern ford. |
| The assault | Once the player has dug in and at least four and a half minutes have passed (or after eight minutes whatever), a scout warns; 70 seconds later six Red soldiers and two tanks cross the river, heading for the Prince. New objective: beat them off. |
| Striking back | When the assault is beaten, four Guardsmen and two tanks arrive from the south-west, Red's camp is shown, and the last objective is set: destroy the camp. |

Red's camp (a refinery, a generator, a barracks and a workshop) is played by
the computer in camp mode (`CampOpponentDef`): it harvests its small rock,
trains troops and tanks up to eight fighters, defends its buildings and
repairs them, but builds nothing new and never attacks; the scouts and the
assault come from the mission's triggers. Red has no hero, so Red's
undecided characters do not hold M7 up.

**Winning:** destroy the four buildings of the camp (the objectives on the
way must be done too). **Losing:** either hero dies (the rule of every
mission), or Blue loses every building and every troop.

The hints teach, one at a time: selecting, the heroes, moving the Prince to
the site, building and placing, harvesting, training, the abilities,
repairing, and attacking across a ford. The mission's characters talk in
the message box, with their portraits (eight seconds a message); new
objectives are announced there too, and the Objectives button (or O) lists
them all.

## Tested

`tests/test_mission2.gd` checks the map and the data, and plays the whole
mission with a simple player that does what the hints say: it wins in
about nine minutes, losing about 27 units. A player who does nothing is
beaten when the assault reaches the Prince, after about ten minutes.

## Provisional choices

| What | Value |
| --- | --- |
| Blue's force at the start | the Prince, the Field Commander, 4 Guardsmen, a light tank, a harvester |
| What the convoy brings | a headquarters, a refinery, 700 Orichalcum |
| Richness of the rocks | four times |
| Red's camp | refinery, generator, barracks, workshop; 4 soldiers, a tank, a harvester, 400 Orichalcum; at most 8 fighters |
| The scouts | 3 soldiers, 75 s after the base is set up |
| The assault | 6 soldiers and 2 tanks, 100 s after the player has dug in and 270 s have passed, or at 580 s at the latest |
| The reinforcements | 4 Guardsmen and 2 light tanks |
