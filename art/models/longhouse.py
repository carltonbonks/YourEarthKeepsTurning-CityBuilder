"""Longhouse (data/buildings.json "longhouse"): a long timber-and-daub hall under a deep thatch roof,
where heroes lodge."""


def build(kit):
    t = kit.town_mats()
    kit.hall(t["daub"], t["thatch"], 3.0, 1.6, 0.85, 1.25, door=t["dark_wood"], beams=t["dark_wood"])
    # Crossed gable ends and a smoke hole's wisp of thatch.
    for sx in (-1, 1):
        kit.limb(t["dark_wood"], (sx * 1.55, -0.15, 1.95), (sx * 1.55, 0.25, 2.35), 0.04)
        kit.limb(t["dark_wood"], (sx * 1.55, 0.15, 1.95), (sx * 1.55, -0.25, 2.35), 0.04)
    kit.banner(t["dark_wood"], t["cloth"], (0.6, -1.15), h=1.6, width=0.3, drop=0.45)
    kit.logs(t["wood"], (-1.0, -1.15), n=3, length=0.8, r=0.07)
