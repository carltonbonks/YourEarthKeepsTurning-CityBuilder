"""Man-at-arms (data/enemies.json "man_at_arms"): mail, a kettle hat and a halberd."""


def build(kit):
    skin = kit.mat("skin", (0.62, 0.44, 0.32), noise=0.15)
    mail = kit.mat("mail", (0.48, 0.49, 0.52), rough=0.45, noise=0.5, scale=60.0)
    steel = kit.mat("steel", (0.62, 0.63, 0.66), rough=0.3, noise=0.15)
    cloth = kit.mat("cloth", (0.36, 0.30, 0.22), noise=0.4)
    wood = kit.mat("wood", (0.34, 0.23, 0.13), noise=0.3)
    me = kit.humanoid(skin, mail, cloth, boots=cloth, helm=steel)
    hx, hy, hz = me["head"]
    kit.cylinder(steel, (hx, 0, hz + 0.1), 0.26, 0.03, sides=12)
    x, y, z = me["hand_r"]
    kit.limb(wood, (x - 0.1, y, z - 0.6), (x + 0.2, y, z + 1.2), 0.03, sides=5, on=me["arm_r"])
    kit.box(steel, (x + 0.26, y, z + 1.05), (0.2, 0.03, 0.22), on=me["arm_r"])
