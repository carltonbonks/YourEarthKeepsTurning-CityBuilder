"""Greenwood plate props (data/plates.json near_kinds "greenwood"): the woods that hide raiders. One
variant per frame: 0 pine, 1 oak, 2 bush, 3 fallen log."""


def build(kit, variant=0):
    t = kit.town_mats()
    pine = kit.mat("pine", (0.16, 0.28, 0.17), noise=0.5, scale=24.0)
    oak = kit.mat("oak", (0.24, 0.34, 0.17), noise=0.5, scale=24.0)
    if variant == 0:
        kit.limb(t["dark_wood"], (0, 0, 0), (0, 0, 0.9), 0.07)
        for k in range(3):
            kit.cone(pine, (0, 0, 1.0 + 0.45 * k), 0.6 - 0.15 * k, 0.05, 0.9, sides=7)
    elif variant == 1:
        kit.limb(t["dark_wood"], (0, 0, 0), (0, 0, 1.1), 0.1)
        kit.ball(oak, (0, 0, 1.55), 0.7, scale=(1.1, 1.0, 0.85))
        kit.ball(oak, (0.35, -0.25, 1.3), 0.4)
    elif variant == 2:
        kit.ball(oak, (0, 0, 0.3), 0.4, scale=(1.3, 1.0, 0.8))
        kit.ball(pine, (0.35, -0.2, 0.2), 0.25)
    else:
        kit.limb(t["dark_wood"], (-0.7, 0, 0.12), (0.7, 0.2, 0.15), 0.13)
        kit.ball(kit.mat("moss", (0.30, 0.40, 0.20), noise=0.6), (0.2, 0.1, 0.25), 0.15, scale=(2, 1, 0.5))
