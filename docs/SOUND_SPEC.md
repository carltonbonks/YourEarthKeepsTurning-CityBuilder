# Sound spec

How the game's sound is organised, and what any sound we fetch, buy or commission must match so it drops into the same slots. It is written for whoever redoes the soundscape: you change data and files, never code. Direction and why: the sound plan at https://claude.ai/artifact/DchJ6Lv3YXFh2HZcCjyhcv.

## The idea

- **Code asks for moments, never files.** The game says `card.pick`, never `card_pick_02.ogg`. One file, `audio/manifest.json`, maps each moment to its sounds, so swapping a sound is a data edit.
- **The sim stays silent.** `sim/` never plays sound. `game/sound_director.gd` watches the interface (and, in later slices, the run) and plays moments, so headless tests and bot runs are untouched.
- **Loudness follows the emphasis tiers** of [TEXT_STYLE.md](TEXT_STYLE.md): 0 ambient, 1 notice, 2 problem, 3 moment, 4 run. The higher the tier, the louder and rarer the sound. Tier 3 and 4 moments get a beat of their own (CLAUDE.md, "make it land").
- **Character (Yusuf, 2026-11-19):** grounded and sparse. Mostly world sounds, quiet music, real recordings with grit. Voices are wordless only: murmurs, shouts, cheers, never words.

## The manifest

Each moment in `audio/manifest.json` is a row like this (the file's `_note` explains every key):

```json
"card.pick": {
	"files": ["sfx/card_pick_01.ogg", "sfx/card_pick_02.ogg", "sfx/card_pick_03.ogg"],
	"bus": "UI",
	"tier": 1,
	"volume_db": -9.0,
	"pitch_jitter": 0.05,
	"max_voices": 1,
	"cooldown_s": 0.1,
	"brief": "A card taken: something with weight set down on wood. A decision made, not a menu click.",
	"licence": ["Kenney (kenney.nl), RPG Audio, CC0 1.0"]
}
```

- **files:** one is picked at random each time it plays. Two to four variants keep a common sound from sounding stamped.
- **brief:** what the moment should feel like. Keep the intent when you change the sound.
- **licence:** one line per source, author first: `Author (site), pack or sound name and link, licence`. The Credits screen is built from these lines.

## Buses

`default_bus_layout.tres` holds the mixer: Master, then Music, Ambience, World (combat, building, people), UI and Stingers (the big one-off moments), each sending to Master. Settings shows a volume slider for Master and for each bus that has sounds (`SettingsPanel.VOLUME_ROWS`; a test fails if a bus with sounds has none). Effects such as reverb or ducking go on the buses in the layout, not in code.

## Files

- **Where:** `audio/sfx/` for one-shots, `audio/ambience/` for beds, `audio/music/` for music.
- **Names:** `<area>_<event>_<nn>.ogg`, the moment's key with its dot made an underscore: `card.pick` is `card_pick_01.ogg`, `card_pick_02.ogg`.
- **Format:** Ogg Vorbis, 44.1 kHz. Mono for one-shots, stereo for beds and music.
- **Level:** every file's loudest peak sits at -1 dBFS, so the manifest's `volume_db` alone sets how loud a moment plays. `tools/import_sound.sh <source> <dest> [--stereo]` converts any wav, flac, mp3 or ogg and levels it.
- **Budget:** all audio stays under 15 MB, so the web build loads fast.

## Licences

Only **CC0** and **CC-BY** (with the author credited) go in, because the repository is public and the game may sell on Steam. No NC (non-commercial), ND (no changes) or SA (share-alike). Check the licence on the source's own page when fetching. Sources so far: Kenney (kenney.nl, CC0). Good next ones: freesound.org (filter to CC0 and CC-BY), opengameart.org (CC0 and CC-BY only).

## Moments so far

Slice 1 (2026-11-19) covers the interface. The director hears it by itself, so screens don't have to remember to:

| Key | When | Tier |
| --- | --- | --- |
| `ui.click` | any button pressed | 0 |
| `ui.hover` | the mouse comes to rest on a card | 0 |
| `ui.toggle` | a check box ticked or a list item chosen | 0 |
| `card.deal` | cards appear for a pick: a flip each, one after another (a screen rebuilt with the same cards stays silent) | 1 |
| `card.pick` | a card taken | 1 |
| `card.roll_blue`, `card.roll_yellow`, `card.roll_orange` | after the flips, a glint for the rarest roll among the new cards | 1-3 |

Later slices add the round's beats (dawn, the war horn, the last kill, relics, age up, won and lost), the town's beds, combat and work, then music. The plan lists their keys.

## Adding or changing a sound

1. Run `tools/import_sound.sh <source> audio/sfx/<area>_<event>_<nn>.ogg`.
2. Add the file (and its licence line) to the moment's row in `audio/manifest.json`, or a new row with a brief.
3. Open the project in Godot once (or run `tools/test.sh sound`) so the file is imported, then commit the `.ogg`, its `.import` file and the manifest together.
4. `tests/test_sound.gd` fails if a file has no row, a row has no licence or brief, a name doesn't match its key, or code asks for a key the manifest lacks.
5. To audition: play the web build, or in the editor run the game and use the screens; Settings' sliders click when let go so a level can be heard.
