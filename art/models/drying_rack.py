"""Drying rack (data/buildings.json "drying_rack"): frames of poles hung with strips of meat, fish
and herbs over a smoky fire."""


def build(kit):
    t = kit.town_mats()
    meat = kit.mat("meat", (0.48, 0.16, 0.12), noise=0.4)
    herb = kit.mat("herbs", (0.40, 0.45, 0.22), noise=0.4)
    for y in (-0.7, 0.4):
        for x in (-1.1, 1.1):
            kit.post(t["wood"], x, y, 1.5, 0.05)
        for z in (1.05, 1.4):
            kit.limb(t["wood"], (-1.1, y, z), (1.1, y, z), 0.03)
            for k in range(9):
                x = -0.95 + k * 0.24
                kit.box(meat if (k + int(z * 10)) % 3 else herb, (x, y, z - 0.2), (0.07, 0.03, 0.35))
    kit.fire((0, -0.15), size=0.18, logs_m=t["dark_wood"])
