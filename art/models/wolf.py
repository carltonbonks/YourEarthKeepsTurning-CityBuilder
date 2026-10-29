"""Wolf (data/enemies.json "wolf"): a lean grey wolf, head low. Feet at the origin, facing +x."""


def build(kit):
    fur = kit.mat("fur", (0.40, 0.38, 0.35), noise=0.45, scale=36.0)
    dark = kit.mat("dark_fur", (0.20, 0.19, 0.18), noise=0.4)
    pale = kit.mat("pale_fur", (0.62, 0.59, 0.54), noise=0.3)
    eye = kit.mat("eye", (0.95, 0.75, 0.25), noise=0.0)
    # Body: chest deeper than the hips.
    kit.ball(fur, (0.05, 0, 0.62), 0.32, scale=(1.55, 0.72, 0.78))
    kit.ball(dark, (0.0, 0, 0.78), 0.2, scale=(1.9, 0.55, 0.4))
    kit.ball(pale, (0.30, 0, 0.52), 0.2, scale=(1.0, 0.8, 0.9))
    # Legs.
    for x in (0.34, -0.30):
        for s in (-1, 1):
            kit.limb(fur, (x, s * 0.12, 0.55), (x + 0.03, s * 0.12, 0.02), 0.055)
    # Neck and head, held low and forward, with ears and a snout.
    kit.limb(fur, (0.42, 0, 0.70), (0.66, 0, 0.66), 0.13)
    kit.ball(fur, (0.74, 0, 0.66), 0.15, scale=(1.2, 0.9, 0.9))
    kit.cone(dark, (0.92, 0, 0.62), 0.08, 0.035, 0.24, sides=6, rot=(0, 1.62, 0))
    for s in (-1, 1):
        kit.cone(dark, (0.70, s * 0.08, 0.81), 0.05, 0.0, 0.13, sides=4)
        kit.ball(eye, (0.85, s * 0.065, 0.70), 0.02)
    # Tail, hanging.
    kit.limb(dark, (-0.45, 0, 0.70), (-0.75, 0, 0.42), 0.07)
