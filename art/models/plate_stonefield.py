"""Stonefield plate props (data/plates.json near_kinds "stonefield"): open hard ground. One variant
per frame: 0 boulder, 1 flat stones, 2 rock pile, 3 tilted slab."""


def build(kit, variant=0):
    t = kit.town_mats()
    if variant == 0:
        kit.ball(t["stone"], (0, 0, 0.25), 0.45, scale=(1.2, 1.0, 0.8), rot=(0.2, 0.1, 0.5))
    elif variant == 1:
        for k, (x, y) in enumerate(((0, 0), (0.45, -0.2), (-0.4, 0.25))):
            kit.box(t["stone"], (x, y, 0.04), (0.5, 0.35, 0.08), rot=(0, 0, 0.4 * k))
    elif variant == 2:
        kit.pile(t["dark_stone"], (0, 0), n=7, size=0.15, spread=0.3, seed=73)
    else:
        kit.box(t["dark_stone"], (0, 0, 0.3), (0.6, 0.18, 0.7), rot=(0.35, 0, 0.6))
