"""Barrow mound (data/world.json dens "barrow"): a long grassy grave mound with a stone-lined
entrance glowing a cold blue, standing stones at its ends."""


def build(kit):
    t = kit.town_mats()
    grass = kit.mat("mound_grass", (0.30, 0.34, 0.22), noise=0.6, scale=24.0)
    kit.ball(grass, (-0.2, 0.3, 0.0), 1.2, scale=(1.5, 0.9, 0.7), detail=2)
    for s in (-1, 1):
        kit.box(t["dark_stone"], (0.55 + s * 0.0, -0.2 + s * 0.32, 0.4), (0.18, 0.14, 0.8))
    kit.box(t["dark_stone"], (0.55, -0.2, 0.86), (0.2, 0.85, 0.16))
    kit.box(kit.glow("barrow_light", (0.5, 0.65, 1.0), 3.0), (0.6, -0.2, 0.35), (0.04, 0.5, 0.65))
    for x, y in ((-1.9, 0.6), (1.4, 0.8)):
        kit.box(t["stone"], (x, y, 0.5), (0.22, 0.18, 1.0), rot=(0.08, 0.05, 0.4))
