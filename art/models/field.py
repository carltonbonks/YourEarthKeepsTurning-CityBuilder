"""Field (data/buildings.json "field"): ploughed strips of ripening grain with a scarecrow and a
sheaf stook at the edge."""


def build(kit):
    t = kit.town_mats()
    grain = kit.mat("grain", (0.74, 0.62, 0.28), noise=0.5, scale=40.0)
    young = kit.mat("young_grain", (0.52, 0.58, 0.26), noise=0.5, scale=40.0)
    kit.box(t["earth"], (0, 0, 0.03), (3.0, 2.6, 0.06))
    for i in range(6):
        y = -1.05 + i * 0.42
        kit.box(grain if i % 3 else young, (0, y, 0.18), (2.8, 0.28, 0.26 + 0.06 * (i % 2)))
    kit.post(t["wood"], 1.2, -1.15, 1.3, 0.035)
    kit.limb(t["wood"], (1.2, -1.45, 1.05), (1.2, -0.85, 1.05), 0.03)
    kit.ball(t["straw"], (1.2, -1.15, 1.32), 0.12)
    kit.box(t["hide"], (1.2, -1.15, 0.9), (0.2, 0.35, 0.4))
    kit.cone(t["straw"], (-1.3, -1.25, 0.35), 0.22, 0.05, 0.7, sides=7)
