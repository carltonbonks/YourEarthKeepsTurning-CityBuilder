# Your Earth Keeps Turning (working title)

Hobbyist city-builder roguelite, co-built with Claude. Design intent lives in [CLAUDE.md](CLAUDE.md).

## Play it

Every change merged to `main` is published as a browser build:
**https://carltonbonks.github.io/YourEarthKeepsTurning-CityBuilder/**

No install needed. Desktop Chrome, Edge or Firefox recommended.

## Layout

| Folder | What lives there |
| --- | --- |
| `sim/` | Game rules and simulation. No graphics, so it can run headless for tests and balance runs. |
| `game/` | Scenes, UI and visuals that show the simulation. |
| `data/` | Balance numbers and content (buildings, heroes, relics) as data files. |
| `tests/` | Automated tests for `sim/`. |

## For developers

Engine: Godot 4.7.1 (GDScript). The CI workflow in `.github/workflows/ci.yml` shows the exact commands.

```sh
godot --headless --path . --import                       # first time / after adding files
godot --headless --path . -s res://tests/run_tests.gd    # run tests
godot --headless --path . --export-release "Web" build/web/index.html
```
