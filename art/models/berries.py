"""Berry thicket (data/world.json nodes "berries"): low leafy bushes heavy with dark berries."""


def build(kit):
    leaf = kit.mat("thicket", (0.22, 0.34, 0.18), noise=0.5, scale=24.0)
    berry = kit.mat("berries", (0.45, 0.12, 0.34), noise=0.3)
    for k, (x, y, r) in enumerate(((0, 0, 0.5), (0.6, -0.35, 0.38), (-0.6, 0.3, 0.42), (0.2, 0.6, 0.35))):
        kit.ball(leaf, (x, y, r * 0.7), r, scale=(1.2, 1.0, 0.85), rot=(0, 0, k))
        for j in range(5):
            kit.ball(berry, (x + r * 0.7 * ((j * 37) % 7 / 7 - 0.4), y - r * 0.9, r * (0.45 + 0.12 * j)), 0.05)
