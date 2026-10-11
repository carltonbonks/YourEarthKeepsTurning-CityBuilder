# Your Earth Keeps Turning (working title)

Hobbyist city-builder roguelite, co-built with Claude. Design intent lives in [CLAUDE.md](CLAUDE.md).

## Play it

Every change merged to `main` is published as a browser build:
**https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/**

No install needed. Desktop Chrome, Edge or Firefox recommended.
Add `?seed=1234` to the address to replay a specific run. Add `&dev=1` for developer tools such as skipping ahead.

### How it plays (slice 4)

A handful of people around a fire, in the middle of a map. Resources ring the camp, monster dens sit far out in the wilds. Survive 10 rounds. Each round:
1. **Build.** Order huts, watch posts, drying racks, and hero lodgings: a longhouse, a mead hall or a spirit shrine. Craftspeople raise them during the day. You also see where the round's attack will come from.
2. **Three days and nights.** At each dawn, pick one newcomer from three cards (tribesperson, warrior, craftsperson, or a hero once any lodging stands). Then everyone acts on their own: tribespeople gather and patch the hearth, warriors patrol, heroes follow the day's whim (hunt, guard, sleep in, carouse) and hunt at the dens for loot and XP.
3. **Heroes run on energy.** They tire as they work and fight, go to bed when tired and at nightfall, and only wake when an enemy comes close to where they sleep. Each personality has a favourite lodging: the mead hall rests them fast and earns shells but they sleep deeply; the shrine heals them and they wake at the first sign of danger. Heroes without a bed sleep by the hearth and recover slowly.
4. **The market.** Build a market square, then stalls (arms, hides, charms, provisions) and the workshops that feed them (knapper, hide rack, bone carver, smoke hut). Craftspeople work the benches when they have nothing to raise. Tribespeople dig flint; beasts give hides and bone when they die; heroes bring obsidian back from the wilds once a knapper stands. Heroes shop by day with their own shells, and the shells go to the settlement. You set each stall's price (Cheap, Fair or Dear) at the start of a round. A hunting lodge pays heroes a prize for every beast.
5. **Night 3 brings the warned attack.** Survive it, then **pick a relic** (1 of 3). Heroes sell the loot they don't wear (the settlement keeps a cut).

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

Balance report styles (a scripted player): `balanced` (huts, a longhouse, watch posts, picks by need), `workers` (never takes heroes), `heroes` (rushes the longhouse, takes every hero it can afford), `market` (builds every workshop, stall and the hunting lodge early). `tools/market_probe.gd -- seed=4821 style=market` prints one run's economy round by round.
