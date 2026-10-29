"""Arms stall (data/buildings.json "arms_stall"): a counter under an ochre awning laid with blades,
with spears leaning in a rack."""


def build(kit):
    t = kit.town_mats()
    awning = kit.mat("awning", (0.70, 0.42, 0.18), noise=0.35)
    flint = kit.mat("flint", (0.35, 0.37, 0.42), rough=0.5, noise=0.3)
    x, y, z = kit.stall(awning, t["wood"], t["dark_wood"])
    for k in range(5):
        kit.box(flint, (x - 0.8 + k * 0.4, y, z + 0.02), (0.28, 0.07, 0.03), rot=(0, 0, 0.3))
    for k in range(4):
        kit.limb(t["wood"], (1.3, -0.6 + k * 0.2, 0), (1.15, -0.6 + k * 0.2, 1.7), 0.025)
        kit.cone(flint, (1.15, -0.6 + k * 0.2, 1.78), 0.04, 0.0, 0.18, sides=4)
