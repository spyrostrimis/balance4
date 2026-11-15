# Balance: heroes and repairs

The heroes' abilities, the rule for losing a hero, and repairing buildings.
Step M7.3 of milestone M7 built these (see [m7-plan.md](m7-plan.md)); the
field commander and Mend came in M3 and are described in
[combat.md](combat.md). The hero trial, a practice mission, is where to try
them.

**Every name and number here is provisional**, apart from what the user
decided on 2026-11-15 (marked *decided*; also in [design.md](design.md)).

## Abilities

An `Ability` (`data/abilities/`) is either **active**, used when the player
says so, or **passive**, always on. A unit type has at most one of each
(`UnitType.ability`, `UnitType.passive`). Every active ability has its own
key.

| Kind | What it does |
| --- | --- |
| Heal one unit (`HEAL_TARGET`) | The hero walks within reach of a unit the player picks and gives it health back. Mend. |
| Area heal (`HEAL_AREA`) | Used at once: every unit of the hero's side within reach, the hero included, gets health back. Troops are healed and vehicles repaired; buildings are not. Restore. |
| Haste aura (`HASTE_AURA`) | Passive: the hero's own units within reach (not the hero) move and attack faster. Encouragement. |

## The Prince

Blue's leader (`data/units/blue_leader.tres`). His name, like everyone's, is
not decided; the game calls him "The Prince".

| | The Prince | (Field Commander) |
| --- | --- | --- |
| Health, speed, sight | 150, 2.5 cells/s, 5 cells | 120, 2.5, 5 |
| Attack | 14, range 1, once a second | 16, range 1, once a second |
| Active | **Restore** (E): area heal, *decided*; 35 health within 3 cells, every 30 s | **Mend** (Q): 40 health to one unit within 3 cells, every 12 s |
| Passive | **Encouragement**: units within 4 cells move and attack 5% faster (*decided*: 5%) | none |

- A sped-up step or swing is rounded to whole ticks, and what is lost is
  carried into the next, so that 5% is 5% on average. Auras do not add up.
- His sprite (a blue cloak and a circlet, no helmet, so he reads apart
  from the field commander) is rendered by `tools/render_units.py`
  (`prince`). His portrait, the field commander's and the scout's are bust
  shots from the same script (`prince_portrait` and so on; run it with
  `portraits`), which `tools/make_hud.py` turns into the HUD's 44x54
  pictures. The field commander is drawn as the backstory has her: the
  woman of the Royal Guard who escaped with the prince.

## Losing a hero

*Decided:* **when the player loses any hero, the player loses the
mission.** This is a rule of every mission, checked by `Mission` before the
objectives. Enemy heroes are not covered: losing one loses the enemy
nothing, unless the mission's objectives say so (a `GoneCondition` on the
hero's tag). The result screen names the fallen hero.

Mission 1 now ends in defeat if the field commander falls. It can still be
won on both maps by keeping the commander a few cells behind the troops,
and its hint says so.

## Selecting and repairing buildings

A left click on one of the player's buildings selects it (selecting units
lets go of it, and the other way round). It gets a frame, its health bar
and its description in the sidebar, and **Repair** (R) takes the place of
Attack and Stop.

- *Decided:* buildings can be repaired, for Orichalcum. The Prince's Restore
  does not repair them.
- A repair gives back 20 health a second and costs 1 Orichalcum for every 4
  health, paid bit by bit. With the store empty it waits; at full health it
  stops. R again stops it.
- The sidebar shows what the rest of the repair will cost. Sparks and a
  rising plus sign show it on the map.
- **The computer opponent repairs too**, by the same rules: a building
  below 60% of its health, while it has more than 150 in store.
- Selling buildings is not planned yet.

## Keys

| Input | What it does |
| --- | --- |
| Q, then left click on one of your units | The Field Commander heals it (Mend) |
| E | The Prince's Restore, at once |
| Left click on one of your buildings | Select it |
| R | Repair the selected building, or stop repairing it |

The sidebar has a button for each hero's ability ("E Restore", "Q Mend"),
which counts down while the ability recharges.

## The hero trial

A practice mission (`hero_trial_blue.tres`, `-- --map=hero-forest`, or
"Hero trial" under Practice on the title screen), Blue only, on the forest map: a base
(headquarters, refinery, generator, barracks), a harvester, the Prince, the
Field Commander, four Guardsmen, a light tank and 800 Orichalcum. Three Red
attacks come from the far corner, after 40 s, 130 s and 230 s, each
announced by a scout ten seconds before. Beat off the last one to win; lose
a hero and it is lost. It is built entirely from the mission format of
[missions.md](missions.md): placed forces, triggers that bring and send the
attacks, a hidden objective shown with the last one.

## Provisional choices

| What | Value | Where |
| --- | --- | --- |
| The Prince's health and attack | 150; 14, range 1, once a second | `data/units/blue_leader.tres` |
| Restore: health, reach, recharge | 35, 3 cells, 30 s | `data/abilities/restore.tres` |
| Encouragement: reach | 4 cells | `data/abilities/encouragement.tres` |
| Repair: speed, cost | 20 health a second; 1 Orichalcum for 4 health | `SimWorld.REPAIR_*` |
| When the computer repairs | below 60% health, with more than 150 in store | `ComputerOpponent.REPAIR_BELOW` |
| The hero trial's attacks | 4 soldiers; 5 and a tank; 6 and two tanks | `data/missions/hero_trial_blue.tres` |
