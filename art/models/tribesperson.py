"""Tribesperson (data/townsfolk.json "tribesperson"): a gatherer in a hide tunic with a fur cloak
and a digging stick. Feet at the origin, facing +x."""


def build(kit):
    skin = kit.mat("skin", (0.66, 0.46, 0.33), noise=0.15)
    hide = kit.mat("hide", (0.56, 0.40, 0.25), noise=0.35)
    fur = kit.mat("fur", (0.36, 0.28, 0.20), noise=0.55, scale=40.0)
    hair = kit.mat("hair", (0.14, 0.10, 0.07), noise=0.3)
    wood = kit.mat("wood", (0.36, 0.25, 0.14), noise=0.3)
    me = kit.humanoid(skin, hide, skin, hair=hair, cloak=fur, boots=hide)
    x, y, z = me["hand_r"]
    kit.limb(wood, (x + 0.1, y, z - 0.75), (x - 0.04, y, z + 0.6), 0.035, sides=5, on=me["arm_r"])
