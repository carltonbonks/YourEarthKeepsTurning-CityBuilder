"""Armour stall (data/buildings.json "hide_stall"): a counter under a brown awning, folded hides on
it and a hide coat hung on a frame."""


def build(kit):
    t = kit.town_mats()
    awning = kit.mat("awning", (0.45, 0.30, 0.18), noise=0.35)
    fur = kit.mat("fur", (0.38, 0.30, 0.22), noise=0.5, scale=36.0)
    x, y, z = kit.stall(awning, t["wood"], t["dark_wood"])
    for k in range(3):
        kit.box(t["hide"] if k % 2 else fur, (x - 0.6 + k * 0.6, y, z + 0.06), (0.45, 0.3, 0.12))
    kit.post(t["dark_wood"], 1.3, -0.5, 1.4, 0.04)
    kit.limb(t["dark_wood"], (1.3, -0.8, 1.3), (1.3, -0.2, 1.3), 0.03)
    kit.cone(fur, (1.3, -0.5, 0.95), 0.3, 0.18, 0.7, sides=6)
