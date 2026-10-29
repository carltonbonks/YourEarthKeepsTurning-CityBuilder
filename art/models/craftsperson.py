"""Craftsperson (data/townsfolk.json "craftsperson"): a leather apron and a stone maul."""


def build(kit):
    skin = kit.mat("skin", (0.64, 0.45, 0.32), noise=0.15)
    cloth = kit.mat("cloth", (0.55, 0.50, 0.40), noise=0.35)
    apron = kit.mat("leather", (0.34, 0.22, 0.13), noise=0.3)
    hair = kit.mat("hair", (0.30, 0.20, 0.12), noise=0.3)
    wood = kit.mat("wood", (0.36, 0.25, 0.14), noise=0.3)
    stone = kit.mat("stone", (0.48, 0.46, 0.42), noise=0.35)
    me = kit.humanoid(skin, cloth, apron, hair=hair, boots=apron)
    kit.box(apron, (0.17, 0, 1.08), (0.06, 0.34, 0.6))
    x, y, z = me["hand_r"]
    kit.limb(wood, (x, y, z - 0.08), (x + 0.32, y, z + 0.08), 0.03, sides=5, on=me["arm_r"])
    kit.box(stone, (x + 0.36, y, z + 0.1), (0.14, 0.14, 0.2), on=me["arm_r"])
