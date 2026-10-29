"""Stalker (data/heroes.json class "stalker"): a lean figure in a dark hood with two knives."""


def build(kit):
    skin = kit.mat("skin", (0.62, 0.44, 0.33), noise=0.15)
    cloth = kit.mat("cloth", (0.18, 0.17, 0.20), noise=0.4)
    leather = kit.mat("leather", (0.28, 0.20, 0.14), noise=0.3)
    blade = kit.mat("flint", (0.45, 0.45, 0.50), rough=0.4, noise=0.2)
    me = kit.humanoid(skin, cloth, leather, cloak=cloth, boots=leather, bulk=0.92)
    hx, hy, hz = me["head"]
    kit.cone(cloth, (hx - 0.03, 0, hz + 0.05), 0.19, 0.03, 0.42, sides=7, rot=(0, -0.25, 0))
    for hand, arm in (("hand_r", "arm_r"), ("hand_l", "arm_l")):
        x, y, z = me[hand]
        kit.box(blade, (x + 0.16, y, z + 0.02), (0.28, 0.03, 0.06), rot=(0, -0.3, 0), on=me[arm])
