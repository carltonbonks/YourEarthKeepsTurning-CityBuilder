# Developer guide

How the code is laid out and the habits every change follows. Design intent lives in [CLAUDE.md](../CLAUDE.md); this file is the "how". If the two disagree, CLAUDE.md wins and this file gets fixed.

## Getting started

```sh
tools/setup_godot.sh                                     # downloads Godot 4.7.1 to ~/godot (once per machine)
tools/test.sh                                            # imports, runs every test, fails on any script error
```

All tests must pass before a PR; CI runs `tools/test.sh` too (see `.github/workflows/ci.yml`). A GDScript error stops a test part-way without failing a check, which is why `tools/test.sh` also fails on any `SCRIPT ERROR` in the log: never run `tests/run_tests.gd` alone and trust its count.

## Code map

The split that matters: **`sim/` is the game, `game/` only shows it.** Nothing in `sim/` touches scenes or nodes, so whole runs play headless for tests and bot balance runs. Nothing in `game/` changes the run except through `RunState`'s public methods (build, choose_pick, choose_relic, set_price, ...).

| File | Role |
| --- | --- |
| `sim/content.gd` | `Content`: loads every `data/*.json` once. The only place data is read. Helpers such as `has_tag` / `unit_has_tag`, `age_reached`, `recipes_for`. |
| `sim/run_state.gd` | `RunState`: one run. Phases (BUILD, PICK, SIM, RELIC, WON, LOST), stock, building orders, dawn picks, promotions, relics (`mod()`), hero mood, upkeep, wave generation, and the run record (`to_record()`, `RECORD_FORMAT`). |
| `sim/world.gd` | `World`: the map and everything on it, stepped in fixed ticks. Owns all world state, the day/night clock, the map, and the shared movement and combat helpers (`walk_toward`, `fight`, `hit`, `damage`, `nearest_enemy`). Every move goes through `walk_toward`, which asks `Pathing` for the next point and walks faster on trails and roads. Pauses at dawn and at round end for `RunState`. Behaviour lives in four parts it creates: |
| `sim/town.gd` | `Town` (`world.town`): the ring town. Plots in rings and sectors round the hearth, obstacles, thickets, where a new building goes (`choose_plot`: its `near` key, never on a staked road, never walling off the hearth), staked roads (`stake`, `route`) and paving, staked palisades (`stake_wall`, `wall_line`), gates where roads cross them, and raising them (`build_wall`). |
| `sim/pathing.gd` | `Pathing` (`world.pathing`): the ground as a grid of squares (solid or open; plain, thicket, trail or a road kind; palisade and gate health) and how units find their way (`next_point`, Godot's AStarGrid2D: one grid for townsfolk and heroes, who climb walls slowly and walk through gates, and one for raiders, where walls cost extra). Raiders that walk into a wall batter it (`World.walk_toward`). Walking straight when that is as quick, cached routes otherwise; trails worn by feet (`tread`, `wear_trails` at dawn). |
| `sim/folk_ai.gd` | `FolkAI` (`world.folk_ai`): townsfolk. Warriors patrol and answer calls; workers gather, haul, build, craft and patch the hearth. |
| `sim/hero_ai.gd` | `HeroAI` (`world.hero_ai`): heroes. Energy and beds, whims, choosing fights, stats and gear, shopping at stalls, fetching from the wilds. |
| `sim/market.gd` | `Market` (`world.market`): workshops, stalls, smelting, building-posted prizes and carcass yields. |
| `sim/enemy_ai.gd` | `EnemyAI` (`world.enemy_ai`): dens and wanderers, the wave, probes, enemy targeting, hearth and tower fire. |
| `sim/unit.gd` | `Unit`: one hero, townsperson or enemy (plain fields). |
| `sim/loot.gd` | `Loot`: items as plain data `{base, tier, affixes}`; rolling, stats, how a hero rates an item. |
| `sim/seeded_rng.gd` | `SeededRng`: every random roll goes through one of these. |
| `sim/autoplayer.gd` | `AutoPlayer`: scripted player for tests and balance runs (styles: balanced, workers, heroes, market, bronze). |
| `sim/run_stats.gd` | Plain-language stats from run records (Run history screen and `tools/run_report.gd`). |
| `game/main.gd` | The one screen: runs the flow (new run, ticking, pausing for decisions) and lays out the panels. UI built in code (placeholder). |
| `game/build_panel.gd` | `BuildPanel`: build-phase choices (orders, tool sets, caravan, stall prices, the warned attack, Begin round). |
| `game/overlays.gd` | `Overlays`: dawn pick, relic pick, end screen, Run history, dev tuning. Sends choices back as signals. |
| `game/status_text.gd` | `StatusText`: the live text (status, clock, heroes, market, relics) built from the run. Read-only. |
| `game/ui_kit.gd` | `UiKit`: small shared builders (heading, button, rich text, note). |
| `game/arena_view.gd` | Draws the map with placeholder shapes; zoom, pan, hover. Read-only. |
| `game/tooltips.gd` | Hover text for map things and the build list, tag notes and supply warnings. Read-only. |
| `game/run_history.gd` | Saves runs to `user://runs/`, download/copy for sharing. |
| `data/*.json` | All content and balance numbers. Each file starts with a `_note` explaining its keys; keep it current when you add a key. |
| `tools/` | Headless helpers: `balance_run.gd` (bot runs), `run_report.gd` (compare runs), `market_probe.gd` (one run's economy), `export_csv.py` (run records to CSV tables). `snapshot.gd` saves a picture of the screen after a bot has played (needs a display: `xvfb-run` in a container). |
| `tests/` | `run_tests.gd` runs every `test_*` method in `tests/test_*.gd` (classes extend `TestCase`, use `check` / `check_eq`). `test_screen.gd` plays a run through the real UI; `test_tags.gd` enforces the tag habit. |

Flow of a round: `RunState` BUILD → for each of 3 days: PICK at dawn → SIM (`World.step()` until the next pause) → after night 3's wave: RELIC → next BUILD.

Where new code goes: a new townsfolk job goes in `FolkAI`, a hero behaviour or ability in `HeroAI`, an economy building in `Market`, an enemy behaviour in `EnemyAI`. State shared by more than one part lives on `World`; a part keeps private state only if no other part reads it (like `Market._prizes`). Parts call each other through the world (`w.market.stall_index(...)`), and a helper used from another part has no leading underscore. Avoid names Godot already uses for built-in functions (that is why it is `walk_toward`, not `move_toward`). Never move a unit by setting `pos` toward a goal yourself: go through `walk_toward`, so units go round buildings and roads count. A new panel or pop-up on the screen gets its own file in `game/` rather than growing `main.gd`.

## Habits

### 1. Content is data
Numbers, names and content go in `data/*.json`, read through `Content`. Code reads keys, never hardcodes a balance value. A new key gets a line in that file's `_note`. Keep visuals swappable: `game/` may pick colours and shapes from data but no rule may depend on art.

### 2. Tags: entities say what they are, rules key on that
Any entity can carry descriptive `tags` in its data: enemies, hero classes, traits, townsfolk roles, buildings, item bases and relics (`Content.TAG_KINDS`). A wolf is `animal`, `sentient`, `beast`. Tags are how rules pick out kinds of thing without naming ids, so new relics, hero abilities, buildings and mechanics should key on tags ("+damage against `undead`", "the hunting lodge pays for `beast`") rather than on lists of enemy or building ids.

Descriptive tags no rule reads yet are fine: they show in tooltips by name and give future rules something to key on. A tag starts *doing* something only when a rule reads it. Today two do:

| Tag | Read by | Effect |
| --- | --- | --- |
| `sentient` | `World.damage` | turns on whoever hits it for a while |
| `beast` | the hunting lodge's `prize` in `data/buildings.json`, used by `Market` | the lodge pays shells and extra hides per kill |

When a rule reads a tag:
1. Read it through `Content.has_tag(kind, id, tag)` or `Content.unit_has_tag(unit, tag)` (a unit carries its type's tags; a hero also carries its trait's), with the tag written in quotes. Never check ids or names instead.
2. Explain it for players in `data/tags.json`. The hover tooltip then shows `tag: what it does`. Prize tags are explained from `buildings.json` automatically.
3. Make sure the entities it should apply to carry it in data, and add a test that the rule fires.
4. `tests/test_tags.gd` scans `sim/` and `game/` for `has_tag(...)` calls and fails if a read tag has no `tags.json` line, if nothing carries it, or if `tags.json` explains a tag no rule reads any more.
5. A behaviour only one entity will ever have can be a specific data key instead (like `shield` or `war_chant`); if a second entity might want it, make it a tag.

Tooltips show tags for creatures today (`Tooltips.tag_notes(run, kind, id)` works for any kind); when heroes, buildings or items get tags, show them in those tooltips too.

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
