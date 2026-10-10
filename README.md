# Your Earth Keeps Turning (working title)

Hobbyist city-builder roguelite, co-built with Claude. Design intent lives in [CLAUDE.md](CLAUDE.md).

## Play it

Every change merged to `main` is published as a browser build:
**https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/**

No install needed. Desktop Chrome, Edge or Firefox recommended.
Add `?seed=1234` to the address to replay a specific run. Add `&dev=1` for developer tools such as skipping ahead.

### How it plays (slice 2)

A handful of people around a fire, in the middle of a map. Resources ring the camp, monster dens sit far out in the wilds. Survive 10 rounds. Each round:
1. **Build.** Order huts, watch posts, a longhouse or drying racks. Craftspeople raise them during the day. You also see where the round's attack will come from.
2. **Three days and nights.** At each dawn, pick one newcomer from three cards (tribesperson, warrior, craftsperson, or a hero once a longhouse stands). Then everyone acts on their own: tribespeople gather and patch the hearth, warriors patrol, heroes hunt at the dens by day for glory and loot. Everyone eats food each day and the fire burns fuel each night.
3. **Night 3 brings the warned attack.** Survive it, then **pick a relic** (1 of 3). Heroes spend their own shells on gear.

## Layout

| Folder | What lives there |
| --- | --- |
| `sim/` | Game rules and simulation. No graphics, so it can run headless for tests and balance runs. |
| `game/` | Scenes, UI and visuals that show the simulation. |
| `data/` | Balance numbers and content (heroes, enemies, relics) as JSON files. |
| `tools/` | Headless helpers, e.g. the balance report. |
| `tests/` | Automated tests for `sim/`. |

## For developers

Engine: Godot 4.7.1 (GDScript). The CI workflow in `.github/workflows/ci.yml` shows the exact commands.

```sh
godot --headless --path . --import                       # first time / after adding files
godot --headless --path . -s res://tests/run_tests.gd    # run tests
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . -s res://tools/balance_run.gd -- runs=50 style=balanced   # balance report
```

Run history: the game saves every run (Run history button). Copy one into chat, or compare many:

```sh
godot --headless --path . -s res://tools/balance_run.gd -- runs=50 style=balanced out=sim.jsonl
godot --headless --path . -s res://tools/run_report.gd -- in=sim.jsonl in=my_runs.json
```

Balance report styles (a scripted player): `balanced` (huts, a longhouse, watch posts, picks by need), `workers` (never takes heroes), `heroes` (rushes the longhouse, takes every hero it can afford).
