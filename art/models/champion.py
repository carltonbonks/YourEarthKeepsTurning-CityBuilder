"""Champion (data/heroes.json class "champion"): a big fighter in furs with a heavy axe."""


def build(kit):
    skin = kit.mat("skin", (0.60, 0.41, 0.29), noise=0.15)
    hide = kit.mat("hide", (0.42, 0.27, 0.16), noise=0.4)
    fur = kit.mat("fur", (0.55, 0.50, 0.44), noise=0.5, scale=40.0)
    bone = kit.mat("bone", (0.86, 0.80, 0.66), noise=0.2)
    wood = kit.mat("wood", (0.34, 0.23, 0.13), noise=0.3)
    stone = kit.mat("obsidian", (0.14, 0.13, 0.17), rough=0.35, noise=0.2)
    me = kit.humanoid(skin, hide, hide, cloak=fur, boots=fur, helm=bone, height=1.06, bulk=1.2)
    hx, hy, hz = me["head"]
    for s in (1, -1):
        kit.cone(bone, (hx, s * 0.14, hz + 0.12), 0.04, 0.0, 0.22, sides=5, rot=(-s * 0.7, 0, 0))
    x, y, z = me["hand_r"]
    kit.limb(wood, (x, y, z - 0.3), (x + 0.15, y, z + 0.75), 0.035, sides=5, on=me["arm_r"])
    kit.box(stone, (x + 0.26, y, z + 0.62), (0.26, 0.05, 0.3), on=me["arm_r"])
