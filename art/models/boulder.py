"""Boulder (data/town.json obstacles "boulder"): a great grey stone left by the ice, filling a plot."""


def build(kit):
    t = kit.town_mats()
    lichen = kit.mat("lichen", (0.52, 0.55, 0.38), noise=0.6, scale=24.0)
    kit.ball(t["stone"], (0, 0, 0.6), 1.15, scale=(1.2, 1.0, 0.75), rot=(0.2, 0.1, 0.5), detail=1)
    kit.ball(t["dark_stone"], (0.9, -0.6, 0.25), 0.45, rot=(0.3, 0, 1.0))
    kit.ball(lichen, (-0.3, -0.2, 1.3), 0.35, scale=(1.4, 1.2, 0.25))
