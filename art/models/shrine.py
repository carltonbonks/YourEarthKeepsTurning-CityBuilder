"""Spirit shrine (data/buildings.json "shrine"): a small round lodge beside a ring of standing stones
with a pale glow at its heart, where heroes heal."""
import math


def build(kit):
    t = kit.town_mats()
    pale = kit.mat("pale_stone", (0.50, 0.50, 0.50), noise=0.45)
    kit.round_hut(t["hide"], t["thatch"], r=0.75, wall_h=0.75, roof_h=1.0, at=(-0.6, 0.6), door=t["dark_wood"], sides=8)
    for i in range(7):
        a = i / 7 * 2 * math.pi
        x, y = 0.6 + 0.6 * math.cos(a), -0.45 + 0.5 * math.sin(a)
        kit.box(pale, (x, y, 0.35 + 0.1 * (i % 2)), (0.18, 0.14, 0.7 + 0.2 * (i % 2)), rot=(0.05, 0, a))
    kit.ball(kit.glow("spirit", (0.6, 0.75, 1.0), 4.0), (0.6, -0.45, 0.3), 0.16)
    kit.stones(pale, (0.6, -0.45), 0.22, n=8, size=0.07)
