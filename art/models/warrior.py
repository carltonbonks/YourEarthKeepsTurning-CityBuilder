"""Warrior (data/townsfolk.json "warrior"): a spear and a round hide shield, a bone-studded cap."""


def build(kit):
    skin = kit.mat("skin", (0.62, 0.43, 0.31), noise=0.15)
    hide = kit.mat("hide", (0.45, 0.30, 0.18), noise=0.35)
    fur = kit.mat("fur", (0.30, 0.24, 0.18), noise=0.55, scale=40.0)
    bone = kit.mat("bone", (0.86, 0.80, 0.66), noise=0.2)
    wood = kit.mat("wood", (0.36, 0.25, 0.14), noise=0.3)
    stone = kit.mat("flint", (0.30, 0.30, 0.33), rough=0.5, noise=0.3)
    shield = kit.mat("shield", (0.58, 0.42, 0.26), noise=0.4)
    me = kit.humanoid(skin, hide, hide, cloak=fur, boots=fur, helm=bone, bulk=1.08)
    x, y, z = me["hand_r"]
    kit.limb(wood, (x - 0.15, y, z - 0.45), (x + 0.35, y, z + 1.05), 0.03, sides=5, on=me["arm_r"])
    kit.cone(stone, (x + 0.40, y, z + 1.17), 0.05, 0.0, 0.2, sides=4, rot=(0, 0.32, 0), on=me["arm_r"])
    x, y, z = me["hand_l"]
    kit.cylinder(shield, (x + 0.08, y + 0.06, z + 0.15), 0.26, 0.05, sides=10, rot=(1.5708, 0, 0), on=me["arm_l"])
    kit.ball(bone, (x + 0.08, y + 0.10, z + 0.15), 0.05, on=me["arm_l"])
