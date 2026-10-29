"""Raider (data/enemies.json "raider"): a ragged raider in dark hides and blood-red rags with a club."""


def build(kit):
    skin = kit.mat("skin", (0.58, 0.40, 0.30), noise=0.2)
    hide = kit.mat("hide", (0.24, 0.20, 0.17), noise=0.45)
    rag = kit.mat("rag", (0.50, 0.12, 0.10), noise=0.4)
    hair = kit.mat("hair", (0.10, 0.08, 0.06), noise=0.3)
    wood = kit.mat("wood", (0.30, 0.20, 0.11), noise=0.3)
    stone = kit.mat("flint", (0.32, 0.32, 0.35), noise=0.3)
    me = kit.humanoid(skin, hide, hide, hair=hair, cloak=rag, boots=hide)
    x, y, z = me["hand_r"]
    kit.limb(wood, (x, y, z - 0.08), (x + 0.12, y, z + 0.55), 0.04, sides=5, on=me["arm_r"])
    kit.box(stone, (x + 0.13, y, z + 0.55), (0.16, 0.1, 0.12), on=me["arm_r"])
