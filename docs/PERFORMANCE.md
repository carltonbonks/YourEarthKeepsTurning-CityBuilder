# Performance and town size

Yusuf expects late bronze and medieval towns to grow large (2026-10-13), so the sim should keep each step cheap as people are added.

## Where it stands

Measured 2026-10-13 with `tools/perf_probe.gd` (native headless; a bot's round-8 town padded with extra townsfolk, plus one raider per three people charging in). Time per `World.step()`:

| People | Before (ms, avg / worst) | After (ms, avg / worst) |
| --- | --- | --- |
| 60 | 2.6 / 28 | 2.7 / 29 |
| 175 | 8.6 / 57 | 7.0 / 50 |
| 400 | 30 / 272 | 17.5 / 115 |
| 850 | 114 / 797 | 35 / 292 (the worst is the probe's first step, when 1,100 new units all find a first route) |

Budget: 10 steps per game second, so 1x speed allows 100 ms a step, 4x 25 ms, 8x 12 ms (the web export is slower than native; not measured). So about 400 people run at 4x and 850 at 2x. Cost now grows roughly in line with the number of people, not with its square: about 30 microseconds per unit per step.

Medieval towns (2026-10-13, after the medieval age): the same probe on the medieval bot's round-12 town (`style=medieval round=12`, more buildings and a 5th ring) takes 3.4 / 10.2 / 21.5 / 46.6 ms on average for 60 / 175 / 400 / 850 people, so 400 people still run at 4x. The round-8 numbers above are unchanged by the medieval age (37 ms at 850).

## What was done (seeded runs unchanged)

All of these give the same results as before: 96 seeded bot runs across four styles came out byte-identical.
- `UnitGrid` (`sim/unit_grid.gd`): `World.nearest_enemy` and `nearest_friend` look only in nearby buckets. The grids are rebuilt each step at moments those units stand still: enemies before townsfolk and heroes act, friends before enemies act. Outside those moments, and for lookups longer than `World.GRID_LOOKUP_MAX`, the lookups scan the list as before.
- `FolkAI.begin_step` indexes warriors once per step for their patrol slots, instead of each warrior filtering everyone.
- `Pathing.REROUTES_PER_STEP`: at most 64 units that already have a route re-route in one step. That smooths the stalls when a building finishes (every route goes stale) or dusk sends everyone home. Units over the cap keep their old route, or walk straight at a new goal, for a step or two. Bot towns never reach the cap.

## What costs time now (850 people)

- Walking (`World.walk_toward`): about 20 ms, of which route-finding (`Pathing.find_path`, AStarGrid2D) is about 8 ms. The rest is per-unit bookkeeping: treading trails, corner cutting, speed lookups.
- Hero targeting (`HeroAI._choose_target`): about 7 ms. Every hero scores every enemy, so it grows with heroes x enemies. If late-game towns have dozens of heroes, limit the scoring to enemies within reach using the grid. That changes which target wins in rare cases, so it needs a bot check.
- Night healing and fleeing checks (`nearest_enemy` per townsperson): about 8 ms.

## Going further

- Past about 1,000 people the cheapest route is design, not tuning: CLAUDE.md already says townsfolk are handled in aggregate. Simulate distant or idle townsfolk as crews (one unit standing for several people), and keep heroes individual.
- Per-unit GDScript work (about 30 microseconds) is the floor. Moving `Pathing` or the folk tick to C# or a GDExtension would cut it several times over, at the cost of a second language in the project.
- Drawing: see "Drawing the map" below.

## Drawing the map (2026-10-29, rendered art slice 5)

`tools/draw_probe.gd` times `ArenaView._draw` itself (`draw_usec`: the script's work, not the graphics card's) on the same padded round-8 town, paused, at the tilted view's usual zoom, with the rendered art on and off. Measured in a cloud container under xvfb (slow CPU, like the step numbers above); the web build is slower again.

| People | Art on (ms, avg / worst) | Art off | Art on before slice 5's fixes |
| --- | --- | --- | --- |
| 60 | 12.3 / 32 | 11.6 / 26 | 16.5 / 37 |
| 175 | 18.0 / 38 | 16.5 / 30 | 22.6 / 46 |
| 400 | 26.9 / 74 | 23.5 / 68 | 35.3 / 55 |

Budget (docs/ART_SPEC.md): the art may add at most a quarter to the map's drawing; it adds about 1 to 3.5 ms (6 to 14%). Slice 5's fixes: `_scale()` and the ground rings' screen offsets are worked out once instead of thousands of times a frame, the nodes this age shows and the standing obstacles are listed once (`_refresh_standing`), and the plates' props remember which stand clear of nodes (`GroundProps._clear`).

What costs time now: townsfolk, at about 30 microseconds each per frame with or without art (spot, shadow, marker, bars), so 175 people take about 5.5 ms. A 60 fps frame has 16.7 ms, so towns past about 150 people drop below 60 fps on the web. Next steps if that shows in play: draw townsfolk far from the camera as plain dots, skip bars for the unhurt, or batch the shadows into one polygon list.

## How to measure

```sh
~/godot/godot --headless --path . -s res://tools/perf_probe.gd -- people=60,175,400,850 seed=4821 round=8
xvfb-run -a ~/godot/godot --path . -s res://tools/draw_probe.gd -- people=60,175,400
```

To show that an optimisation changes nothing, compare seeded bot records before and after, for example by running `OUT=<dir> LABEL=x tools/balance.sh 24` in a worktree of `main` and on your branch, then `cmp` the `.jsonl` files.
