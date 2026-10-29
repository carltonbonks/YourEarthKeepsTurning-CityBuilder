"""The Antlered King (data/enemies.json "antlered_king", a boss): a tall dark spirit with a stag's antlers."""


def build(kit):
    bark = kit.mat("bark", (0.22, 0.17, 0.13), noise=0.5)
    moss = kit.mat("moss", (0.26, 0.34, 0.18), noise=0.5, scale=30.0)
    antler = kit.mat("antler", (0.80, 0.74, 0.60), noise=0.25)
    eye = kit.mat("eye", (1.0, 0.35, 0.25), noise=0.0)
    me = kit.humanoid(bark, bark, bark, cloak=moss, boots=bark, height=1.35, bulk=1.25)
    hx, hy, hz = me["head"]
    for s in (-1, 1):
        kit.ball(eye, (hx + 0.13, s * 0.05, hz), 0.025)
        base = (hx - 0.02, s * 0.1, hz + 0.1)
        tip = (hx - 0.1, s * 0.42, hz + 0.6)
        kit.limb(antler, base, tip, 0.03, sides=5)
        kit.limb(antler, (hx - 0.05, s * 0.25, hz + 0.33), (hx + 0.12, s * 0.33, hz + 0.55), 0.022, sides=5)
        kit.limb(antler, (hx - 0.08, s * 0.35, hz + 0.48), (hx - 0.25, s * 0.45, hz + 0.68), 0.02, sides=5)
