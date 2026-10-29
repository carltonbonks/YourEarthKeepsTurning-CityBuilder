"""Reeve's hut (data/buildings.json "reeves_hut"): a round hut with a carved tally post at its door,
notched sticks bundled against the wall."""


def build(kit):
    t = kit.town_mats()
    kit.round_hut(t["daub"], t["thatch"], r=0.9, wall_h=0.85, roof_h=1.2, at=(-0.2, 0.2), door=t["dark_wood"], sides=10)
    kit.post(t["dark_wood"], 1.0, -0.7, 1.4, 0.09)
    for k in range(6):
        kit.box(t["bone"], (1.06, -0.7, 0.4 + k * 0.15), (0.04, 0.14, 0.03))
    for k in range(5):
        kit.limb(t["wood"], (0.4 + k * 0.08, -0.85, 0.0), (0.35 + k * 0.08, -0.65, 0.6), 0.02, sides=4)
