# Your Earth Keeps Turning (working title)

Hobbyist city-builder roguelite, co-built with Claude. Design intent lives in [CLAUDE.md](CLAUDE.md).

## Play it

Every change merged to `main` is published as a browser build:
**https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/**

No install needed. Desktop Chrome, Edge or Firefox recommended.
Add `?seed=1234` to the address to replay a specific run. Add `&dev=1` for developer tools such as skipping ahead.

The screen is kept short: a thin bar of key numbers on top, the map, and your heroes and the latest story underneath. Point at anything (a number on the bar, a hero, a card, something on the map) for the detail. Space pauses, Esc opens the menu (seed, new run, Run history), V tilts the map.

### How it plays

A handful of people around a fire, in the middle of a map. Resources ring the camp, monster dens sit far out in the wilds. Survive 14 rounds. Each round:
1. **Build.** A hand of building cards lies along the bottom of the map: homes and food are always on offer, the rest is dealt each round, and a card the town needs says why at the top (for example "Recommended: food runs out in 2 days"). Order huts, watch posts, garden patches (a little food every dawn), drying racks, hero lodgings (a longhouse, a mead hall or a spirit shrine), and the market and its workshops. Craftspeople raise them during the day, and each building picks its own plot in the rings round the hearth: homes and lodgings near the fire, stalls and workshops round the market, watch posts facing the warned attack and spread apart (unless they guard a gate), the hunting lodge and stone-layers' yard on the edge, and a gate beside buildings (best in a gap between two) where the busiest path runs. Plots touch, so a row of buildings is a wall that everyone (raiders too) has to walk round. Sentient raiders a watch post shoots may turn on it; a broken post stops shooting until it is mended at dawn. A card in the map's top-right corner shows where the round's attack will come from and your town's power against it, and the Begin round button. Hover over anything on the map or a card for what it does, its tags, and warnings such as a stall with no workshop feeding it.
2. **Three days and nights.** At each dawn, pick one newcomer from three cards (tribesperson, warrior, craftsperson, or a hero once any lodging stands). A townsperson who stands out can be offered as a Promote card instead: a veteran warrior becomes a champion hero, a busy craftsperson a named master. Then everyone acts on their own: tribespeople gather and patch the hearth, warriors patrol, heroes follow the day's whim (hunt, guard, sleep in, carouse) and hunt at the dens for loot and XP. Everyone, heroes included, eats 1 food each dawn; if there isn't enough, a townsperson walks away, heroes sulk, and nobody of that kind comes to that dawn's pick.
3. **Getting around.** Everyone finds their own way round buildings, boulders and old oaks, and around the thickets out in the wilds. Ground people walk a lot wears into a trail, and a busy trail into a worn path (each a little faster); idle ones fade. A stone-layers' yard lets craftspeople pave the busiest worn paths for stone (much faster, and cobbles in the bronze age). Raiders use paths and roads too. A gate across a busy path lets your people through but raiders must batter it down or go round; watch posts like to stand near gates. New buildings go over trails freely and keep off paving, lifting the stones (back into stock) only when nothing else is free. The bronze age opens a fourth ring of plots.
4. **Heroes run on energy and mood.** They tire as they work and fight, go to bed when tired and at nightfall, and only wake when an enemy comes close. Each personality has a favourite lodging. Hunger, cold, sleeping rough and comrades dying sour their mood; a favourite bed, shopping and prizes lift it. An unhappy hero walks away.
5. **The market.** Stalls (arms, armour, charms, provisions) sell to heroes, fed by workshops (knapper, hide rack, bone carver, smoke hut) that craftspeople staff. A hunting lodge pays heroes a prize for every beast.
6. **The bronze age.** Raise the Bronze moot (costly, your choice when) to unlock copper seams, the smelter, the bronzesmith, bronze tool sets for townsfolk groups and a caravan selling tin, timber and stone (both appear as cards in the building hand). Heroes fetch cassiterite from near the dens. Bronze reavers arrive from round 6 and shrug off stone blows.
7. **The medieval age.** Once the bronzesmith stands and 12 people live in town, raise the Stone keep (it shoots, and adds health to the hearth) to open a fifth ring of plots, bog iron in the marshes, the charcoal burner, bloomery and blacksmith (iron, then steel), townhouses, fields worked by tribespeople, family cards at dawn (several newcomers at once), the guildhall (knights answer the call, and a veteran champion can be knighted) and the chapel. From round 10 come men-at-arms in mail, battering rams that ignore people and go for gates and the hearth, and hollow knights from the barrows; steel cuts through their mail. The Black Margrave leads the last attack.
8. **Night 3 brings the warned attack.** Survive it, then **pick a relic** (1 of 3). Attacks grow every round on a fixed schedule; if your town has fallen far behind, the warband holds some raiders back (the story tells you), but a strong town never faces a bigger attack for being strong.

## Layout

| Folder | What lives there |
| --- | --- |
| `sim/` | Game rules and simulation. No graphics, so it can run headless for tests and balance runs. |
| `game/` | Scenes, UI and visuals that show the simulation. |
| `data/` | Balance numbers and content (heroes, enemies, relics) as JSON files. |
| `tools/` | Headless helpers, e.g. the balance report and Godot setup. |
| `docs/` | [DEVELOPMENT.md](docs/DEVELOPMENT.md): code map and development habits. [PENDING_DEFAULTS.md](docs/PENDING_DEFAULTS.md): Claude's design defaults still waiting for a playtest. [PERFORMANCE.md](docs/PERFORMANCE.md): how the sim copes with big towns. |
| `tests/` | Automated tests for `sim/`. |

## For developers

Engine: Godot 4.7.1 (GDScript). Read [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) first. `tools/setup_godot.sh` downloads Godot to `~/godot/godot` (Linux); the CI workflow in `.github/workflows/ci.yml` shows the exact commands.

```sh
tools/setup_godot.sh                                     # get Godot (Linux), once
tools/test.sh                                            # import and run every test (tools/test.sh market: only matching tests)
tools/balance.sh 60 balanced workers                     # bot win rates, styles in parallel
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . -s res://tools/balance_run.gd -- runs=50 style=balanced   # balance report
```

Run history: the game saves every run (Run history button). Copy one into chat, or compare many:

```sh
godot --headless --path . -s res://tools/balance_run.gd -- runs=50 style=balanced out=sim.jsonl
godot --headless --path . -s res://tools/run_report.gd -- in=sim.jsonl in=my_runs.json
```

Balance report styles (a scripted player): `balanced` (huts, a longhouse, watch posts, picks by need), `workers` (never takes heroes), `heroes` (rushes the longhouse, takes every hero it can afford), `market` (builds every workshop, stall and the hunting lodge early), `bronze` (like market, then ages up as soon as it can), `medieval` (like bronze, then raises the Stone keep and uses the medieval buildings). `tools/market_probe.gd -- seed=4821 style=market` prints one run's economy round by round. `tools/snapshot.gd` saves a picture of the screen after a bot has played some rounds (needs a display; see the file).
