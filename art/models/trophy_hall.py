"""Trophy hall (data/buildings.json "trophy_hall"): a dark timber hall with a great antlered skull
over the door and pelts and tusks hung along its front."""


def build(kit):
    t = kit.town_mats()
    fur = kit.mat("fur", (0.36, 0.28, 0.20), noise=0.5, scale=36.0)
    kit.hall(t["dark_wood"], t["thatch"], 2.6, 1.5, 0.95, 1.15, at=(0, 0.3), door=t["wood"], beams=t["wood"])
    kit.ball(t["bone"], (0, -0.5, 1.15), 0.16, scale=(0.8, 0.6, 1.0))
    for s in (-1, 1):
        kit.limb(t["bone"], (s * 0.1, -0.5, 1.25), (s * 0.55, -0.55, 1.6), 0.04)
        kit.limb(t["bone"], (s * 0.35, -0.52, 1.42), (s * 0.4, -0.55, 1.75), 0.03)
        kit.limb(t["bone"], (s * 0.45, -0.55, 1.5), (s * 0.75, -0.55, 1.75), 0.025)
    for x in (-0.95, 0.85):
        kit.box(fur, (x, -0.47, 0.6), (0.5, 0.04, 0.6))
