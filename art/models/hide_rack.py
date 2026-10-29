"""Hide rack (data/buildings.json "hide_rack"): hides stretched on pole frames, a scraping log and a
tub of tanning water."""


def build(kit):
    t = kit.town_mats()
    fur = kit.mat("fur", (0.38, 0.30, 0.22), noise=0.5, scale=36.0)
    for k, x in enumerate((-0.8, 0.5)):
        for sx in (-0.5, 0.5):
            kit.post(t["wood"], x + sx, 0.3, 1.6, 0.04)
        kit.limb(t["wood"], (x - 0.55, 0.3, 1.5), (x + 0.55, 0.3, 1.5), 0.03)
        kit.limb(t["wood"], (x - 0.55, 0.3, 0.3), (x + 0.55, 0.3, 0.3), 0.03)
        kit.box(t["hide"] if k else fur, (x, 0.3, 0.9), (0.85, 0.03, 1.05), rot=(0.05, 0, 0))
    kit.limb(t["dark_wood"], (-0.8, -0.6, 0.15), (0.3, -0.7, 0.25), 0.12)
    kit.barrel(t["wood"], (0.9, -0.6), r=0.25, h=0.35, band=t["rope"])
    kit.cylinder(kit.mat("tan_water", (0.30, 0.20, 0.10), rough=0.2, noise=0.1), (0.9, -0.6, 0.34), 0.22, 0.02, sides=8)
