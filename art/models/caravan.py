"""The southern caravan's camp (data/trades.json, game/caravan_camp.gd): two covered wagons, a mule, the goods
laid out on a blue cloth (sacks, barrels, bars of tin) and the caravan's banner."""
import math


def build(kit):
    t = kit.town_mats()
    canvas = kit.mat("canvas", (0.72, 0.66, 0.52), noise=0.3)
    sack = kit.mat("sack", (0.62, 0.52, 0.34), noise=0.45)
    tin = kit.mat("tin", (0.70, 0.72, 0.74), rough=0.35, noise=0.15)
    mule = kit.mat("mule", (0.34, 0.27, 0.21), noise=0.4)

    def wagon(x, y, turn, length=1.5):
        dx, dy = math.cos(turn), math.sin(turn)
        kit.box(t["wood"], (x, y, 0.5), (length, 0.85, 0.28), rot=(0, 0, turn))
        for along in (-0.45, 0.45):
            for side in (-1, 1):
                wx = x + dx * along * length - dy * side * 0.47
                wy = y + dy * along * length + dx * side * 0.47
                kit.cylinder(t["dark_wood"], (wx, wy, 0.28), 0.28, 0.07, sides=10, rot=(1.5708, 0, turn))
        kit.cylinder(canvas, (x, y, 0.7), 0.44, length * 0.92, sides=10, rot=(0, 1.5708, turn))
        kit.limb(t["wood"], (x + dx * length * 0.5, y + dy * length * 0.5, 0.45),
            (x + dx * (length * 0.5 + 0.7), y + dy * (length * 0.5 + 0.7), 0.2), 0.03)

    wagon(0.0, 0.45, 0.25)
    wagon(-1.3, 0.85, -0.35, 1.3)
    # A mule standing in the traces of the first wagon.
    kit.box(mule, (1.45, 0.72, 0.55), (0.75, 0.3, 0.32), rot=(0, 0, 0.25))
    kit.box(mule, (1.88, 0.84, 0.78), (0.24, 0.18, 0.22), rot=(0, 0, 0.25))
    for lx, ly in ((1.2, 0.53), (1.22, 0.85), (1.65, 0.65), (1.68, 0.95)):
        kit.limb(mule, (lx, ly, 0.4), (lx, ly, 0.0), 0.04)
    # Goods laid out in front, on a blue cloth.
    kit.box(t["cloth_blue"], (-0.1, -0.75, 0.02), (1.4, 0.7, 0.02))
    for i, (sx, sy) in enumerate(((-0.55, -0.6), (-0.35, -0.95), (-0.15, -0.62))):
        kit.ball(sack, (sx, sy, 0.16), 0.17, scale=(1, 1, 1.15))
    kit.barrel(t["wood"], (0.25, -0.6), band=t["iron"])
    kit.barrel(t["wood"], (0.45, -0.95), r=0.14, h=0.34, band=t["iron"])
    for k in range(4):
        kit.box(tin, (0.0 + 0.12 * k, -1.0, 0.05 + 0.02 * (k % 2)), (0.1, 0.24, 0.05))
    kit.banner(t["wood"], t["cloth"], (-0.95, -0.35), h=1.9)
