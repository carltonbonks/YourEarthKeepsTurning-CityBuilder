"""Levy hall (data/buildings.json "levy_hall"): a plain long hall with racks of spears along its
front and a war horn on a post, ready for the warned night."""


def build(kit):
    t = kit.town_mats()
    kit.hall(t["wood"], t["thatch"], 2.6, 1.3, 0.85, 1.0, at=(0, 0.5), door=t["dark_wood"], beams=t["dark_wood"])
    for k in range(9):
        x = -1.1 + k * 0.27
        kit.limb(t["wood"], (x, -0.3, 0.0), (x + 0.04, -0.12, 1.5), 0.02)
        kit.cone(t["iron"], (x + 0.045, -0.115, 1.57), 0.03, 0.0, 0.15, sides=4)
    kit.limb(t["dark_wood"], (-1.2, -0.25, 0.8), (1.2, -0.25, 0.8), 0.03)
    kit.post(t["dark_wood"], 1.25, -0.8, 1.3, 0.04)
    kit.cone(t["bone"], (1.25, -0.8, 1.35), 0.07, 0.02, 0.35, sides=6, rot=(0, 1.2, 0))
