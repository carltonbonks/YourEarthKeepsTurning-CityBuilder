"""Foragers' camp (data/buildings.json "foragers_camp"): an outpost tent with baskets of berries and
roots and herbs drying on a line."""


def build(kit):
    t = kit.town_mats()
    berry = kit.mat("berries", (0.45, 0.14, 0.32), noise=0.4)
    wicker = kit.mat("wicker", (0.62, 0.48, 0.26), noise=0.5, scale=40.0)
    kit.tent(t["hide"], t["dark_wood"], at=(-0.6, 0.5), r=0.7, h=1.3)
    for x, y in ((0.5, -0.4), (0.85, -0.05), (0.2, -0.75)):
        kit.cylinder(wicker, (x, y, 0.13), 0.16, 0.26, sides=8)
        kit.ball(berry, (x, y, 0.27), 0.12, scale=(1, 1, 0.5))
    for x in (0.4, 1.2):
        kit.post(t["wood"], x, 0.6, 1.1, 0.03)
    kit.limb(t["rope"], (0.4, 0.6, 1.05), (1.2, 0.6, 1.05), 0.01, sides=4)
    for k in range(4):
        kit.box(kit.mat("herbs", (0.40, 0.45, 0.22), noise=0.4), (0.5 + k * 0.2, 0.6, 0.9), (0.06, 0.06, 0.25))
