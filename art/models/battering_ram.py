"""Battering ram (data/enemies.json "battering_ram"): an iron-capped log hung under a hide roof on wheels."""


def build(kit):
    wood = kit.mat("wood", (0.36, 0.25, 0.15), noise=0.4)
    dark = kit.mat("dark_wood", (0.22, 0.15, 0.09), noise=0.4)
    hide = kit.mat("hide", (0.42, 0.32, 0.22), noise=0.45)
    iron = kit.mat("iron", (0.30, 0.30, 0.32), rough=0.4, noise=0.3)
    for x in (-0.55, 0.55):
        for s in (-1, 1):
            kit.cylinder(dark, (x, s * 0.42, 0.22), 0.22, 0.08, sides=10, rot=(1.5708, 0, 0))
    kit.box(wood, (0, 0, 0.42), (1.6, 0.8, 0.1))
    for x in (-0.6, 0.6):
        for s in (-1, 1):
            kit.box(wood, (x, s * 0.36, 0.85), (0.08, 0.08, 0.85))
    kit.cylinder(wood, (0.15, 0, 0.72), 0.13, 2.0, sides=8, rot=(0, 1.5708, 0))
    kit.cone(iron, (1.2, 0, 0.72), 0.16, 0.06, 0.3, sides=8, rot=(0, 1.5708, 0))
    kit.cone(hide, (0, 0, 1.32), 0.75, 0.1, 0.45, sides=4, rot=(0, 0, 0.785), scale=(1.6, 0.9, 1))
