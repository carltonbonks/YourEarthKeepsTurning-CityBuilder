# CLAUDE.md — City-Builder Roguelite (working title TBD)

This file tells Claude what game we're building, what matters, and how to work with Yusuf.
It's the source of truth for design intent. When code or docs drift from it, flag it and don't quietly diverge.

## Elevator pitch

You're a hands-off ruler of a frontier town. You never command units. You shape the town with buildings, production chains, incentives and drafted relics, and your heroes decide for themselves how to fight, what to loot and where to venture. Runs are 30–90 minute roguelites played in rounds, auto-battler style (like How Many Dudes). You make a few weighty decisions between rounds, then watch the systems play out.

**Reference games:** Majesty / Lessaria (indirect hero control), Against the Storm (runs, production chains, meta unlocks), Ratropolis / How Many Dudes (round-based auto-battles), Slay the Spire (relic drafting), They Are Billions / Frostpunk (pressure, defences, harsh world), Dwarf Fortress / Rimworld (emergent stories), Cult of the Lamb / Moonlighter (hub town), Loop Hero, Hades, Path of Exile 2 (itemisation).

## Design pillars (in priority order)

1. **Incremental power choices.** The roguelite drip of picking upgrades and relics that stack into a build. Every between-round decision should feel like it moves the needle.
2. **Emergent systems you watch unfold.** Heroes, townsfolk, enemies and the environment interact in ways the player didn't script. Favour systemic rules over hand-authored outcomes.
3. **Power now vs. power later.** Choices should regularly trade immediate safety against long-term scaling (economy, hero growth, relic synergies).
4. **Loot and itemisation.** Random drops, item traits and gear progression, with heroes choosing their own gear wherever that's reasonable. That keeps the player hands-off.
5. **Balancing NPC whims.** The player's job is to keep self-interested heroes and townsfolk pointed in a useful direction.

When a feature doesn't serve at least one pillar, question it.

## Core structure

- **Run:** 30–90 minutes, procedurally generated map, randomised items, relics and events.
- **Rounds:** each round has a decision phase and then an auto-resolved phase.
  - *Decision phase* (where the player's attention goes): placing and upgrading buildings and town layout, managing production chains and resources (Against the Storm), drafting relics, cards and event choices.
  - *Resolve phase:* combat and the simulation play out automatically (How Many Dudes / Ratropolis). The player mostly watches. No direct unit control.
- **Round shape (decided 2026-10-10):** a round is **3 fast day/night cycles**. At the start of the round the player builds. At each dawn they pick one newcomer from a few cards (How Many Dudes), and the buildings they own shape that pool. During each day heroes and townsfolk act on their own. The telegraphed wave comes on the third night; earlier nights bring only wanderers and small probes.
- **Map (decided 2026-10-10):** the settlement sits in the centre, with resources and threats on all sides. Monster dens far out in the wilds spawn wandering monsters. The wilds are strictly hero territory, where heroes fight for glory, loot and XP.
- **Ages (decided 2026-10-10):** runs start as a handful of tribespeople around a campfire and tech up through **neolithic, bronze and medieval**. Neolithic resources are burnable fuel (brush, dung), wood and stone, with furs and flint or obsidian for gear. **Bronze age (decided 2026-10-11):** aging up is the player's choice, a costly milestone building (power now vs. later), never automatic. Tin comes from cassiterite veins near the dens: heroes fetch it, and townsfolk can only mine it safely once heroes have cleared the nearby threats; craftspeople smelt it. A caravan may sell tin and a little cassiterite (heavy, so little of it) at a steep markup over local supply.
- **Town layout (decided 2026-10-11):** Frostpunk-style rings of plots round the hearth, adapted rather than copied. Buildings **place themselves** (Yusuf chose auto-placement over picking cells): each type prefers a ring and neighbours, plots touch so a row of buildings is a wall, and placement never cuts the hearth off. Everyone uses real pathfinding round buildings and obstacles. The player shapes the town by **staking roads** (free, by waypoints, never straight lines forced to a destination); buildings leave staked ground clear, so planning roads ahead pays off. Craftspeople with a stone-laying building pave staked roads for stone, with better road kinds in later ages. Roads speed raiders too. **Palisades and gates (decided 2026-10-12):** the player also stakes palisades, which craftspeople raise. Where a road crosses one there's a gate. Raiders keep the road bonus; walls and gates are the player's way to slow them without exposing their people.
- **Pressure:** escalating enemy waves **and** environmental hardship and scarcity. Social and moral pressure (factions, morale, Frostpunk-style choices) is a *later* layer, added only once the town's internal mechanics are deep enough to support it.
- **Victory conditions:** a mix, such as surviving waves, reaching economic or production goals, or collecting or completing certain relics and items. Vary them per run or map.

## NPCs

- **Heroes:** individuals with traits, personalities, morals and itemisation (equipment, loot). They act on their own incentives: they go out to fight, explore and loot based on their goals, and they react to bounties, buildings and town state. They should feel like characters whose stories emerge.
- **Townspeople / colonists:** mostly generic and handled **in aggregate**. They're modified, transformed and upgraded as groups (Against the Storm's races are a reference for group needs), not micromanaged one by one. Newcomers arrive through the dawn pick (for example tribesperson, warrior or craftsperson), and each one adds upkeep. A sufficiently upgraded townsperson can be promoted to an individual with traits and gear.
- **Hero recruitment:** heroes need lodging (a guild, tavern or similar). Once you have it, heroes appear as dawn cards with an extra gold recruitment cost. Heroes are scarce and capricious, and they spend energy on their own agendas, then rest at lodging that suits them.
- **Incentives come from buildings:** bounties and prizes are posted by buildings that have prerequisites, such as a hunting lodge posting prizes on beasts. There is no free bounty button.
- **Economy:** the marketplace sells goods and services directly to heroes, and each stall is fed by an upstream supply chain of buildings.
- Heroes do the **bulk of the fighting**. Static defences around the town and castle (walls, towers) help but shouldn't carry the game.

## Items and relics

- Sources: reward picks after waves or milestones (Slay the Spire), map events and exploration, and town production or markets where heroes buy gear (Majesty, Moonlighter).
- Heroes should ideally make their own loot and gear choices (automated by their personality and needs). The player shapes this indirectly.
- Relics define run-level builds and should create synergies and the power-now-or-later trade-off.

## Meta-progression (between runs)

- **Unlocks that add variety:** new buildings, hero types, relics and events (Against the Storm, Hades). Prefer variety over raw permanent stat boosts.
- **Hub town** that you build up between runs (Cult of the Lamb, Moonlighter).
- **Story across runs** (Hades-style) is a *later* goal. Don't build it now, but don't design it out.

## Art and tone

- **For now: simple placeholder art.** Keep visuals swappable (no logic coupled to specific art assets).
- Final style is undecided. The candidates are **pixel art** or **low-poly 3D**, chosen for ease of development. Claude should help evaluate the options when the prototype is playable.
- **Setting and tone (decided 2026-10-10):** historical fiction with dark fantasy mixed in, kept a little mystical. A people rises from stone to steel across the three ages.

## Technical direction

- **Engine:** Godot 4.x (GDScript unless there's a strong reason for C#).
- **Platform:** PC, targeting Steam.
- **Goal:** mostly a hobby and learning project, but build it to **SDLC practices compatible with a future Steam release**:
  - Git with meaningful commits, feature branches and PRs.
  - Automated tests for core simulation logic (e.g. GUT for Godot) and CI (GitHub Actions) that runs them, plus headless export builds.
  - Data-driven content (buildings, heroes, relics, items and enemies defined in resource/data files, not hardcoded) so balancing and modding stay easy.
  - Keep simulation logic separate from presentation, so the auto-resolve phase can run headless for tests and balance simulations.
  - **Tags (proposed by Yusuf 2026-10-10):** entities carry descriptive tags in their data (e.g. a wolf is `animal`, `sentient`, `beast`), and rules key on a few of them (sentient creatures turn on whoever hits them). Descriptive tags are fine (decided 2026-10-11), and upcoming relics, hero abilities, buildings and mechanics will key on tags. A tag only does something when a rule reads it, and every tag a rule reads is explained to players in `data/tags.json`, which hover tooltips show (see docs/DEVELOPMENT.md).
  - Deterministic, seedable RNG, so runs are reproducible for debugging and balancing.
  - Versioned save formats, settings, and input remapping. Plan for the Steamworks integration points (achievements, cloud saves) without building them early.
- **Yusuf's background:** low familiarity with code. They understand SDLC concepts from years around software projects, but have written very little code and no end-to-end programs. Claude owns build, test, troubleshoot and deploy end to end. Explain technical choices in plain language, never ask Yusuf to debug or edit code, and give one-click or one-command ways to run things.

## Working in the code (read first)

**[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) is the code map and the habits every change follows.** The short version:
- `sim/` is the game and runs headless; `game/` only shows it and never changes rules. Content and numbers live in `data/*.json`, read through `Content`, each file with a `_note` explaining its keys.
- Tags: any entity (enemy, hero class, trait, townsfolk role, building, item base, relic) can carry descriptive tags, and relics, abilities, buildings and mechanics key on tags rather than ids. Rules read them only via `Content.has_tag` / `unit_has_tag`; a tag a rule reads gets a player-facing line in `data/tags.json` (`tests/test_tags.gd` enforces it).
- All randomness goes through `SeededRng`. Run records only grow: new fields, bump `RECORD_FORMAT`, update `tools/export_csv.py`.
- Every rule gets a test; balance-affecting changes report bot win rates; new mechanics are taught to `AutoPlayer`.
- Setup and tests: `tools/setup_godot.sh` once, then `tools/test.sh` (also fails on script errors). New behaviour goes in the matching `World` part (`FolkAI`, `HeroAI`, `Market`, `EnemyAI`) and new UI in its own `game/` file.

## Fast iteration (dev-cycle priority)

Yusuf must be able to try changes and give feedback quickly, without heavy builds. This keeps token cost down and keeps development interactive.
- **Small slices:** ship the smallest playable change that answers a design question, then get feedback before building more.
- **Playtest in the browser where possible:** prefer Godot web exports Yusuf can open from a link, with no install or build steps on their side. Fall back to a downloadable desktop build only when web can't do it.
- **Tune without rebuilding:** balance numbers live in data files, and in-game debug or tuning panels let Yusuf tweak values and re-run a round live.
- **Prototype before engine work** when it's cheaper: paper or spreadsheet mockups, or text summaries of headless simulation runs (e.g. "100 seeded runs: average waves survived, top relics"), to settle a design question before building it in-game.
- **Clear feedback hooks:** each playtest comes with 2-3 specific questions, plus a seed so Yusuf can say "seed 4821, round 6 felt unfair" and Claude can reproduce it.
- **Run history:** every run is saved as a versioned record (`RunState.to_record()`): the choices made, each wave, hero snapshots, deaths, relics and the result. Yusuf copies runs from the in-game Run history screen into chat, and simulated runs use the same format, so `tools/run_report.gd` can compare them. When mechanics change, extend the record and bump `RECORD_FORMAT` rather than dropping fields.
- Keep each iteration's report short: what changed, how to try it, what to look for.

## How to work with Yusuf

- **Default mode:** Claude proposes designs and builds. Yusuf approves big decisions and playtests.
- **Be token-efficient.** Keep replies short, lead with the decision or result, and skip narrating the investigation.
- **Decision policy (evolving):** to start, check in with Yusuf on design decisions. Then keep evaluating which *kinds* of decisions can be offloaded, and propose moving them into the "Claude decides" list below. Once Yusuf agrees, record them there and stop asking.
- When asking, give short multiple-choice options with a recommendation marked, grounded in the reference games where helpful.
- Pick sensible defaults for low-stakes implementation details and say which were chosen.
- **Don't punish optimising (Yusuf, 2026-10-12):** as a general theme, scaling and pressure systems may ease off for a struggling town but never get harder because the player is doing well.

### Claude decides without asking
- Code structure, naming, refactors, tooling and test setup within the technical direction above.
- Placeholder art, UI layout for prototypes, and debug tools.
- *(Add design categories here as Yusuf delegates them.)*

### Always ask Yusuf
- Changes to the pillars, core loop, or run and round structure.
- New major systems (e.g. turning on social or moral pressure, story).
- Final art style, tone, title, and anything publishing-related (store page, pricing, spending money).

## Open questions
- Final art style (pixel vs low-poly 3D).
- How Yusuf wants to playtest (browser builds from a link are the assumed default).
- Working title.
- Which buildings post which incentives.
- Hero energy and lodging rules: slice 3 uses Claude's defaults (energy drains awake and per attack, lodgings differ in rest speed, healing and how deeply heroes sleep, each trait has a favourite lodging, daily whims). Pending Yusuf's playtest.
- Bronze age, promotions and hero mood: slice 5 uses Claude's defaults (Bronze moot needs a market and 12 people and costs 14 wood, 8 stone, 30 shells; copper seams for townsfolk; smelter turns 2 cassiterite into tin and 2 copper + 1 tin into a bronze ingot; ingots go to the bronzesmith's gear or to one-off tool sets per townsfolk group; the caravan sells tin at 9 and cassiterite at 5 shells; bronze reavers from round 6 shrug off 40% of stone blows; a warrior with 6 kills can be promoted to a level 2 champion for 20 shells, a craftsperson with 8 goods at one workshop to a named master with a craft trait for 15; Promote cards take a dawn slot; mood is kept simple: sleeping rough once lodgings exist, hunger, cold and comrades dying lower it, a favourite bed, buying and prizes raise it, and a hero at 15 or below leaves). Pending Yusuf's playtest.
- Marketplace rules: slice 4 uses Claude's defaults (workshops hold 1 craftsperson and can be built twice, stalls hold 4 goods, Cheap/Fair/Dear prices per stall at x0.6/x1/x1.5, greedy heroes skip Dear stalls, crafted gear tiers up every 3 rounds, the hunting lodge pays 3 shells per beast, obsidian is fetched by heroes and sold for 2 shells a shard, between-round traders are gone). Pending Yusuf's playtest.
- Ring town, pathfinding and roads: slice 6 uses Claude's defaults (3 rings of plots in the stone age and a 4th from the bronze age, 8 sectors; 3 boulders and 2 old oaks on random plots; thickets past the town at 60% speed; trails form where feet pass most and give +20%; the stone-layers' yard costs 8 wood and 4 stone, and its craftspeople pave when nothing needs building or crafting, 1 stone per 5 squares for stone paths at +45%, 1 stone and 1 wood for bronze-age cobbles at +70%, always leaving 4 of each in stock; raiders get the road bonus too). Palisades (slice 7) use Claude's defaults: straight lines between waypoints, 1 wood per 3 squares and 2 craftsperson-seconds a square, raised by idle craftspeople before paving and only while 15 wood is left (wood also feeds the fire); a square of wall has 40 health and a gate 70, patched to full each dawn; raiders go round when that's shorter than half a square per point of health and batter through otherwise; your own people climb over at 15% speed or use gates (fully blocking them cost the bot about 20 points); fighters strike over it. The bot doesn't build palisades, because a full ring cost it 1 to 11 points in every setting tried. Pending Yusuf's playtest.
- Power level and catch-up (2026-10-12, Yusuf's idea after Path of Exile 2's monster power): `sim/power.gd` rates every fighter as sqrt(effective HP x damage per second), so the town (heroes, warriors, hearth and towers) and each wave sit on one scale. **Yusuf decided (2026-10-12): soft catch-up that only eases waves, never boosts them, because the game shouldn't punish optimising.** Claude's defaults: when the scheduled wave is over 1.5x the town's power as the round starts, raiders are held back from it until it isn't, keeping at least 60% of them (`catch_up_*` in data/balance.json). Bots: balanced 72% to 78%, heroes 58% to 72%, workers 27% to 52% (1.3x pushed balanced to 82%). Pending Yusuf's playtest.
- Difficulty tuning pass 1 (2026-10-11): Claude's target is the balanced bot winning 70-80% with the workers-only bot clearly weak. One new enemy type per round (wolves round 2, cave bears 4, bone-callers 5, bronze reavers 6), softer cave bears (65 hp), tougher reavers (48 hp), hunger costs less mood (-5), more dry brush, nights 14s. Pending Yusuf's playtest.
