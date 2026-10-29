"""Market square (data/buildings.json "market"): trodden open ground with a trader's mat, baskets,
a post with a pennant and a ring of stones."""


def build(kit):
    t = kit.town_mats()
    wicker = kit.mat("wicker", (0.62, 0.48, 0.26), noise=0.5, scale=40.0)
    kit.cylinder(t["earth"], (0, 0, 0.02), 1.45, 0.04, sides=12, scale=(1.05, 0.95, 1))
    kit.stones(t["stone"], (0, 0), 1.4, n=16, size=0.09)
    kit.box(t["cloth"], (0.3, -0.35, 0.05), (0.9, 0.7, 0.03))
    for x, y in ((0.0, -0.6), (0.6, -0.5), (0.65, 0.0), (-0.6, 0.4)):
        kit.cylinder(wicker, (x, y, 0.13), 0.15, 0.26, sides=8)
    kit.pile(t["hide"], (-0.5, -0.4), n=4, size=0.12, spread=0.15)
    kit.banner(t["dark_wood"], t["cloth_blue"], (-0.2, 0.6), h=2.0, width=0.35, drop=0.5)
