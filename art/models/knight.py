"""Knight (data/heroes.json class "knight"): mail and a red tabard, a great helm, sword and kite shield."""


def build(kit):
    skin = kit.mat("skin", (0.64, 0.46, 0.34), noise=0.15)
    mail = kit.mat("mail", (0.52, 0.53, 0.56), rough=0.45, noise=0.5, scale=60.0)
    steel = kit.mat("steel", (0.70, 0.71, 0.74), rough=0.3, noise=0.15)
    tabard = kit.mat("tabard", (0.58, 0.14, 0.12), noise=0.3)
    leather = kit.mat("leather", (0.30, 0.20, 0.12), noise=0.3)
    me = kit.humanoid(skin, mail, mail, boots=leather, helm=steel, bulk=1.1)
    kit.box(tabard, (0.15, 0, 1.15), (0.05, 0.3, 0.75))
    hx, hy, hz = me["head"]
    kit.cylinder(steel, (hx, 0, hz + 0.02), 0.155, 0.3, sides=10)
    x, y, z = me["hand_r"]
    kit.box(steel, (x + 0.05, y, z + 0.45), (0.05, 0.03, 0.85), rot=(0, 0.25, 0), on=me["arm_r"])
    kit.box(leather, (x, y, z), (0.04, 0.22, 0.04), on=me["arm_r"])
    x, y, z = me["hand_l"]
    kit.cone(tabard, (x + 0.1, y + 0.07, z + 0.1), 0.24, 0.05, 0.7, sides=4, rot=(3.1416, 0, 0), scale=(0.3, 1, 1), on=me["arm_l"])
