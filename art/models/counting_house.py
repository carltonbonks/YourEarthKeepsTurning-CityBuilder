"""Counting house (data/buildings.json "counting_house"): a narrow stone-footed house with a barred
window, a strongbox on a cart at the door and gold coins spilled on the step."""


def build(kit):
    t = kit.town_mats()
    plaster = kit.mat("plaster", (0.70, 0.62, 0.48), noise=0.35)
    shingle = kit.mat("shingle", (0.30, 0.24, 0.20), noise=0.5, scale=30.0)
    gold = kit.mat("gold", (0.90, 0.70, 0.25), rough=0.3, noise=0.1)
    kit.box(t["stone"], (-0.2, 0.3, 0.6), (1.8, 1.3, 1.2))
    kit.box(plaster, (-0.2, 0.3, 1.55), (1.9, 1.4, 0.7))
    kit.gable(shingle, (-0.2, 0.3, 1.9), 1.9, 1.4, 1.0)
    kit.box(t["dark_wood"], (-0.5, -0.36, 0.5), (0.45, 0.04, 1.0))
    kit.box(kit.glow("window", (1.0, 0.75, 0.4), 2.0), (0.35, -0.36, 0.8), (0.35, 0.02, 0.3))
    for k in range(3):
        kit.box(t["iron"], (0.25 + k * 0.1, -0.38, 0.8), (0.02, 0.02, 0.32))
    kit.box(t["dark_wood"], (0.9, -0.7, 0.3), (0.5, 0.35, 0.3))
    kit.box(t["iron"], (0.9, -0.7, 0.3), (0.52, 0.04, 0.32))
    kit.pile(gold, (0.4, -0.75), n=5, size=0.04, spread=0.15, seed=31)
