# Developer guide

How the code is laid out and the habits every change follows. Design intent lives in [CLAUDE.md](../CLAUDE.md); this file is the "how". If the two disagree, CLAUDE.md wins and this file gets fixed.

## Getting started

```sh
tools/setup_godot.sh          # downloads Godot 4.7.1 to ~/godot (once per machine; cloud sessions do it at start, see .claude/hooks)
tools/test.sh                 # imports, runs every test (~75 s), fails on any script error
tools/test.sh market gate     # only tests whose "file::method" contains a filter; use while working, then run all once
QUICK=1 tools/test.sh town    # skips the import step (fine unless you added a script, class_name or resource)
tools/balance.sh 60 balanced workers   # bot win rates, one style per core at once
```

Tests over 2 s print their time. Most of the suite is whole bot runs: a test that only reads a finished run's record should use `bot_record(seed, style)` from `TestCase`, which plays each seed and style once per test run and shares it.

All tests must pass before a PR; CI runs `tools/test.sh` too (see `.github/workflows/ci.yml`). A GDScript error stops a test part-way without failing a check, which is why `tools/test.sh` also fails on any `SCRIPT ERROR` in the log: never run `tests/run_tests.gd` alone and trust its count.

## Code map

The split that matters: **`sim/` is the game, `game/` only shows it.** Nothing in `sim/` touches scenes or nodes, so whole runs play headless for tests and bot balance runs. Nothing in `game/` changes the run except through `RunState`'s public methods (build, choose_pick, choose_relic, set_price, ...).

| File | Role |
| --- | --- |
| `sim/content.gd` | `Content`: loads every `data/*.json` once. The only place data is read. Helpers such as `has_tag` / `unit_has_tag`, `age_reached`, `recipes_for`. |
| `sim/run_state.gd` | `RunState`: one run. Phases (BUILD, PICK, SIM, RELIC, WON, LOST), stock, building orders, taking dawn cards, relics (`mod()`), ages, tool sets and the caravan, upkeep (food, fuel, fields). Its three parts below hold the rest. |
| `sim/people.gd` | `People` (`run.people`): dealing the dawn cards (townsfolk, heroes, families, Promote cards), promotions and knighting, making and adding heroes, hero mood and heroes leaving, levelling, healing and selling finds between rounds. |
| `sim/build_hand.gd` | `BuildHand` (`run.hand`): the round's building cards. Deals a hand weighted toward what the town needs (`need`), the ageing-up card (`milestone`), ordering from a card (`order`, which calls `RunState.build`) and the once-a-round redraw. The player and `AutoPlayer` order only through it; `RunState.build` is the raw rule tests use for setup. |
| `sim/wave_planner.gd` | `WavePlanner` (`run.waves`): each round's wave from its budget, bosses on their `boss_round`, catch-up easing (`plan`), early-night probes, the wave preview (`counts`). |
| `sim/run_record.gd` | `RunRecord` (`run.record`): the run's history. `to_record()`, `RECORD_FORMAT` and its changelog, the round being played (`entry`) and every `note_*` logger other parts call. |
| `sim/world.gd` | `World`: the map and everything on it, stepped in fixed ticks. Owns all world state, the day/night clock, the map, and the shared movement and combat helpers (`walk_toward`, `fight`, `hit`, `damage`, `nearest_enemy`). Every move goes through `walk_toward`, which asks `Pathing` for the next point and walks faster on trails and roads. Pauses at dawn and at round end for `RunState`. Behaviour lives in four parts it creates: |
| `sim/town.gd` | `Town` (`world.town`): the ring town. Plots in rings and sectors round the hearth, obstacles, thickets, where a new building goes (`choose_plot`: its `near` key, off paving if it can, never walling off the hearth; a gate in the busiest gap), what building over ground does (`occupy`: trails vanish, paving is lifted and refunded), paving the busiest worn paths (`next_to_pave`, `pave`) and gates (`on_built`, `patch_walls`, `gate_health`). |
| `sim/pathing.gd` | `Pathing` (`world.pathing`): the ground as a grid of squares (solid or open; plain, thicket, trail, worn path or a road kind; gate health) and how units find their way (`next_point`, Godot's AStarGrid2D: one grid for townsfolk and heroes, who walk through gates, and one for raiders, where gates cost extra). Raiders that walk into a gate batter it (`World.walk_toward`). Walking straight when that is as quick, cached routes otherwise; desire paths worn by feet (`tread`, `wear_trails` at dawn, which also lists `busy_paths` for paving). |
| `sim/folk_ai.gd` | `FolkAI` (`world.folk_ai`): townsfolk. Warriors patrol and answer calls; workers gather (each plans its trip: `plan_trip`), haul, build, craft and patch the hearth. |
| `sim/hero_ai.gd` | `HeroAI` (`world.hero_ai`): heroes. Energy and beds, whims, choosing fights, stats and gear, shopping at stalls, fetching from the wilds. |
| `sim/market.gd` | `Market` (`world.market`): workshops, stalls, smelting, building-posted prizes and carcass yields. |
| `sim/enemy_ai.gd` | `EnemyAI` (`world.enemy_ai`): dens and wanderers, the wave, probes, enemy targeting, hearth and tower fire, sentient raiders breaking towers that shot them (`mend_towers` at dawn). |
| `sim/unit.gd` | `Unit`: one hero, townsperson or enemy (plain fields). |
| `sim/unit_grid.gd` | `UnitGrid`: buckets units by position so `World.nearest_enemy` / `nearest_friend` only look nearby. Same answers as a full scan. |
| `sim/loot.gd` | `Loot`: items as plain data `{base, tier, affixes}`; rolling, stats, how a hero rates an item. |
| `sim/seeded_rng.gd` | `SeededRng`: every random roll goes through one of these. |
| `sim/autoplayer.gd` | `AutoPlayer`: scripted player for tests and balance runs (styles: balanced, workers, heroes, market, bronze, medieval). |
| `sim/power.gd` | `Power`: power levels. A fighter rates sqrt(effective HP x damage per second); the town (heroes, `fighter` townsfolk, hearth and towers) and a wave are sums on the same scale. Logged per round as `power`. `RunState.plan_wave` uses it for catch-up: a wave that far outmatches the town is eased (never grown). |
| `sim/run_stats.gd` | Plain-language stats from run records (Run history screen and `tools/run_report.gd`). |
| `game/main.gd` | The one screen: runs the flow (new run, ticking, pausing for decisions) and lays out the panels. UI built in code (placeholder). |
| `game/build_panel.gd` | `BuildPanel`: the rest of the build phase (tool sets, caravan, paths, the warned attack with both power levels and any catch-up, Begin round). |
| `game/build_hand_view.gd` | `BuildHandView`: the building cards as a heads-up hand along the bottom of the map, with each card's "Recommended: ..." line (`recommendation`) and the redraw. |
| `game/overlays.gd` | `Overlays`: dawn pick, relic pick, end screen, Run history, dev tuning. Sends choices back as signals. |
| `game/status_text.gd` | `StatusText`: the live text (status, clock, heroes, market, relics) built from the run. Read-only. |
| `game/ui_kit.gd` | `UiKit`: small shared builders (heading, button, rich text, note). |
| `game/arena_view.gd` | Draws the map with placeholder shapes, tilted (isometric, everything standing drawn back to front) or flat (V toggles); zoom, pan, hover. Read-only: only the projection (`_to_screen` / `_to_world`) knows about the tilt. |
| `game/tooltips.gd` | Hover text for map things and the build list, tag notes and supply warnings. Read-only. |
| `game/run_history.gd` | Saves runs to `user://runs/`, download/copy for sharing. |
| `data/*.json` | All content and balance numbers. Each file starts with a `_note` explaining its keys; keep it current when you add a key. |
| `tools/` | Headless helpers: `test.sh` (tests), `balance.sh` / `balance_run.gd` (bot runs), `run_report.gd` (compare runs), `market_probe.gd` (one run's economy), `perf_probe.gd` (ms per step as the town grows), `export_csv.py` (run records to CSV tables). `snapshot.gd` saves a picture of the screen after a bot has played (needs a display: `xvfb-run` in a container). |
| `tests/` | `run_tests.gd` runs every `test_*` method in `tests/test_*.gd` (classes extend `TestCase`, use `check` / `check_eq`). `TestCase.bot_record(seed, style)` shares finished bot runs between tests. `test_screen.gd` plays a run through the real UI; `test_tags.gd` enforces the tag habit. |

Flow of a round: `RunState` BUILD → for each of 3 days: PICK at dawn → SIM (`World.step()` until the next pause) → after night 3's wave: RELIC → next BUILD.

Big towns: anything that runs for every unit every step must not loop over every other unit (that grows with people squared). Use `nearest_enemy` / `nearest_friend` (grid-backed), or build an index once per step (like `FolkAI.begin_step`). Check with `tools/perf_probe.gd` (see [PERFORMANCE.md](PERFORMANCE.md)).

Where new code goes: a new townsfolk job goes in `FolkAI`, a hero behaviour or ability in `HeroAI`, an economy building in `Market`, an enemy behaviour in `EnemyAI`. State shared by more than one part lives on `World`; a part keeps private state only if no other part reads it (like `Market._prizes`). Parts call each other through the world (`w.market.stall_index(...)`), and a helper used from another part has no leading underscore. Avoid names Godot already uses for built-in functions (that is why it is `walk_toward`, not `move_toward`). Never move a unit by setting `pos` toward a goal yourself: go through `walk_toward`, so units go round buildings and roads count. A new panel or pop-up on the screen gets its own file in `game/` rather than growing `main.gd`.

## Habits

### 1. Content is data
Numbers, names and content go in `data/*.json`, read through `Content`. Code reads keys, never hardcodes a balance value. A new key gets a line in that file's `_note`. Keep visuals swappable: `game/` may pick colours and shapes from data but no rule may depend on art.

### 2. Tags: entities say what they are, rules key on that
Any entity can carry descriptive `tags` in its data: enemies, hero classes, traits, townsfolk roles, buildings, item bases and relics (`Content.TAG_KINDS`). A wolf is `animal`, `sentient`, `beast`. Tags are how rules pick out kinds of thing without naming ids, so new relics, hero abilities, buildings and mechanics should key on tags ("+damage against `undead`", "the hunting lodge pays for `beast`") rather than on lists of enemy or building ids.

Descriptive tags no rule reads yet are fine: they show in tooltips by name and give future rules something to key on. A tag starts *doing* something only when a rule reads it. Today these do:

| Tag | Read by | Effect |
| --- | --- | --- |
| `sentient` | `World.damage`, `EnemyAI.towers_tick` | turns on whoever hits it for a while, towers (`tower_hp`) included |
| `fighter` | `Power.town` | a townsfolk role that counts toward the town's power level |
| `beast` | the hunting lodge's `prize` in `data/buildings.json`, used by `Market` | the lodge pays shells and extra hides per kill |
| `undead` | the chapel's `prize`, and the reliquary's `bane` in `data/items.json` (`Loot.bane`) | the chapel pays per kill; reliquaries hit them harder |
| `siege` | `EnemyAI.enemy_tick`, `World._batter` | ignores people, goes for gates and the hearth (battering rams) |
| `proud` | `People.update_moods` | knights: sleeping rough hurts twice as much, wearing steel cheers them |

When a rule reads a tag:
1. Read it through `Content.has_tag(kind, id, tag)` or `Content.unit_has_tag(unit, tag)` (a unit carries its type's tags; a hero also carries its trait's), with the tag written in quotes. Never check ids or names instead.
2. Explain it for players in `data/tags.json`. The hover tooltip then shows `tag: what it does`. Prize tags are explained from `buildings.json` automatically.
3. Make sure the entities it should apply to carry it in data, and add a test that the rule fires.
4. `tests/test_tags.gd` scans `sim/` and `game/` for `has_tag(...)` calls and fails if a read tag has no `tags.json` line, if nothing carries it, or if `tags.json` explains a tag no rule reads any more.
5. A behaviour only one entity will ever have can be a specific data key instead (like `shield` or `war_chant`); if a second entity might want it, make it a tag.

Tooltips show tags for creatures only (`Tooltips.tag_notes(run, kind, id)` works for any kind). Knights' `proud` is the first hero tag a rule reads and the hero tooltip doesn't show it yet; when heroes, buildings or items get tags players need to see, show them in those tooltips too.

### 3. Determinism
All randomness goes through the run's `SeededRng` (never `randi()`/`randf()`), and the sim steps in fixed ticks. The same seed and the same choices must give the same run, so "seed 4821, round 6" is reproducible.

### 4. Run records
Every run is saved as `RunState.to_record()` (built by `RunRecord`), used by the game's Run history, the bots and `tools/export_csv.py`. When a mechanic changes what a run looks like: extend the record (never drop or rename fields), bump `RECORD_FORMAT` in `sim/run_record.gd` with a comment saying what the new format adds, add the new fields to `tools/export_csv.py`, and keep `tests/test_run_record.gd` passing.

### 5. Tests and balance
- Every new rule gets a test in `tests/`, usually by building a `RunState` with a fixed seed and stepping it (see `tests/test_market.gd`).
- After a change that affects difficulty, run the bots and report win rates per style in the PR:
  `tools/balance.sh 60 balanced workers` (runs the styles in parallel; one style alone is `balance_run.gd -- runs=60 style=balanced`). For a before/after, run the same command on `main` in a second worktree.
  Current target (tuning pass 1): balanced 70-80%, workers clearly weaker.
- New mechanics that a scripted player should use get taught to `AutoPlayer`, otherwise bot numbers stop meaning anything.

### 6. Player-facing transparency
If players need to understand a rule to make a choice, it shows up in a tooltip (`game/tooltips.gd`) or a building's `text` in data. Supply warnings (a stall with no workshop feeding it) are the model: say what is missing and what to build.

### 7. Shipping a slice
Small slices, one PR each, from a `claude/...` branch. A PR says what changed in plain language, how to try it on the playtest link (merged to `main` = live at https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/), bot win rates if balance moved, and 2-3 playtest questions with a seed. Claude's default choices for open design questions go in [PENDING_DEFAULTS.md](PENDING_DEFAULTS.md) (one line per area, with bot numbers), and CLAUDE.md's "Open questions" names the area. Update the "How it plays" section of README.md when the game changes.

## Run data for analysis

Run records (Yusuf's downloads and bot batches) live in the project's shared folder at `game-data/raw/`, and `python3 tools/export_csv.py <raw> <csv>` rebuilds the CSV tables in `game-data/csv/` (described in `game-data/README.md` there). Bot batches: `OUT=<dir> LABEL=<label> tools/balance.sh 60` writes `bots-<label>-<style>.jsonl` per style.

## Performance

How sim cost grows with town size, where the time goes and how to re-measure: [PERFORMANCE.md](PERFORMANCE.md). Read it before adding anything that loops over every unit each step.
