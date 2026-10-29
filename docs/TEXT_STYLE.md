# Text style

How every word on screen is written and shown (Yusuf, 2026-10-28; plan https://claude.ai/artifact/UMEZjZHwumYo7eqvohW3Ak). Cards follow `game/card_view.gd` on top of this. `tests/test_text_style.gd` checks the parts a test can.

## Voices

Who is speaking decides the grammar.

- **Ledger** (top bar, chips, card footers, tables): a label, then a number. No verbs, no full stop. "Food 25", "Lv 3", "One only".
- **Guide** (the Elder, tips, the build hint, blockers, buttons): speaks to the player. Buttons are verbs ("Begin round 4"); a hint is a sentence with a full stop.
- **Chronicle** (the log, banners, the end screen, night summaries): the town's story, present tense, who first, full stop. "Aed fells the last raider."

## Words

- Sentence case everywhere: headings, buttons, chips, menu items, and names. Capitals go only on a name's first word and on proper names (people, places such as the Fen, the named such as the Black Margrave): "Bone dice", "Hearth-mother's doll".
- Mid-sentence, buildings, goods, roles and ages are lower case ("build a stone-layers' yard"); people, relics and places keep their capitals.
- Small tracked capitals are only for eyebrow labels: card bands, hand sections, settings groups.
- **Vocabulary:** home is the **town** ("camp" only for the pedlar's camp and war camps). Whatever attacks is **raiders** (sentient) or **beasts** (animals); **foes** covers both in rules text. Never settlement, village, enemies, attackers, invaders.

## Numbers

- Sentences: number then noun ("16 food"). Cards and the bar: icon then number.
- Change is signed: "+16", "−3" (a real minus).
- Of a total: "13 / 15". Copies and speeds: "×3", "2×". Levels: "Lv 3" in the ledger, "level 3" in sentences.
- Time and distance in the player's units: days, nights, rounds, and "near town", "a fair walk out", "far out". Never map units.

## Sizes

Six sizes as `UiKit` constants (cards keep their own, `CardView`), never a number in a screen's code:
`CAPTION` 11 (footers, hover detail, eyebrows), `BODY` 13 (log, alerts, the Elder, the top bar), `STRONG` 15 (summary lines, popups over the map), `TITLE` 18 (verdicts, subtitles), `HEADING` 24 (pop-up titles), and for moments only `BANNER` 32 (tier 3) and `BANNER_RUN` 44 (tier 4). The title screen's logo is the one exception.

## Colour

Each colour means one thing: `UiKit.INK`, `DIM`, `GOOD`, `DANGER`, `EMBER`, `GOLD`, `BONE` (and `NIGHT` for the clock). BBCode goes through `UiKit.tint`, never a hand-written `[color=#...]`. Text that doesn't carry a meaning is ink or dim.

| Colour | Means |
|---|---|
| Ink, dim | Plain information; every ledger number |
| Green | Good, gained |
| Red | Loss, danger, can't |
| Ember | A problem this round that the player can fix (alerts, the Elder) |
| Hi-viz yellow | Learn this once (first-time tips only) |
| Gold | A moment (tier 3 and 4 banners) |
| Bone | Advice, the main button |
| The four rarities | Card frames, pips, plaques, relic names in hover; nowhere else |

Numbers on the top bar are ink; only a state ("runs out tonight") takes a colour. Eyebrow labels are dim, not ember.

## Emphasis tiers

Every message gets one tier; the tier sets its size, colour, motion and whether time pauses. Higher tiers are rarer. Story lines pass theirs to `RunState.tell(line, tier)` (`AMBIENT`, `NOTICE` by default, `PROBLEM`, `MOMENT`, `RUN`) and the log styles them through `UiKit.story_line`; alerts carry a `tier` in `Alerts.active`.

0. **Ambient** (a hut is finished, deals are laid out): log only, dim.
1. **Notice** (goods carried in, a relic dealt, the earth turns): log in ink, a small popup on the map.
2. **Problem now** (food or fuel running out, no room, an attack that outmatches you): ember alert or the Elder, log line bold with the cost in red, one pulse when it appears. A suggestion that costs nothing this round is a plain note, never ember.
3. **Moment** (the last raider falls, a hero dies or levels, a new age, a relic taken, a building lost): a gold banner (red for a loss) naming who, about 2 s of slow time or a camera beat. Picks wait for it; Space skips.
4. **Run** (victory, the fire going out): full-width banner, the largest size, holds until a click.
