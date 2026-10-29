"""Stone keep (data/buildings.json "stone_keep"): a squat square stone tower with battlements, a
timber hoarding and a lord's banner, the town's step into the medieval age."""


def build(kit):
    t = kit.town_mats()
    kit.box(t["stone"], (0, 0, 1.4), (1.9, 1.9, 2.8))
    kit.box(t["dark_stone"], (0, 0, 0.15), (2.1, 2.1, 0.3))
    for i in range(5):
        for side in range(4):
            off = -0.8 + i * 0.4
            x, y = ((off, -0.92), (0.92, off), (off, 0.92), (-0.92, off))[side]
            kit.box(t["stone"], (x, y, 3.0), (0.22, 0.22, 0.4))
    kit.box(t["dark_wood"], (0, -0.97, 0.55), (0.6, 0.06, 1.1))
    for z in (1.6, 2.2):
        for x in (-0.5, 0.5):
            kit.box(kit.mat("slit", (0.05, 0.04, 0.04), noise=0.0), (x, -0.96, z), (0.08, 0.02, 0.3))
            kit.box(kit.mat("slit", (0.05, 0.04, 0.04), noise=0.0), (0.96, x, z), (0.02, 0.08, 0.3))
    kit.banner(t["dark_wood"], t["cloth"], (0.4, 0.4), h=4.3, width=0.5, drop=0.7, turn=0.78)
