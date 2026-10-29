"""Cassiterite vein (data/world.json nodes "cassiterite"): a dark rock split by a vein of heavy
black-brown crystal, tin ore."""


def build(kit):
    t = kit.town_mats()
    ore = kit.mat("cassiterite", (0.18, 0.14, 0.13), rough=0.3, noise=0.3)
    kit.ball(t["stone"], (0, 0.2, 0.3), 0.7, scale=(1.3, 0.9, 0.85))
    for k in range(6):
        kit.cone(ore, (0.1 * (k - 3), -0.35, 0.25 + 0.06 * (k % 3)), 0.07, 0.01, 0.3, sides=4, rot=(0.6, 0, k))
    kit.pile(ore, (0.7, -0.55), n=4, size=0.08, spread=0.2, seed=71)
