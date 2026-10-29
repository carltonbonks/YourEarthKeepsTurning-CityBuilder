"""Bronze reaver (data/enemies.json "bronze_reaver"): bronze helm and scale shirt, a sickle sword and a shield."""


def build(kit):
    skin = kit.mat("skin", (0.60, 0.42, 0.30), noise=0.2)
    bronze = kit.mat("bronze", (0.70, 0.48, 0.22), rough=0.35, noise=0.35)
    cloth = kit.mat("cloth", (0.35, 0.25, 0.18), noise=0.4)
    leather = kit.mat("leather", (0.28, 0.18, 0.10), noise=0.3)
    me = kit.humanoid(skin, bronze, cloth, boots=leather, helm=bronze, bulk=1.08)
    hx, hy, hz = me["head"]
    kit.box(bronze, (hx - 0.02, 0, hz + 0.2), (0.25, 0.03, 0.12))
    x, y, z = me["hand_r"]
    kit.box(bronze, (x + 0.05, y, z + 0.3), (0.05, 0.03, 0.5), rot=(0, 0.35, 0), on=me["arm_r"])
    kit.box(bronze, (x + 0.2, y, z + 0.55), (0.2, 0.03, 0.06), rot=(0, -0.5, 0), on=me["arm_r"])
    x, y, z = me["hand_l"]
    kit.cylinder(leather, (x + 0.08, y + 0.06, z + 0.15), 0.24, 0.05, sides=10, rot=(1.5708, 0, 0), on=me["arm_l"])
    kit.ball(bronze, (x + 0.08, y + 0.10, z + 0.15), 0.06, on=me["arm_l"])
