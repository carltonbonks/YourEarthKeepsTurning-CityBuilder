# Your Earth Keeps Turning (working title)

Hobbyist city-builder roguelite, co-built with Claude. Design intent lives in [CLAUDE.md](CLAUDE.md).

## Play it

Every change merged to `main` is published as a browser build:
**https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/**

No install needed. Desktop Chrome, Edge or Firefox recommended.
Add `?seed=1234` to the address to replay a specific run.

### How the slice plays

Survive 10 rounds. Each round:
1. **Decide.** See the coming wave, post per-kill bounties on enemy types, recruit heroes, build markets, repair the keep.
2. **Watch.** The wave resolves on its own. Heroes pick targets from their personality: greedy ones chase bounties, dutiful ones guard the keep, cautious ones retreat early. Without a bounty, heroes only go as far from the keep as their nature allows.
3. **Pick a relic** (1 of 3). Heroes spend their own bounty gold on gear.

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
godot --headless --path . -s res://tools/balance_run.gd -- runs=200 style=shaman   # balance report
```

Run history: the game saves every run (Run history button). Copy one into chat, or compare many:

```sh
godot --headless --path . -s res://tools/balance_run.gd -- runs=200 style=shaman out=sim.jsonl
godot --headless --path . -s res://tools/run_report.gd -- in=sim.jsonl in=my_runs.json
```

Balance report styles (a scripted player): `none` (no bounties), `common` (5g on the most numerous enemy), `shaman` (10g on shamans), `bounty` (10g on the toughest enemy).
