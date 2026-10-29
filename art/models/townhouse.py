"""Townhouse (data/buildings.json "townhouse"): a two-storey timber-framed house on a stone footing,
its upper floor jutting out, under a steep roof with a chimney."""


def build(kit):
    t = kit.town_mats()
    plaster = kit.mat("plaster", (0.70, 0.62, 0.48), noise=0.35)
    shingle = kit.mat("shingle", (0.30, 0.24, 0.20), noise=0.5, scale=30.0)
    kit.box(t["stone"], (0, 0, 0.2), (2.3, 1.5, 0.4))
    kit.box(plaster, (0, 0, 0.85), (2.2, 1.4, 0.9))
    kit.box(plaster, (0, 0, 1.75), (2.4, 1.6, 0.9))
    kit.gable(shingle, (0, 0, 2.2), 2.4, 1.6, 1.2)
    for x in (-1.1, -0.4, 0.4, 1.1):
        kit.box(t["dark_wood"], (x, -0.71, 0.85), (0.08, 0.02, 0.9))
        kit.box(t["dark_wood"], (x * 1.08, -0.81, 1.75), (0.08, 0.02, 0.9))
    for z in (1.3, 2.2):
        kit.box(t["dark_wood"], (0, -0.72 - (z > 2) * 0.1, z), (2.3, 0.02, 0.08))
    kit.box(t["dark_wood"], (0.0, -0.72, 0.65), (0.45, 0.04, 0.8))
    kit.box(kit.glow("window", (1.0, 0.75, 0.4), 2.0), (0.7, -0.82, 1.75), (0.3, 0.02, 0.3))
    kit.box(t["stone"], (0.7, 0.4, 3.0), (0.3, 0.3, 1.0))
