"""Hut (data/buildings.json "hut"): a round daub hut with a thatched cone roof and a hide door."""
import math


def build(kit):
    daub = kit.mat("daub", (0.46, 0.33, 0.20), noise=0.45)
    thatch = kit.mat("thatch", (0.62, 0.47, 0.22), noise=0.6, scale=30.0)
    wood = kit.mat("wood", (0.20, 0.13, 0.08), noise=0.4)
    hide = kit.mat("hide", (0.50, 0.36, 0.24), noise=0.3)
    stone = kit.mat("stone", (0.42, 0.40, 0.37), noise=0.4)
    kit.cylinder(daub, (0, 0, 0.45), 1.0, 0.9, sides=10)
    roof = kit.cone(thatch, (0, 0, 1.45), 1.35, 0.1, 1.25, sides=10)
    roof.rotation_euler = (0.04, -0.05, 0.2)
    # A ring of stones round the foot of the wall.
    for i in range(14):
        a = i / 14 * 6.2832
        kit.ball(stone, (1.04 * math.cos(a), 1.04 * math.sin(a), 0.06), 0.11, scale=(1.2, 1.0, 0.7))
    # The door faces the hearth's side of the plot (+x) with a hide hung over it.
    kit.box(wood, (0.97, 0, 0.36), (0.1, 0.52, 0.72))
    kit.box(hide, (1.02, 0, 0.33), (0.04, 0.42, 0.62))
    # Roof poles poking out of the top.
    for i in range(5):
        a = i * 1.3
        kit.limb(wood, (0.05 * math.cos(a), 0.05 * math.sin(a), 1.9), (0.3 * math.cos(a), 0.3 * math.sin(a), 2.45), 0.035, sides=5)
