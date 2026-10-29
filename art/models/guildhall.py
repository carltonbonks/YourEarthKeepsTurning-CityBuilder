"""Guildhall (data/buildings.json "guildhall"): a long two-storey timber hall on a stone ground
floor, banners at the door, where knights and their peers lodge."""


def build(kit):
    t = kit.town_mats()
    plaster = kit.mat("plaster", (0.70, 0.62, 0.48), noise=0.35)
    shingle = kit.mat("shingle", (0.30, 0.24, 0.20), noise=0.5, scale=30.0)
    banner = kit.mat("guild_cloth", (0.45, 0.18, 0.32), noise=0.3)
    kit.box(t["stone"], (0, 0.15, 0.55), (3.0, 1.6, 1.1))
    kit.box(plaster, (0, 0.15, 1.55), (3.1, 1.75, 0.9))
    kit.gable(shingle, (0, 0.15, 2.0), 3.1, 1.75, 1.2)
    for x in (-1.5, -0.75, 0.0, 0.75, 1.5):
        kit.box(t["dark_wood"], (x, -0.73, 1.55), (0.08, 0.02, 0.9))
    kit.box(t["dark_wood"], (0, -0.66, 0.5), (0.6, 0.05, 1.0))
    for x in (-0.55, 0.55):
        kit.box(banner, (x, -0.68, 1.45), (0.3, 0.02, 0.8))
        kit.box(t["bronze"], (x, -0.69, 1.6), (0.12, 0.02, 0.12))
    for x in (-1.1, 1.1):
        kit.box(kit.glow("window", (1.0, 0.75, 0.4), 2.0), (x, -0.66, 0.6), (0.25, 0.02, 0.3))
