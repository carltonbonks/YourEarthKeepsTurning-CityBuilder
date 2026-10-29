"""Hunter (data/heroes.json class "hunter"): a hooded archer in green-brown with a bow and quiver."""


def build(kit):
    skin = kit.mat("skin", (0.66, 0.47, 0.34), noise=0.15)
    cloth = kit.mat("cloth", (0.33, 0.40, 0.24), noise=0.4)
    leather = kit.mat("leather", (0.38, 0.26, 0.15), noise=0.3)
    wood = kit.mat("wood", (0.46, 0.32, 0.18), noise=0.3)
    hair = kit.mat("hair", (0.50, 0.32, 0.16), noise=0.3)
    me = kit.humanoid(skin, cloth, leather, hair=hair, cloak=cloth, boots=leather)
    kit.box(leather, (-0.2, 0.05, 1.35), (0.1, 0.12, 0.5), rot=(0.3, 0, 0))
    x, y, z = me["hand_l"]
    # The bow: a few straight staves bent into an arc.
    for a, b in (((x + 0.08, y, z - 0.5), (x + 0.16, y, z - 0.15)), ((x + 0.16, y, z - 0.15), (x + 0.16, y, z + 0.25)), ((x + 0.16, y, z + 0.25), (x + 0.08, y, z + 0.6))):
        kit.limb(wood, a, b, 0.025, sides=5, on=me["arm_l"])
