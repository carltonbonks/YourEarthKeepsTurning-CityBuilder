"""Gate (data/buildings.json "gate"): two heavy posts and a lintel with a swung-open wooden door,
standing across the way people walk through. Rendered in 8 facings: facing 0 lets people through
along +x (the way out from the hearth when the gate stands on +x)."""


def build(kit):
    t = kit.town_mats()
    for s in (-1, 1):
        kit.post(t["dark_wood"], 0, s * 0.75, 1.7, 0.1)
        kit.cone(t["dark_wood"], (0, s * 0.75, 1.82), 0.1, 0.0, 0.24, sides=6)
        kit.fence(t["wood"], [(0, s * 0.85), (0, s * 1.4)], h=1.1, gap=0.18, r=0.055, rail=True)
    kit.box(t["dark_wood"], (0, 0, 1.45), (0.16, 1.7, 0.14))
    kit.box(t["hide"], (0, 0, 1.6), (0.06, 0.8, 0.16))
    # The door, swung open against the inside (toward -x).
    kit.box(t["wood"], (-0.35, 0.66, 0.6), (0.7, 0.07, 1.1))
    for z in (0.3, 0.9):
        kit.box(t["iron"], (-0.35, 0.62, z), (0.66, 0.02, 0.06))
