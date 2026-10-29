"""Training yard (data/buildings.json "training_yard"): a fenced patch of trodden sand with straw
dummies on posts and a rack of practice weapons."""


def build(kit):
    t = kit.town_mats()
    sand = kit.mat("sand", (0.55, 0.47, 0.34), noise=0.4)
    kit.box(sand, (0, 0, 0.02), (2.8, 2.4, 0.04))
    kit.fence(t["wood"], [(-1.4, -1.2), (1.4, -1.2), (1.4, 1.2), (-1.4, 1.2)], h=0.8, gap=0.45, closed=True)
    for x, y in ((-0.5, -0.2), (0.5, 0.3)):
        kit.post(t["dark_wood"], x, y, 1.3, 0.04)
        kit.limb(t["dark_wood"], (x, y - 0.3, 1.1), (x, y + 0.3, 1.1), 0.03)
        kit.cylinder(t["straw"], (x, y, 0.95), 0.17, 0.55, sides=7)
        kit.ball(t["straw"], (x, y, 1.33), 0.12)
    kit.box(t["dark_wood"], (0.6, -0.8, 0.6), (0.9, 0.08, 0.06))
    for k in range(4):
        kit.limb(t["wood"], (0.25 + k * 0.23, -0.85, 0.0), (0.25 + k * 0.23, -0.78, 1.1), 0.025)
