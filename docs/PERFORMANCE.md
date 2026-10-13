# Performance and town size

Measured 2026-10-12 (native headless, a bot's round-8 town padded with extra townsfolk, plus one raider per three people). Time per `World.step()` by day:

| People | ms per step |
| --- | --- |
| ~20 (bot today) | 1 |
| 60 | 3 |
| 175 | 15 |
| 400 | 63 |
| 850 | 250, with stalls over 1 s |

Budget: 10 steps per game second, so 8x speed leaves about 12 ms a step (less in the web export, which is slower than native). Fine up to roughly 150 people; a 1000-person town is unplayable as the code stands.

Where the time goes (all grow with people squared), cheapest fix first:
- Idle craftspeople re-run `FolkAI._choose_work` every step, and `Market.workshop_needing_hands` filters all folk for each workshop. Fix: let idle workers wait before looking again, and count hands per workshop once per step.
- `FolkAI._warrior_tick` filters all folk to find its patrol slot. Fix: index warriors once per step. (A quick try of these first two fixes took 400 people from 63 to 27 ms.)
- `World.nearest_enemy` / `nearest_friend` scan every unit, and `EnemyAI.dens_tick` and `war_chant` scan every enemy. Fix: a spatial grid of buckets so lookups only check nearby squares.
- Stalls: a building finishing bumps `Pathing.version`, and every unit re-routes in the same step. Fix: stagger re-routing over several steps, or share routes (a flow field to the hearth for raiders).
- Drawing (`game/arena_view.gd`) is not the bottleneck at these sizes (judged from the code, not measured).

Past a few hundred people the better route is design, not tuning: CLAUDE.md already says townsfolk are handled in aggregate, so simulate them as crews and keep heroes individual.

To re-measure: pad a run with `w.folk_ai.add_folk(role)` after the bot reaches the round you want, top up stock at each dawn, and time `run.step()` with `Time.get_ticks_usec()`.
