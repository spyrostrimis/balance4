# Balance: sound and music

Since milestone M7 (step M7.7) the game has sound. **All of it is
placeholder**: tones and noise made by a script, so that every action is
heard and the plumbing is in place. The real sound and music come in M10 or
later (a decision of 2026-11-15, see [m7-plan.md](m7-plan.md)); swapping
them in needs no code changes.

## How it fits together

| Part | What it is |
| --- | --- |
| `tools/make_sounds.py` | Makes every sound and both music loops from tones and noise (numpy), and writes the sound bank. Run `python tools/make_sounds.py`; it gives the same files every time |
| `assets/audio/*.wav` | The sounds (mono, 16-bit, 22050 Hz) |
| `data/sounds/sound_bank.tres` | The sound bank (`SoundBank`): one `SoundEvent` per event the game plays |
| `scripts/ui/sounds.gd` | `SoundPlayer`, loaded as the autoload `Sounds`: plays events by name, twelve at a time, and the music in a loop |
| `default_bus_layout.tres` | The audio buses: Master, and Music and Effects feeding it. The settings' three volumes set them (see `GameSettings`) |

A `SoundEvent` has a name, one or more files (one is picked at random each
time), a volume, how much the pitch may vary, its bus, and the shortest time
between two plays (so twenty soldiers striking at once do not make twenty
sounds).

**To replace a sound**, put a new file in `assets/audio/` and point the
event at it in the sound bank (in the Godot inspector or by hand), or give
it the old file's name. Ogg Vorbis works as well as WAV.

## The events

| Event | When |
| --- | --- |
| `click` | Any HUD or menu button |
| `select` | Units or a building selected |
| `order`, `order_attack` | A move or harvest order; an attack or attack-move order |
| `denied` | Something cannot be done (the message box says why) |
| `hit`, `shot` | A blow; a tank's shot |
| `death`, `explosion` | A soldier falls; a vehicle blows up |
| `wreck` | A building is destroyed |
| `mend`, `restore` | The field commander's Mend; the Prince's Restore |
| `place`, `ready`, `trained` | A building is placed; a building is finished; a unit comes out |
| `low_power` | The base starts using more power than it makes |
| `transform` | A harvester changes between truck and robot |
| `repair` | A building of the player's is being repaired (about once a second) |
| `steal` | Orichalcum is taken from a trailer |
| `message` | A mission's character says something |
| `victory`, `defeat` | The mission ends |
| `music_menu`, `music_mission` | Loops on the title screen and the briefing; in a mission |

The world's sounds (hits, deaths, heals and so on) are heard only where the
player can see them: on screen, or just off it, and on explored ground. The
player's own buildings being finished and units being trained are heard
wherever they are. The world tells the screen about them through
`SimWorld.effects`, as it does for drawing.

## Tested

`tests/test_sounds.gd` checks that the bank has every event on the right
bus, that the player plays and holds back repeats, that a finished building
is announced, and that the map screen sounds what happens in view and not
what happens out of sight.
