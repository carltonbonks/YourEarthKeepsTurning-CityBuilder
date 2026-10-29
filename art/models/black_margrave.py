"""The Black Margrave (data/enemies.json "black_margrave", a boss): a tall lord in black plate and a blood-red cloak, with a great mace."""


def build(kit):
    skin = kit.mat("skin", (0.55, 0.40, 0.32), noise=0.15)
    plate = kit.mat("black_plate", (0.13, 0.13, 0.16), rough=0.3, noise=0.25)
    cape = kit.mat("cape", (0.45, 0.06, 0.07), noise=0.35)
    gold = kit.mat("gold", (0.80, 0.62, 0.25), rough=0.3, noise=0.2)
    me = kit.humanoid(skin, plate, plate, cloak=cape, boots=plate, helm=plate, height=1.2, bulk=1.3)
    kit.box(cape, (-0.2, 0, 1.0), (0.05, 0.5, 1.1), rot=(0, 0.12, 0))
    hx, hy, hz = me["head"]
    kit.cylinder(plate, (hx, 0, hz + 0.02), 0.17, 0.34, sides=8)
    for i in range(5):
        kit.cone(gold, (hx - 0.05, -0.1 + i * 0.05, hz + 0.24), 0.03, 0.0, 0.12, sides=4)
    x, y, z = me["hand_r"]
    kit.limb(plate, (x, y, z - 0.1), (x + 0.1, y, z + 0.65), 0.035, sides=6, on=me["arm_r"])
    kit.ball(plate, (x + 0.11, y, z + 0.72), 0.14, on=me["arm_r"])
