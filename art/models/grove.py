"""Grove (data/world.json nodes "grove"): a stand of dark pines and a broad oak, wood for the town."""


def build(kit):
    t = kit.town_mats()
    pine = kit.mat("pine", (0.18, 0.30, 0.18), noise=0.5, scale=24.0)
    oak = kit.mat("oak", (0.26, 0.36, 0.18), noise=0.5, scale=24.0)
    for x, y, h in ((-0.6, 0.4, 2.4), (0.5, 0.7, 2.0), (0.7, -0.4, 1.7)):
        kit.limb(t["dark_wood"], (x, y, 0), (x, y, h * 0.4), 0.08)
        for k in range(3):
            kit.cone(pine, (x, y, h * (0.45 + 0.2 * k)), 0.55 - 0.13 * k, 0.05, h * 0.38, sides=7)
    kit.limb(t["dark_wood"], (-0.3, -0.6, 0), (-0.3, -0.6, 1.0), 0.12)
    kit.ball(oak, (-0.3, -0.6, 1.4), 0.65, scale=(1.1, 1.0, 0.85))
