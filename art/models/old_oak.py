"""Old oak (data/town.json obstacles "old_oak"): a huge gnarled oak the elders won't let anyone fell."""
import math


def build(kit):
    t = kit.town_mats()
    oak = kit.mat("oak", (0.24, 0.34, 0.17), noise=0.5, scale=24.0)
    kit.cone(t["dark_wood"], (0, 0, 0.8), 0.45, 0.28, 1.6, sides=8)
    for a, l in ((0.3, 1.0), (2.4, 0.9), (4.3, 1.1)):
        kit.limb(t["dark_wood"], (0, 0, 1.4), (l * math.cos(a), l * math.sin(a), 2.1), 0.12)
        kit.ball(oak, (l * math.cos(a), l * math.sin(a), 2.4), 0.75, scale=(1.1, 1.0, 0.8))
    kit.ball(oak, (0, 0, 2.8), 0.95, scale=(1.1, 1.0, 0.8))
    for a in (0.8, 2.9, 5.0):
        kit.limb(t["dark_wood"], (0, 0, 0.2), (0.7 * math.cos(a), 0.7 * math.sin(a), 0.02), 0.1)
