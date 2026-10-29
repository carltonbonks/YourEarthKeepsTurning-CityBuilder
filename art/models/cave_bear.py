"""Cave bear (data/enemies.json "cave_bear"): a hulking brown bear with a pale muzzle."""


def build(kit):
    fur = kit.mat("fur", (0.36, 0.24, 0.16), noise=0.5, scale=30.0)
    dark = kit.mat("dark_fur", (0.20, 0.13, 0.09), noise=0.4)
    muzzle = kit.mat("muzzle", (0.58, 0.46, 0.34), noise=0.3)
    me = kit.quadruped(fur, dark, length=1.25, height=1.35, girth=1.6)
    kit.ball(fur, (0.25, 0, 1.0), 0.32, scale=(1.2, 1.1, 0.8))
    x, y, z = me["head"]
    kit.ball(fur, (x, 0, z), 0.24, scale=(1.1, 1.0, 0.95))
    kit.cone(muzzle, (x + 0.24, 0, z - 0.06), 0.12, 0.06, 0.22, sides=6, rot=(0, 1.62, 0))
    for s in (-1, 1):
        kit.ball(dark, (x - 0.05, s * 0.15, z + 0.2), 0.06)
