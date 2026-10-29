"""Lookout cairn (data/buildings.json "lookout_cairn"): a tall heap of piled stone with a flat top
and a pole flying a strip of cloth."""


def build(kit):
    t = kit.town_mats()
    for k, (r, z) in enumerate(((0.75, 0.25), (0.6, 0.65), (0.45, 1.0), (0.3, 1.3))):
        kit.stones(t["stone"] if k % 2 else t["dark_stone"], (0, 0), r, n=9 - k, size=0.2 - 0.02 * k, z=z)
        kit.cylinder(t["dark_stone"], (0, 0, z - 0.05), r * 0.8, 0.4, sides=8)
    kit.banner(t["dark_wood"], t["cloth"], (0, 0), h=2.4, width=0.3, drop=0.35)
