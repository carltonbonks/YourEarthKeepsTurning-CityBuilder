"""Bone carver (data/buildings.json "bone_carver"): a hide-roofed hut with antlers over its door, a
heap of bones and a carving block."""


def build(kit):
    t = kit.town_mats()
    kit.round_hut(t["daub"], t["hide"], r=0.8, wall_h=0.8, roof_h=1.0, at=(-0.4, 0.3), door=t["dark_wood"], sides=8)
    for s in (-1, 1):
        kit.limb(t["bone"], (0.42, 0.3 + s * 0.1, 1.0), (0.45, 0.3 + s * 0.4, 1.35), 0.03)
        kit.limb(t["bone"], (0.45, 0.3 + s * 0.3, 1.2), (0.5, 0.3 + s * 0.35, 1.45), 0.02)
    kit.pile(t["bone"], (0.8, -0.6), n=8, size=0.08, spread=0.25, seed=7)
    kit.cylinder(t["dark_wood"], (0.0, -0.8, 0.2), 0.22, 0.4, sides=8)
    kit.box(t["bone"], (0.0, -0.8, 0.43), (0.25, 0.06, 0.06))
