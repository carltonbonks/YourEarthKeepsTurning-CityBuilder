"""Beacon tower (data/buildings.json "beacon_tower"): a tall stone-footed timber tower with a great
iron basket of fire at its top that draws the attack."""


def build(kit):
    t = kit.town_mats()
    kit.box(t["stone"], (0, 0, 0.4), (1.2, 1.2, 0.8))
    for sx in (-1, 1):
        for sy in (-1, 1):
            kit.limb(t["dark_wood"], (sx * 0.5, sy * 0.5, 0.8), (sx * 0.3, sy * 0.3, 3.4), 0.07)
    for z in (1.6, 2.5):
        f = 0.5 - (z - 0.8) / 2.6 * 0.2
        kit.limb(t["wood"], (-f, -f, z), (f, -f, z), 0.04)
        kit.limb(t["wood"], (f, -f, z), (f, f, z), 0.04)
    kit.box(t["dark_wood"], (0, 0, 3.4), (0.8, 0.8, 0.08))
    kit.cylinder(t["iron"], (0, 0, 3.6), 0.35, 0.35, sides=8)
    kit.fire((0, 0), size=0.45, z=3.6)
