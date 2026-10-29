"""Chapel (data/buildings.json "chapel"): a small whitewashed stone chapel with a bell gable and a
round window, a few grave markers beside it."""


def build(kit):
    t = kit.town_mats()
    white = kit.mat("whitewash", (0.80, 0.78, 0.74), noise=0.3)
    slate = kit.mat("slate", (0.26, 0.27, 0.30), noise=0.4, scale=30.0)
    kit.box(white, (-0.1, 0.2, 0.75), (2.4, 1.3, 1.5))
    kit.gable(slate, (-0.1, 0.2, 1.5), 2.4, 1.3, 1.0)
    kit.box(white, (1.2, 0.2, 2.0), (0.25, 0.7, 1.4))
    kit.box(kit.mat("bell_gap", (0.08, 0.07, 0.07), noise=0.0), (1.33, 0.2, 2.25), (0.02, 0.3, 0.4))
    kit.ball(t["bronze"], (1.2, 0.2, 2.2), 0.12)
    kit.box(t["dark_wood"], (-0.1, -0.46, 0.5), (0.5, 0.04, 1.0))
    kit.cylinder(kit.glow("window", (0.95, 0.8, 0.5), 2.0), (1.0, -0.46, 1.1), 0.14, 0.03, sides=10, rot=(1.5708, 0, 0))
    for x in (-0.9, -0.5):
        kit.box(t["stone"], (x, -0.95, 0.25), (0.08, 0.2, 0.5))
        kit.box(t["stone"], (x, -0.95, 0.38), (0.08, 0.38, 0.08))
