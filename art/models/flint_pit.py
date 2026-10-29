"""Flint pit (data/world.json nodes "flint_pit"): a shallow chalky dig with nodules of dark flint."""


def build(kit):
    chalk = kit.mat("chalk", (0.68, 0.66, 0.60), noise=0.4)
    flint = kit.mat("flint", (0.25, 0.27, 0.32), rough=0.5, noise=0.3)
    kit.cylinder(chalk, (0, 0, 0.03), 0.85, 0.06, sides=10)
    kit.cylinder(kit.mat("pit_floor", (0.45, 0.43, 0.40), noise=0.4), (0, 0, 0.05), 0.6, 0.04, sides=10)
    kit.pile(chalk, (0.75, -0.5), n=5, size=0.14, spread=0.25, seed=53)
    kit.pile(flint, (0, 0), n=7, size=0.11, spread=0.35, seed=59)
