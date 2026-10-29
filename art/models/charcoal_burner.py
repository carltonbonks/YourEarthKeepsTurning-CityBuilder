"""Charcoal burner (data/buildings.json "charcoal_burner"): a big turf-covered clamp smoking and
glowing at its vents, long stacks of cordwood and a burner's shelter."""


def build(kit):
    t = kit.town_mats()
    turf = kit.mat("turf", (0.24, 0.22, 0.14), noise=0.6)
    kit.ball(turf, (0.2, 0.2, 0.0), 1.05, scale=(1.0, 0.9, 0.7), detail=2)
    ember = kit.glow("ember", (1.0, 0.42, 0.1), 4.5)
    for x, y, z in ((0.85, -0.3, 0.3), (0.5, -0.5, 0.45), (0.2, 0.2, 0.74)):
        kit.ball(ember, (x, y, z), 0.08)
    smoke = kit.mat("smoke", (0.5, 0.5, 0.5), noise=0.2)
    for k in range(3):
        kit.ball(smoke, (0.2 - 0.06 * k, 0.2 + 0.05 * k, 0.95 + 0.3 * k), 0.13 + 0.05 * k)
    kit.logs(t["wood"], (-0.6, -1.0), n=7, length=1.2, r=0.07)
    kit.tent(t["hide"], t["dark_wood"], at=(-1.1, 0.9), r=0.45, h=1.0)
