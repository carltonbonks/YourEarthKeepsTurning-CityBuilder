"""Bronze moot (data/buildings.json "bronze_moot"): a ring of tall stones round a speaking stone with
a bronze sun disc on a pole, the town's step into the bronze age."""
import math


def build(kit):
    t = kit.town_mats()
    for i in range(9):
        a = i / 9 * 2 * math.pi
        h = 1.2 + 0.25 * ((i * 4) % 3)
        kit.box(t["stone"], (1.15 * math.cos(a), 1.0 * math.sin(a), h / 2), (0.28, 0.22, h), rot=(0.04 * (i % 3), 0, a))
    kit.box(t["dark_stone"], (0, 0, 0.25), (0.6, 0.45, 0.5))
    kit.post(t["dark_wood"], 0, 0.1, 2.4, 0.04)
    kit.cylinder(t["bronze"], (0, 0.1, 2.4), 0.32, 0.05, sides=16, rot=(1.5708, 0, 0.785))
    kit.cylinder(kit.glow("sun", (1.0, 0.7, 0.3), 1.5), (0.02, 0.08, 2.4), 0.12, 0.06, sides=10, rot=(1.5708, 0, 0.785))
