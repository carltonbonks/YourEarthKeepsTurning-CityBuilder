"""Seer's tent (data/buildings.json "seer_tent"): a tall painted tent with a violet glow at its
flap, smoke-blackened bones and a bowl of embers before it."""


def build(kit):
    t = kit.town_mats()
    paint = kit.mat("painted_hide", (0.42, 0.28, 0.48), noise=0.4)
    kit.tent(paint, t["dark_wood"], at=(-0.2, 0.2), r=1.0, h=2.0, sides=8)
    kit.box(kit.glow("seer", (0.8, 0.5, 1.0), 4.0), (0.6, -0.4, 0.35), (0.08, 0.3, 0.55), rot=(0, 0, -0.8))
    kit.cylinder(t["stone"], (0.9, -0.8, 0.08), 0.2, 0.16, sides=8)
    kit.ball(kit.glow("ember", (1.0, 0.45, 0.12), 4.0), (0.9, -0.8, 0.16), 0.12, scale=(1, 1, 0.4))
    kit.pile(t["bone"], (-0.9, -0.7), n=4, size=0.06, spread=0.15, seed=23)
