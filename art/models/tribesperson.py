"""Tribesperson (data/townsfolk.json "tribesperson"): a gatherer in a hide tunic with a fur cloak
and a digging stick. Feet at the origin, facing +x."""


def build(kit):
    skin = kit.mat("skin", (0.66, 0.46, 0.33), noise=0.15)
    hide = kit.mat("hide", (0.56, 0.40, 0.25), noise=0.35)
    fur = kit.mat("fur", (0.36, 0.28, 0.20), noise=0.55, scale=40.0)
    hair = kit.mat("hair", (0.14, 0.10, 0.07), noise=0.3)
    wood = kit.mat("wood", (0.30, 0.21, 0.12), noise=0.3)
    # Legs, a little apart.
    for s in (-1, 1):
        kit.limb(skin, (0, s * 0.11, 0.05), (0.02, s * 0.10, 0.80), 0.075)
        kit.box(hide, (0.05, s * 0.11, 0.04), (0.24, 0.12, 0.08))
    # Tunic and fur cloak over the shoulders.
    kit.cone(hide, (0, 0, 0.95), 0.27, 0.20, 0.55, sides=8)
    kit.cylinder(hide, (0, 0, 1.33), 0.20, 0.32, sides=8)
    kit.cone(fur, (-0.03, 0, 1.40), 0.30, 0.14, 0.22, sides=8)
    # Arms: one hangs, one holds the stick forward.
    kit.limb(skin, (0, 0.24, 1.42), (0.04, 0.29, 0.98), 0.06)
    kit.limb(skin, (0, -0.24, 1.42), (0.22, -0.26, 1.08), 0.06)
    kit.limb(wood, (0.30, -0.27, 0.10), (0.18, -0.25, 1.62), 0.03, sides=5)
    # Head and hair.
    kit.ball(skin, (0.0, 0, 1.66), 0.14, scale=(1.0, 0.95, 1.1))
    kit.ball(hair, (-0.04, 0, 1.72), 0.145, scale=(1.0, 1.0, 0.9))
