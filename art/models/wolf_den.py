"""Wolf den (data/world.json dens "wolf_den"): a rocky outcrop with a dark cave mouth, gnawed bones
and scrub round it."""


def build(kit):
    t = kit.town_mats()
    rock = kit.mat("den_rock", (0.36, 0.33, 0.30), noise=0.5)
    scrub = kit.mat("scrub", (0.36, 0.36, 0.20), noise=0.5)
    kit.ball(rock, (-0.3, 0.3, 0.3), 1.0, scale=(1.3, 1.0, 0.85), detail=1)
    kit.ball(rock, (0.6, 0.6, 0.2), 0.7, scale=(1.0, 1.0, 0.9), detail=1, rot=(0, 0, 0.7))
    kit.ball(rock, (-1.2, -0.3, 0.1), 0.5, detail=1)
    kit.ball(kit.mat("cave", (0.03, 0.03, 0.03), noise=0.0), (0.35, -0.35, 0.3), 0.42, scale=(0.9, 0.5, 0.75))
    kit.pile(t["bone"], (0.7, -0.9), n=6, size=0.07, spread=0.3, seed=43)
    for x, y in ((-1.1, -1.0), (1.3, -0.2), (-0.8, 1.2)):
        kit.ball(scrub, (x, y, 0.15), 0.25, scale=(1.2, 1.0, 0.7))
