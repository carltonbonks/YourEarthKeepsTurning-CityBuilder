"""Runners' hut (data/buildings.json "runners_hut"): a small hut with packs and water skins by the
door and a pole marking the way out."""


def build(kit):
    t = kit.town_mats()
    kit.round_hut(t["daub"], t["thatch"], r=0.8, wall_h=0.8, roof_h=1.0, at=(-0.35, 0.3), door=t["dark_wood"], sides=9)
    for k, (x, y) in enumerate(((0.6, -0.5), (0.85, -0.2), (0.4, -0.8))):
        kit.ball(t["hide"], (x, y, 0.17), 0.17, scale=(1, 0.8, 1.1))
    kit.limb(t["rope"], (0.6, -0.5, 0.3), (0.85, -0.2, 0.3), 0.02)
    kit.banner(t["dark_wood"], t["cloth"], (1.15, 0.4), h=1.7, width=0.22, drop=0.35)
