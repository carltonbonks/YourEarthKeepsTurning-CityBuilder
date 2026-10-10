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
- **Pressure:** escalating enemy waves **and** environmental hardship and scarcity. Social and moral pressure (factions, morale, Frostpunk-style choices) is a *later* layer, added only once the town's internal mechanics are deep enough to support it.
- **Victory conditions:** a mix, such as surviving waves, reaching economic or production goals, or collecting or completing certain relics and items. Vary them per run or map.

## NPCs

- **Heroes:** individuals with traits, personalities, morals and itemisation (equipment, loot). They act on their own incentives: they go out to fight, explore and loot based on their goals, and they react to bounties, buildings and town state. They should feel like characters whose stories emerge.
- **Townspeople / colonists:** mostly generic and handled **in aggregate**. They're modified, transformed and upgraded as groups (Against the Storm's races are a reference for group needs), not micromanaged one by one.
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
- Tone also undecided. The candidates are **grim survival** (Frostpunk) or **mythic and stylish** (Hades), and they could be blended. Claude can propose, Yusuf decides.

## Technical direction

- **Engine:** Godot 4.x (GDScript unless there's a strong reason for C#).
- **Platform:** PC, targeting Steam.
- **Goal:** mostly a hobby and learning project, but build it to **SDLC practices compatible with a future Steam release**:
  - Git with meaningful commits, feature branches and PRs.
  - Automated tests for core simulation logic (e.g. GUT for Godot) and CI (GitHub Actions) that runs them, plus headless export builds.
  - Data-driven content (buildings, heroes, relics, items and enemies defined in resource/data files, not hardcoded) so balancing and modding stay easy.
  - Keep simulation logic separate from presentation, so the auto-resolve phase can run headless for tests and balance simulations.
  - Deterministic, seedable RNG, so runs are reproducible for debugging and balancing.
  - Versioned save formats, settings, and input remapping. Plan for the Steamworks integration points (achievements, cloud saves) without building them early.
- **Yusuf's background:** low familiarity with code. They understand SDLC concepts from years around software projects, but have written very little code and no end-to-end programs. Claude owns build, test, troubleshoot and deploy end to end. Explain technical choices in plain language, never ask Yusuf to debug or edit code, and give one-click or one-command ways to run things.

## Fast iteration (dev-cycle priority)

Yusuf must be able to try changes and give feedback quickly, without heavy builds. This keeps token cost down and keeps development interactive.
- **Small slices:** ship the smallest playable change that answers a design question, then get feedback before building more.
- **Playtest in the browser where possible:** prefer Godot web exports Yusuf can open from a link, with no install or build steps on their side. Fall back to a downloadable desktop build only when web can't do it.
- **Tune without rebuilding:** balance numbers live in data files, and in-game debug or tuning panels let Yusuf tweak values and re-run a round live.
- **Prototype before engine work** when it's cheaper: paper or spreadsheet mockups, or text summaries of headless simulation runs (e.g. "100 seeded runs: average waves survived, top relics"), to settle a design question before building it in-game.
- **Clear feedback hooks:** each playtest comes with 2-3 specific questions, plus a seed so Yusuf can say "seed 4821, round 6 felt unfair" and Claude can reproduce it.
- Keep each iteration's report short: what changed, how to try it, what to look for.

## How to work with Yusuf

- **Default mode:** Claude proposes designs and builds. Yusuf approves big decisions and playtests.
- **Be token-efficient.** Keep replies short, lead with the decision or result, and skip narrating the investigation.
- **Decision policy (evolving):** to start, check in with Yusuf on design decisions. Then keep evaluating which *kinds* of decisions can be offloaded, and propose moving them into the "Claude decides" list below. Once Yusuf agrees, record them there and stop asking.
- When asking, give short multiple-choice options with a recommendation marked, grounded in the reference games where helpful.
- Pick sensible defaults for low-stakes implementation details and say which were chosen.

### Claude decides without asking
- Code structure, naming, refactors, tooling and test setup within the technical direction above.
- Placeholder art, UI layout for prototypes, and debug tools.
- *(Add design categories here as Yusuf delegates them.)*

### Always ask Yusuf
- Changes to the pillars, core loop, or run and round structure.
- New major systems (e.g. turning on social or moral pressure, story).
- Final art style, tone, title, and anything publishing-related (store page, pricing, spending money).

## Open questions
- Final art style (pixel vs low-poly 3D) and tone (grim vs mythic).
- How Yusuf wants to playtest (browser builds from a link are the assumed default).
- Working title and setting.
- The exact form of the hero-incentive system (bounties, temples, taverns, etc.) and of hero autonomy outside the walls.
