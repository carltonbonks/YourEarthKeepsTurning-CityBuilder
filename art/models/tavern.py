"""Mead hall (data/buildings.json "tavern"): a broad hall with a carved door, barrels by the wall and
a glow at the door, where heroes drink and pay."""


def build(kit):
    t = kit.town_mats()
    kit.hall(t["wood"], t["thatch"], 2.8, 1.9, 1.0, 1.3, door=t["dark_wood"], beams=t["dark_wood"])
    for sx in (-1, 1):
        kit.cone(t["dark_wood"], (sx * 1.5, 0, 2.45), 0.08, 0.0, 0.4, sides=4)
    kit.box(kit.glow("lamp", (1.0, 0.65, 0.3), 3.0), (0.0, -0.99, 0.42), (0.34, 0.02, 0.62))
    for i, x in enumerate((0.75, 1.1)):
        kit.barrel(t["wood"], (x, -1.25), band=t["iron"])
    kit.barrel(t["wood"], (0.92, -1.22), r=0.15, h=0.36, band=t["iron"])
    kit.box(t["dark_wood"], (-0.8, -1.25, 0.25), (0.8, 0.25, 0.08))
    for x in (-1.1, -0.5):
        kit.post(t["dark_wood"], x, -1.25, 0.24, 0.04)
