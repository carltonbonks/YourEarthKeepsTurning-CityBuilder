"""Hollow knight (data/enemies.json "hollow_knight"): blackened plate with nothing inside, a greatsword."""


def build(kit):
    plate = kit.mat("plate", (0.24, 0.25, 0.28), rough=0.35, noise=0.3)
    steel = kit.mat("steel", (0.55, 0.56, 0.60), rough=0.3, noise=0.15)
    void = kit.mat("void", (0.03, 0.03, 0.04), noise=0.0)
    eye = kit.mat("eye", (0.55, 0.75, 1.0), noise=0.0)
    me = kit.humanoid(plate, plate, plate, boots=plate, helm=plate, bulk=1.15, skirt=True)
    hx, hy, hz = me["head"]
    kit.cylinder(plate, (hx, 0, hz + 0.02), 0.16, 0.32, sides=8)
    kit.box(void, (hx + 0.15, 0, hz + 0.02), (0.02, 0.18, 0.04))
    kit.ball(eye, (hx + 0.16, 0, hz + 0.02), 0.02)
    x, y, z = me["hand_r"]
    kit.box(steel, (x + 0.08, y, z + 0.6), (0.07, 0.03, 1.15), rot=(0, 0.25, 0), on=me["arm_r"])
    kit.box(plate, (x, y, z), (0.05, 0.3, 0.05), on=me["arm_r"])
