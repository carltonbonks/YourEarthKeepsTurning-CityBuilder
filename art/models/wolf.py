"""Wolf (data/enemies.json "wolf"): a lean grey wolf, head low. Feet at the origin, facing +x."""


def build(kit):
    fur = kit.mat("fur", (0.44, 0.42, 0.38), noise=0.45, scale=36.0)
    dark = kit.mat("dark_fur", (0.22, 0.21, 0.20), noise=0.4)
    pale = kit.mat("pale_fur", (0.64, 0.61, 0.56), noise=0.3)
    eye = kit.mat("eye", (0.95, 0.75, 0.25), noise=0.0)
    me = kit.quadruped(fur, fur, belly=pale)
    kit.ball(dark, (0.0, 0, 0.78), 0.2, scale=(1.9, 0.55, 0.4))
    x, y, z = me["head"]
    kit.cone(dark, (x + 0.18, 0, z - 0.04), 0.08, 0.035, 0.24, sides=6, rot=(0, 1.62, 0))
    for s in (-1, 1):
        kit.cone(dark, (x - 0.04, s * 0.08, z + 0.15), 0.05, 0.0, 0.13, sides=4)
        kit.ball(eye, (x + 0.11, s * 0.065, z + 0.04), 0.02)
    rx, ry, rz = me["rump"]
    kit.limb(dark, (rx, 0, rz), (rx - 0.3, 0, rz - 0.28), 0.07)
