"""Oath stone (data/buildings.json "oath_stone"): a tall dark standing stone carved with glowing
runes, on a stepped base where heroes swear."""


def build(kit):
    t = kit.town_mats()
    kit.box(t["stone"], (0, 0, 0.1), (1.6, 1.4, 0.2))
    kit.box(t["stone"], (0, 0, 0.3), (1.1, 0.95, 0.2))
    kit.box(t["dark_stone"], (0, 0, 1.4), (0.5, 0.36, 2.0), rot=(0.03, -0.04, 0.3))
    rune = kit.glow("rune", (0.75, 0.85, 1.0), 4.0)
    for k in range(4):
        kit.box(rune, (0.06, -0.18, 0.9 + k * 0.32), (0.18 - 0.03 * (k % 2), 0.02, 0.05), rot=(0, 0, 0.3))
    for s in (-1, 1):
        kit.post(t["dark_wood"], s * 0.65, -0.55, 0.9, 0.035)
        kit.ball(kit.glow("ember", (1.0, 0.45, 0.12), 4.0), (s * 0.65, -0.55, 0.95), 0.06)
