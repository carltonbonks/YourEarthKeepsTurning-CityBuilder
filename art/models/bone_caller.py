"""Bone-caller (data/enemies.json "bone_caller"): a robed shaman in a bone mask with a skull staff."""


def build(kit):
    skin = kit.mat("skin", (0.55, 0.40, 0.32), noise=0.2)
    robe = kit.mat("robe", (0.30, 0.18, 0.28), noise=0.45)
    bone = kit.mat("bone", (0.88, 0.83, 0.70), noise=0.2)
    wood = kit.mat("wood", (0.26, 0.18, 0.10), noise=0.3)
    glow = kit.mat("glow", (0.85, 0.40, 0.75), noise=0.0)
    me = kit.humanoid(skin, robe, robe, cloak=robe, boots=robe)
    kit.cone(robe, (0, 0, 0.45), 0.32, 0.24, 0.9, sides=9)
    hx, hy, hz = me["head"]
    kit.box(bone, (hx + 0.12, 0, hz), (0.05, 0.2, 0.26))
    x, y, z = me["hand_r"]
    kit.limb(wood, (x, y, z - 0.85), (x + 0.05, y, z + 0.75), 0.03, sides=5, on=me["arm_r"])
    kit.ball(bone, (x + 0.05, y, z + 0.82), 0.09, on=me["arm_r"])
    kit.ball(glow, (x + 0.12, y, z + 0.84), 0.025, on=me["arm_r"])
