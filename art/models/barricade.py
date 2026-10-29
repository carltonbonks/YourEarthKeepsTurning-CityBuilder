"""Barricade (data/town.json barricades): brush and sharpened stakes thrown across a gap once raiders
are spotted. 8 facings like a gate: facing 0 blocks the way along +x."""


def build(kit):
    t = kit.town_mats()
    brush = kit.mat("brush", (0.42, 0.36, 0.20), noise=0.6, scale=30.0)
    for k in range(7):
        y = -1.2 + k * 0.4
        kit.limb(t["wood"], (-0.25, y, 0), (0.35, y + 0.05, 0.75), 0.04)
        kit.limb(t["wood"], (0.25, y + 0.2, 0), (-0.3, y + 0.15, 0.65), 0.035)
    for k in range(5):
        kit.ball(brush, (0, -1.0 + k * 0.5, 0.2), 0.3, scale=(0.9, 1.3, 0.75), rot=(0, 0, k))
