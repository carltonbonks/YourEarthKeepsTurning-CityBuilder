"""Garden patch (data/buildings.json "garden"): fenced rows of greens and roots."""


def build(kit):
    t = kit.town_mats()
    green = kit.mat("greens", (0.30, 0.48, 0.20), noise=0.5, scale=30.0)
    root = kit.mat("roots", (0.62, 0.40, 0.22), noise=0.4)
    kit.box(t["earth"], (0, 0, 0.04), (2.8, 2.4, 0.08))
    for i in range(5):
        y = -0.9 + i * 0.45
        kit.box(t["earth"], (0, y, 0.1), (2.5, 0.22, 0.1))
        for k in range(8):
            x = -1.1 + k * 0.31
            m = green if (i + k) % 3 else root
            kit.ball(m, (x, y, 0.2), 0.1 + 0.03 * ((i * k) % 3), scale=(1, 1, 0.8))
    kit.fence(t["wood"], [(-1.45, -1.25), (1.45, -1.25), (1.45, 1.25), (-1.45, 1.25)], h=0.5, gap=0.35, closed=True)
