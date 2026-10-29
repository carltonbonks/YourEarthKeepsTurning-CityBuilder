"""Barrow plate props (data/plates.json near_kinds "barrow"): old graves where the fallen may rise.
One variant per frame: 0 grave mound, 1 leaning stone, 2 skull cairn, 3 dead tree."""


def build(kit, variant=0):
    t = kit.town_mats()
    grass = kit.mat("mound_grass", (0.30, 0.30, 0.24), noise=0.6, scale=24.0)
    if variant == 0:
        kit.ball(grass, (0, 0, 0.0), 0.55, scale=(1.4, 0.8, 0.5))
        kit.box(t["stone"], (0.6, 0, 0.25), (0.08, 0.25, 0.5))
    elif variant == 1:
        kit.box(t["dark_stone"], (0, 0, 0.45), (0.3, 0.16, 1.0), rot=(0.3, 0.15, 0.4))
    elif variant == 2:
        kit.pile(t["dark_stone"], (0, 0), n=5, size=0.12, spread=0.15, seed=79)
        kit.ball(t["bone"], (0.05, -0.05, 0.42), 0.09, scale=(1, 0.9, 1.1))
    else:
        kit.limb(t["dark_wood"], (0, 0, 0), (0.05, 0, 1.4), 0.07)
        kit.limb(t["dark_wood"], (0.03, 0, 0.9), (0.45, -0.1, 1.3), 0.04)
        kit.limb(t["dark_wood"], (0.04, 0, 1.1), (-0.35, 0.1, 1.5), 0.035)
