"""Obsidian outcrop (data/world.json nodes "obsidian"): black glassy shards jutting from the ground."""


def build(kit):
    glass = kit.mat("obsidian", (0.10, 0.07, 0.14), rough=0.15, noise=0.2)
    for k, (x, y, h) in enumerate(((0, 0, 1.2), (0.4, -0.3, 0.8), (-0.4, 0.2, 0.9), (0.2, 0.45, 0.6), (-0.3, -0.45, 0.5))):
        kit.cone(glass, (x, y, h / 2), 0.22, 0.02, h, sides=5, rot=(0.15 * (k - 2), 0.1 * k, k))
