"""Charm stall (data/buildings.json "charm_stall"): a counter under a pale violet awning, hung with
strings of carved charms that catch the light."""


def build(kit):
    t = kit.town_mats()
    awning = kit.mat("awning", (0.60, 0.50, 0.68), noise=0.35)
    x, y, z = kit.stall(awning, t["wood"], t["dark_wood"])
    for k in range(7):
        kit.ball(t["bone"], (x - 0.9 + k * 0.3, y, z + 0.05), 0.05)
    for k in range(5):
        px = -0.9 + k * 0.45
        kit.limb(t["rope"], (px, -0.75, 1.42), (px, -0.75, 1.05), 0.008, sides=4)
        kit.ball(kit.glow("charm", (0.85, 0.75, 1.0), 1.5), (px, -0.75, 1.02), 0.05)
