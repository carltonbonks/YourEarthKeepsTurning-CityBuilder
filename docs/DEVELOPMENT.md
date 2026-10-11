# Developer guide

How the code is laid out and the habits every change follows. Design intent lives in [CLAUDE.md](../CLAUDE.md); this file is the "how". If the two disagree, CLAUDE.md wins and this file gets fixed.

## Getting started

```sh
tools/setup_godot.sh                                     # downloads Godot 4.7.1 to ~/godot (once per machine)
~/godot/godot --headless --path . --import               # first time / after adding files
~/godot/godot --headless --path . -s res://tests/run_tests.gd
```

All tests must pass before a PR (CI runs the same commands, see `.github/workflows/ci.yml`). The error lines about "resources still in use at exit" are harmless; look for `N passed, 0 failed`.

## Code map

The split that matters: **`sim/` is the game, `game/` only shows it.** Nothing in `sim/` touches scenes or nodes, so whole runs play headless for tests and bot balance runs. Nothing in `game/` changes the run except through `RunState`'s public methods (build, choose_pick, choose_relic, set_price, ...).

| File | Role |
| --- | --- |
| `sim/content.gd` | `Content`: loads every `data/*.json` once. The only place data is read. Helpers such as `enemy_has_tag`, `age_reached`, `recipes_for`. |
| `sim/run_state.gd` | `RunState`: one run. Phases (BUILD, PICK, SIM, RELIC, WON, LOST), stock, building orders, dawn picks, promotions, relics (`mod()`), hero mood, upkeep, wave generation, and the run record (`to_record()`, `RECORD_FORMAT`). |
| `sim/world.gd` | `World`: the map and everything on it, stepped in fixed ticks. Day/night, townsfolk jobs, hero AI (whims, energy, lodgings, shopping, wilds), workshops and stalls, prizes, enemies, combat, towers. Pauses at dawn and at round end for `RunState`. |
| `sim/unit.gd` | `Unit`: one hero, townsperson or enemy (plain fields). |
| `sim/loot.gd` | `Loot`: items as plain data `{base, tier, affixes}`; rolling, stats, how a hero rates an item. |
| `sim/seeded_rng.gd` | `SeededRng`: every random roll goes through one of these. |
| `sim/autoplayer.gd` | `AutoPlayer`: scripted player for tests and balance runs (styles: balanced, workers, heroes, market, bronze). |
| `sim/run_stats.gd` | Plain-language stats from run records (Run history screen and `tools/run_report.gd`). |
| `game/main.gd` | The one screen: decisions on the left, map in the middle, heroes and story below. UI built in code (placeholder). |
| `game/arena_view.gd` | Draws the map with placeholder shapes; zoom, pan, hover. Read-only. |
| `game/tooltips.gd` | Hover text for map things and the build list, tag notes and supply warnings. Read-only. |
| `game/run_history.gd` | Saves runs to `user://runs/`, download/copy for sharing. |
| `data/*.json` | All content and balance numbers. Each file starts with a `_note` explaining its keys; keep it current when you add a key. |
| `tools/` | Headless helpers: `balance_run.gd` (bot runs), `run_report.gd` (compare runs), `market_probe.gd` (one run's economy), `export_csv.py` (run records to CSV tables). |
| `tests/` | `run_tests.gd` runs every `test_*` method in `tests/test_*.gd` (classes extend `TestCase`, use `check` / `check_eq`). |

Flow of a round: `RunState` BUILD → for each of 3 days: PICK at dawn → SIM (`World.step()` until the next pause) → after night 3's wave: RELIC → next BUILD.

## Habits

### 1. Content is data
Numbers, names and content go in `data/*.json`, read through `Content`. Code reads keys, never hardcodes a balance value. A new key gets a line in that file's `_note`. Keep visuals swappable: `game/` may pick colours and shapes from data but no rule may depend on art.

### 2. Tags: add one only when a rule reads it
Creatures carry descriptive `tags` in `data/enemies.json` (a wolf is `animal`, `sentient`, `beast`). A tag only *does* something when a rule reads it. Today two do:

| Tag | Read by | Effect |
| --- | --- | --- |
| `sentient` | `World._damage` | turns on whoever hits it for a while |
| `beast` | hunting lodge `prize` in `data/buildings.json` | the lodge pays shells and extra hides per kill |

When you add or change a rule that keys on a tag:
1. Read it through `Content.enemy_has_tag(type_id, tag)` (or a building's `prize.tag` in data), never by checking enemy ids.
2. Explain it for players: add a line to `data/tags.json` (prize tags are found from `buildings.json` automatically). The hover tooltip then shows `tag: what it does`; tags without a rule show by name alone.
3. Add the tag to every creature it should apply to in data, and a test that the rule fires (see `tests/test_tooltips.gd` for the tooltip side).
4. Don't invent a tag for one creature: if only one enemy needs a behaviour, give it a specific data key instead (like `shield` or `war_chant`).

Tags exist only on enemies so far. If heroes, buildings or items need them, generalise `enemy_has_tag` into one `has_tag` helper first rather than adding a second mechanism.

### 3. Determinism
All randomness goes through the run's `SeededRng` (never `randi()`/`randf()`), and the sim steps in fixed ticks. The same seed and the same choices must give the same run, so "seed 4821, round 6" is reproducible.

### 4. Run records
Every run is saved as `RunState.to_record()`, used by the game's Run history, the bots and `tools/export_csv.py`. When a mechanic changes what a run looks like: extend the record (never drop or rename fields), bump `RECORD_FORMAT` with a comment saying what the new format adds, add the new fields to `tools/export_csv.py`, and keep `tests/test_run_record.gd` passing.

### 5. Tests and balance
- Every new rule gets a test in `tests/`, usually by building a `RunState` with a fixed seed and stepping it (see `tests/test_market.gd`).
- After a change that affects difficulty, run the bots and report win rates per style in the PR:
  `~/godot/godot --headless --path . -s res://tools/balance_run.gd -- runs=40 style=balanced`
  Current target (tuning pass 1): balanced 70-80%, workers clearly weaker.
- New mechanics that a scripted player should use get taught to `AutoPlayer`, otherwise bot numbers stop meaning anything.

### 6. Player-facing transparency
If players need to understand a rule to make a choice, it shows up in a tooltip (`game/tooltips.gd`) or a building's `text` in data. Supply warnings (a stall with no workshop feeding it) are the model: say what is missing and what to build.

### 7. Shipping a slice
Small slices, one PR each, from a `claude/...` branch. A PR says what changed in plain language, how to try it on the playtest link (merged to `main` = live at https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/), bot win rates if balance moved, and 2-3 playtest questions with a seed. Claude's default choices for open design questions go in CLAUDE.md's "Open questions" as "Claude's defaults, pending Yusuf's playtest". Update the "How it plays" section of README.md when the game changes.

## Run data for analysis

Run records (Yusuf's downloads and bot batches) live in the project's shared folder at `game-data/raw/`, and `python3 tools/export_csv.py <raw> <csv>` rebuilds the CSV tables in `game-data/csv/` (described in `game-data/README.md` there). Bot batches: `balance_run.gd -- runs=60 style=balanced out=bots-<label>-balanced.jsonl label=<label>`.
