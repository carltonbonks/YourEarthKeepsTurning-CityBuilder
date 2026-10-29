"""War camp (data/world.json dens "war_camp"): raiders' tents behind an arc of sharpened stakes, a
war banner and a fire."""
import math


def build(kit):
    t = kit.town_mats()
    red = kit.mat("war_cloth", (0.45, 0.12, 0.08), noise=0.3)
    kit.tent(t["hide"], t["dark_wood"], at=(-0.6, 0.4), r=0.65, h=1.3)
    kit.tent(red, t["dark_wood"], at=(0.5, 0.8), r=0.55, h=1.1)
    kit.fire((0.3, -0.3), size=0.2, logs_m=t["dark_wood"])
    for i in range(9):
        a = math.radians(200 + i * 20)
        x, y = 1.6 * math.cos(a), 1.4 * math.sin(a)
        kit.limb(t["wood"], (x, y, 0), (x * 1.15, y * 1.15, 0.9), 0.05)
    kit.banner(t["dark_wood"], red, (-1.0, -0.6), h=2.2, width=0.4, drop=0.7)
    kit.ball(t["bone"], (-1.0, -0.6, 2.25), 0.08)
