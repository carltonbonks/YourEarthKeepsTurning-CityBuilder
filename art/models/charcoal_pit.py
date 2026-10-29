"""Charcoal pit (data/buildings.json "charcoal_pit"): a smouldering earth mound with embers showing
through, a stack of wood beside it."""


def build(kit):
    t = kit.town_mats()
    kit.ball(t["earth"], (0, 0.1, 0.0), 1.0, scale=(1.0, 1.0, 0.55), detail=2)
    ember = kit.glow("ember", (1.0, 0.4, 0.1), 4.0)
    for x, y in ((0.55, -0.5), (0.8, 0.1), (-0.2, -0.75)):
        kit.ball(ember, (x, y, 0.25), 0.08)
    kit.ball(kit.mat("smoke", (0.5, 0.5, 0.5), noise=0.2), (0.0, 0.1, 0.75), 0.18)
    kit.logs(t["wood"], (-0.9, -0.9), n=6, length=0.8, r=0.07, turn=0.6)
