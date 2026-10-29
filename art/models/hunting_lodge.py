"""Hunting lodge (data/buildings.json "hunting_lodge"): a low timber hall with antlers on the
gables, a hide pegged out and a carcass hanging from a frame."""


def build(kit):
    t = kit.town_mats()
    meat = kit.mat("meat", (0.48, 0.20, 0.14), noise=0.4)
    kit.hall(t["wood"], t["thatch"], 2.4, 1.4, 0.8, 1.0, at=(-0.3, 0.45), door=t["dark_wood"], beams=t["dark_wood"])
    for sx in (-1, 1):
        x = -0.3 + sx * 1.32
        for s in (-1, 1):
            kit.limb(t["bone"], (x, 0.45, 1.75), (x, 0.45 + s * 0.35, 2.15), 0.03)
            kit.limb(t["bone"], (x, 0.45 + s * 0.22, 1.95), (x, 0.45 + s * 0.3, 2.3), 0.02)
    for x in (0.7, 1.3):
        kit.post(t["dark_wood"], x, -0.7, 1.4, 0.045)
    kit.limb(t["dark_wood"], (0.7, -0.7, 1.35), (1.3, -0.7, 1.35), 0.035)
    kit.ball(meat, (1.0, -0.7, 0.95), 0.16, scale=(0.8, 0.8, 1.8))
    kit.box(t["hide"], (-0.8, -0.75, 0.03), (0.8, 0.55, 0.02), rot=(0, 0, 0.2))
