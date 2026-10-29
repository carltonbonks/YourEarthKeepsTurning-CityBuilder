# Art spec

How the game's map art is made, and what any art we buy or commission must match so it drops into the same slots. Direction and why: the plan at https://claude.ai/artifact/6zLzm2AyxnvEXaC7KFaFwd and "Art and tone" in CLAUDE.md.

## The pipeline

1. **A model per content id.** The id is the one in `data/*.json` (`hut`, `tribesperson`, `wolf`). Today each model is a Blender Python script in `art/models/<id>.py` with a `build(kit)` function that makes its parts with `art/lib/kit.py`. A bought or commissioned model will be a `.glb` file in `art/models/`. The renderer doesn't load those yet: the first one we buy adds that step.
2. **A manifest row** in `art/manifest.json`: kind, model, frame size, camera scale, facings, size on the map and licence. Its `_note` explains each key.
3. **Render:** `tools/render_art.sh [id...]` runs Blender headless and writes `art/sprites/<id>.png` (one row per facing, one column per animation frame) and `art/sprites/index.json`, then prints where it saved a contact sheet of everything. Each walker takes about 15 seconds. The first run installs Blender (about 400 MB, a few minutes).
4. **Draw:** `game/sprite_book.gd` loads the sprites, and `game/arena_view.gd` draws an id's sprite in the tilted view. An id with no art keeps its placeholder shape, so art can arrive one piece at a time.
5. **Check:** `tests/test_art.gd` fails if a row names an id that doesn't exist, has no licence, or isn't rendered, or if a sprite has no row.

Commit the model, the manifest row, the PNG, its `.import` file and `index.json` together.

## Camera and light (fixed for every piece)

- Orthographic, looking down 30 degrees and turned 45 degrees, so the ground squashes 2:1 like the tilted map. The camera never turns in play.
- A warm low key light from the screen's upper left and a cold rim light from behind, set in `tools/render_art.py`. Change them there, for all art at once.
- The raw render is the look (Yusuf, 2026-10-29). There is no palette or grit pass for now.

## Models

- **Scale:** 1 unit = 1 metre. A person stands about 1.8 m tall, a wolf about 0.9 m at the head.
- **Pivot and facing:** the origin sits at the feet (walkers) or the middle of the footprint on the ground (buildings), and the model faces +X.
- **Buildings** fill a plot about 30 world units wide and 26 deep. `world_per_unit` in the manifest says how many world units one model metre covers (the hut uses 9, so a 2.7 m hut fills its plot).
- **Low-poly and flat-shaded.** Detail comes from shape and material noise, not polygons: a few hundred faces for a person, a few thousand for a big building.
- **Materials** use named slots for what they show (`skin`, `hide`, `fur`, `wood`, `stone`, `metal`, `cloth`, `banner`), so later age tints and team colours can find them.

## Walkers

- **8 facings.** Facing 0 looks along +x on the sim's map, and each next one turns 45 degrees toward +y. The renderer turns the model for each facing.
- **Animations (slice 2):** `idle` (1 frame), `walk` (6) and `attack` (4), posed by `tools/render_art.py` from a simple joint rig: our script models hang their arms and legs on empties named `arm_l`, `arm_r`, `leg_l`, `leg_r` (humanoid) or `leg_fl`, `leg_fr`, `leg_bl`, `leg_br` (quadruped); `rig: none` only bobs and lunges. `work` (gather or carry) and `fall` come later. Bought rigged characters should use one humanoid rig with Mixamo-style bone names, so they and their animations share a skeleton; the renderer will play their clips into the same columns. Beasts get their own rig per kind.
- **How they move on the map:** `game/walker_motion.gd` glides each sprite between the sim's steps, turns it the way it walks, steps the walk with the ground covered, plays a blow when it strikes (facing its target) and flashes it when hit.
- **Size on the map:** `height_r` in the manifest says how tall the figure stands, in multiples of the placeholder circle's radius (townsfolk 2.9, wolves 2.2; heroes about 2.25 to 2.4 of their larger circle, so a hero stands a little taller than a townsperson, Yusuf 2026-10-29).

## Buildings and the land (slice 3)

- **Every building** has a model, built from the shared parts in `art/lib/kit.py` (`town_mats` for the town's everyday materials so buildings share a look, `hall`, `round_hut`, `stall`, `tent`, `fence`, `logs`, `pile`, `fire`, `glow` for embers and lamps). Buildings face the camera's side with their doors (+x or -y).
- **One facing**, except things turned across the way people walk through: gates and barricades have 8, facing 0 letting people through along +x, and the game turns them to point out from the hearth.
- **States:** a building being built (or an outpost raiders wrecked) is a faint ghost of its sprite that firms up as the work goes on; a broken tower or barricade is darkened; a battered gate fades. Damaged and upgraded looks come later.
- **Tall pieces** (towers, the keep, two-storey houses, the old oak) use a taller frame such as 256 by 384; the camera's scale always spans the frame's width, so a tall frame shows more sky, not a smaller building.
- **The land:** resource nodes (shrink as they are worked, fade when worked out), dens, the hearth (burning, and cold on a cold night), the pedlar's camp and the plots' obstacles all have sprites. The turning ring's plates are dressed with props (`plate_<kind>`: reeds and pools, trees, stones, graves) that `game/ground_props.gd` scatters over each plate and turns with it.
- **Looks in one sheet:** a row with `variants: n` renders its model's `build(kit, variant)` n times into the columns of one sheet (the plates' props, the hearth's burning and cold looks).
- **Kinds** (the manifest's `kind`, checked against data by `tests/test_art.gd`): building, townsfolk, hero, enemy, node, den, obstacle, plate (`plate_` + a kind in data/plates.json) and scenery (barricade, pedlar_camp, hearth).

## Bought or commissioned art

- **3D models (preferred):** deliver `.glb` files to the scale, pivot, facing, rig and material-slot rules above. They go through the same renderer, so they match the camera and light of everything else.
- **Finished 2D sprites:** allowed for a special piece. Deliver one PNG per id with the frame size and facings of its manifest row, feet at the row's anchor point, on a transparent background.
- **Licence:** every manifest row says where its art comes from and under what terms (CC0, own work, bought from whom). A credits screen will be built from these lines.
- **AI-made art** is allowed while prototyping (Yusuf, 2026-10-29). Mark it in the licence line, because Steam asks for a disclosure and it all gets an artist pass before launch.
