"""Bronzesmith (data/buildings.json "bronzesmith"): a timber workshop with a glowing hearth under
its eaves, a stone anvil and bronze blades on a rack."""


def build(kit):
    t = kit.town_mats()
    kit.hall(t["daub"], t["thatch"], 2.0, 1.3, 0.85, 0.9, at=(-0.4, 0.5), door=t["dark_wood"], beams=t["dark_wood"])
    kit.box(t["stone"], (0.65, -0.3, 0.25), (0.6, 0.5, 0.5))
    kit.box(kit.glow("forge", (1.0, 0.55, 0.2), 6.0), (0.65, -0.3, 0.51), (0.4, 0.3, 0.04))
    kit.box(t["dark_stone"], (-0.2, -0.65, 0.2), (0.35, 0.25, 0.4))
    kit.box(t["bronze"], (-0.2, -0.65, 0.42), (0.3, 0.06, 0.04))
    for k in range(3):
        kit.limb(t["bronze"], (1.25, -0.9 + k * 0.25, 0.1), (1.15, -0.9 + k * 0.25, 1.0), 0.03)
