"""Small things shown on cards (rendered art slice 4): relic icons and item bases. Each maker builds one object
about a metre across at most, resting on the ground at the origin, with the parts in kit.py. LOOKS makes a relic
look by name (art/card_art.json relic_looks); ITEMS makes an item base by id (data/items.json bases)."""
import math


def _m(kit):
    t = kit.town_mats()
    t.update({
        "gold": kit.mat("gold", (0.88, 0.68, 0.26), rough=0.3, noise=0.1),
        "steel": kit.mat("steel", (0.62, 0.64, 0.68), rough=0.3, noise=0.1),
        "flint": kit.mat("flint", (0.30, 0.32, 0.38), rough=0.4, noise=0.3),
        "obsidian": kit.mat("obsidian", (0.10, 0.07, 0.14), rough=0.15, noise=0.2),
        "fur": kit.mat("fur", (0.40, 0.31, 0.22), noise=0.5, scale=36.0),
        "red": kit.mat("red_paint", (0.62, 0.14, 0.10), noise=0.2),
        "amber": kit.glow("amber", (1.0, 0.62, 0.18), 1.2),
        "spirit": kit.glow("spirit", (0.6, 0.75, 1.0), 2.5),
        "leaf": kit.mat("leaf", (0.26, 0.44, 0.20), noise=0.5, scale=24.0),
    })
    return t


def blade(kit, m, hilt, length=0.8, width=0.07, guard=None, at=(0, 0)):
    """A blade lying at an angle on the ground, point toward +x."""
    x, y = at
    kit.box(m, (x + 0.1, y, 0.04), (length, width, 0.025), rot=(0, 0, 0.5))
    kit.cone(m, (x + 0.1 + length * 0.5 * math.cos(0.5), y + length * 0.5 * math.sin(0.5), 0.04), width * 0.7, 0.0, 0.12,
        sides=4, rot=(0, 1.5708, 0.5))
    hx, hy = x + 0.1 - length * 0.5 * math.cos(0.5), y - length * 0.5 * math.sin(0.5)
    kit.limb(hilt, (hx, hy, 0.04), (hx - 0.2 * math.cos(0.5), hy - 0.2 * math.sin(0.5), 0.04), 0.025)
    if guard is not None:
        kit.limb(guard, (hx - 0.1 * math.sin(0.5), hy + 0.1 * math.cos(0.5), 0.045), (hx + 0.1 * math.sin(0.5), hy - 0.1 * math.cos(0.5), 0.045), 0.02)


def spear(kit, shaft, head, at=(0, 0)):
    kit.limb(shaft, (at[0] - 0.5, at[1] - 0.25, 0.03), (at[0] + 0.4, at[1] + 0.2, 0.03), 0.02)
    kit.cone(head, (at[0] + 0.48, at[1] + 0.24, 0.03), 0.05, 0.0, 0.2, sides=4, rot=(0, 1.5708, 0.46))


def ring_of(kit, m, r, thick, z=0.03, beads=None, n=12):
    """A ring lying flat (a torc, a necklace), with beads hung on it if `beads`."""
    for i in range(n):
        a0, a1 = i / n * 2 * math.pi, (i + 1) / n * 2 * math.pi
        if i == n - 1 and beads is None:
            continue
        kit.limb(m, (r * math.cos(a0), r * math.sin(a0), z), (r * math.cos(a1), r * math.sin(a1), z), thick, sides=5)
    if beads is not None:
        for i in range(0, n, 2):
            a = i / n * 2 * math.pi
            kit.ball(beads, (r * math.cos(a), r * math.sin(a), z), thick * 2.2)


def garment(kit, m, trim=None, mail=False):
    """A tunic or coat laid out flat: body and sleeves."""
    kit.box(m, (0, 0, 0.04), (0.55, 0.42, 0.06))
    for s in (-1, 1):
        kit.box(m, (0.1, s * 0.33, 0.04), (0.18, 0.28, 0.05), rot=(0, 0, s * 0.4))
    if trim is not None:
        kit.box(trim, (0.27, 0, 0.08), (0.04, 0.42, 0.03))
    if mail:
        for i in range(4):
            kit.box(trim or m, (-0.2 + i * 0.13, 0, 0.075), (0.02, 0.4, 0.01))


def _paint(kit, t):
    kit.cylinder(t["daub"], (0, 0, 0.12), 0.2, 0.24, sides=10)
    kit.cylinder(t["red"], (0, 0, 0.245), 0.17, 0.02, sides=10)
    kit.limb(t["wood"], (0.05, 0, 0.2), (0.3, 0.1, 0.5), 0.015)


def _shells(kit, t):
    for i in range(7):
        a = i / 7 * 2 * math.pi
        kit.ball(t["bone"], (0.25 * math.cos(a), 0.25 * math.sin(a), 0.05), 0.07, scale=(1.4, 1.0, 0.6), rot=(0, 0, a))
    kit.limb(t["rope"], (-0.3, 0, 0.04), (0.3, 0, 0.04), 0.01)


def _stones(kit, t):
    for i, h in enumerate((0.7, 0.5, 0.6)):
        a = i / 3 * 2 * math.pi
        kit.box(t["stone"], (0.25 * math.cos(a), 0.25 * math.sin(a), h / 2), (0.14, 0.11, h), rot=(0.04, 0, a))


def _knife(kit, t):
    blade(kit, t["flint"], t["dark_wood"], length=0.45, width=0.08)
    kit.ball(t["red"], (0.0, -0.15, 0.01), 0.08, scale=(1.5, 1.0, 0.15))


def _sack(kit, t):
    kit.ball(t["hide"], (0, 0, 0.2), 0.25, scale=(1.0, 0.9, 1.0))
    kit.cone(t["hide"], (0, 0, 0.47), 0.08, 0.12, 0.12, sides=7)
    kit.limb(t["rope"], (-0.08, 0, 0.42), (0.08, 0, 0.42), 0.015)


def _staff(kit, t):
    kit.limb(t["dark_wood"], (-0.4, -0.2, 0.03), (0.45, 0.22, 0.03), 0.025)
    kit.ball(t["bone"], (0.48, 0.24, 0.06), 0.06)
    for i in range(3):
        kit.limb(t["rope"], (0.3 + i * 0.03, 0.15, 0.03), (0.32 + i * 0.03, 0.0, 0.0), 0.006, sides=4)


def _tooth(kit, t):
    ring_of(kit, t["rope"], 0.25, 0.008, n=16)
    kit.cone(t["bone"], (0.0, -0.25, 0.04), 0.05, 0.0, 0.2, sides=6, rot=(1.5708, 0, 0))


def _fire(kit, t):
    kit.fire((0, 0), size=0.2, logs_m=t["dark_wood"])


def _flint(kit, t):
    kit.pile(t["flint"], (0, 0), n=6, size=0.1, spread=0.18, seed=5)


def _arrows(kit, t):
    for i in range(3):
        y = -0.12 + i * 0.12
        kit.limb(t["wood"], (-0.4, y, 0.03), (0.35, y + 0.05, 0.03), 0.012)
        kit.cone(kit.glow("ember", (1.0, 0.45, 0.12), 4.0), (0.4, y + 0.055, 0.03), 0.03, 0.0, 0.1, sides=4, rot=(0, 1.5708, 0.07))


def _bowl(kit, t):
    kit.cone(t["daub"], (0, 0, 0.1), 0.15, 0.28, 0.2, sides=12)
    kit.cylinder(kit.mat("salt", (0.85, 0.85, 0.82), noise=0.2), (0, 0, 0.205), 0.26, 0.02, sides=12)


def _logs(kit, t):
    kit.logs(t["wood"], (0, 0), n=4, length=0.7, r=0.07)


def _dice(kit, t):
    for i, (x, y) in enumerate(((0, 0), (0.18, -0.1), (-0.15, 0.12))):
        kit.box(t["bone"], (x, y, 0.06), (0.12, 0.12, 0.12), rot=(0, 0, i * 0.6))
        kit.ball(t["dark_wood"], (x + 0.05, y - 0.05, 0.12), 0.015)


def _mask(kit, t):
    kit.ball(t["wood"], (0, 0, 0.3), 0.28, scale=(0.35, 1.0, 1.25))
    for s in (-1, 1):
        kit.ball(kit.mat("eye_hole", (0.04, 0.03, 0.03), noise=0.0), (0.1, s * 0.1, 0.38), 0.05, scale=(0.5, 1.2, 0.6))
        kit.box(t["red"], (0.1, s * 0.13, 0.22), (0.02, 0.08, 0.02))


def _torc(kit, t):
    ring_of(kit, t["gold"], 0.22, 0.03, n=12)
    for s in (-1, 1):
        kit.ball(t["gold"], (0.22 * math.cos(-0.25 * s), 0.22 * math.sin(-0.25 * s) - 0.0, 0.03), 0.05)


def _disc(kit, t):
    kit.cylinder(t["bronze"], (0, 0, 0.3), 0.28, 0.03, sides=20, rot=(1.5708, 0, 0.785))
    kit.cylinder(kit.glow("sun", (1.0, 0.75, 0.3), 1.2), (0.02, -0.02, 0.3), 0.1, 0.04, sides=12, rot=(1.5708, 0, 0.785))


def _crown(kit, t):
    ring_of(kit, t["bronze"], 0.2, 0.025, z=0.05, n=14)
    for i in range(7):
        a = i / 7 * 2 * math.pi
        kit.cone(t["bronze"], (0.2 * math.cos(a), 0.2 * math.sin(a), 0.14), 0.035, 0.0, 0.16, sides=4)


def _banner(kit, t):
    kit.banner(t["dark_wood"], kit.mat("black_cloth", (0.08, 0.07, 0.07), noise=0.2), (0, 0), h=0.9, width=0.45, drop=0.55)


def _drum(kit, t):
    kit.cylinder(t["wood"], (0, 0, 0.16), 0.22, 0.32, sides=12)
    kit.cylinder(t["hide"], (0, 0, 0.33), 0.23, 0.02, sides=12)
    kit.limb(t["bone"], (0.1, 0.1, 0.36), (0.35, -0.15, 0.5), 0.015)


def _wheel(kit, t):
    ring_of(kit, t["stone"], 0.25, 0.05, z=0.3, n=14)
    for i in range(4):
        a = i / 4 * math.pi
        kit.limb(t["dark_stone"], (0.25 * math.cos(a), 0.25 * math.sin(a), 0.3), (-0.25 * math.cos(a), -0.25 * math.sin(a), 0.3), 0.025)


def _horn(kit, t):
    for i in range(6):
        a = i / 6 * 1.4
        kit.cylinder(t["bone"], (0.3 * math.cos(a) - 0.15, 0.3 * math.sin(a) - 0.15, 0.06), 0.035 + 0.012 * i, 0.12, sides=8,
            rot=(1.5708, 0, a))


def _doll(kit, t):
    kit.cone(t["straw"], (0, 0, 0.2), 0.12, 0.05, 0.4, sides=7)
    kit.ball(t["straw"], (0, 0, 0.45), 0.08)
    kit.limb(t["straw"], (0, -0.15, 0.3), (0, 0.15, 0.3), 0.025)
    kit.box(t["cloth"], (0, 0, 0.25), (0.2, 0.2, 0.08))


def _pelt(kit, t):
    kit.ball(t["fur"], (0, 0, 0.03), 0.4, scale=(1.2, 0.8, 0.08))
    kit.ball(t["fur"], (0.45, 0, 0.08), 0.12, scale=(1.2, 0.9, 0.7))
    kit.cone(t["fur"], (0.45, 0.06, 0.18), 0.03, 0.0, 0.08, sides=4)


def _brand(kit, t):
    kit.limb(t["iron"], (-0.4, -0.15, 0.03), (0.2, 0.1, 0.03), 0.02)
    kit.box(kit.glow("forge", (1.0, 0.45, 0.12), 5.0), (0.27, 0.13, 0.04), (0.14, 0.14, 0.03), rot=(0, 0, 0.4))


def _bell(kit, t):
    kit.cone(t["bronze"], (0, 0, 0.18), 0.22, 0.1, 0.32, sides=12)
    kit.ball(t["bronze"], (0, 0, 0.36), 0.06)


def _belt(kit, t):
    ring_of(kit, t["hide"], 0.28, 0.025, n=14)
    for i in range(5):
        a = -0.8 + i * 0.4
        kit.cone(t["bone"], (0.28 * math.cos(a), 0.28 * math.sin(a), 0.03), 0.03, 0.0, 0.12, sides=4, rot=(1.5708, 0, a))


def _knot(kit, t):
    for i in range(3):
        a = i / 3 * 2 * math.pi
        ring_of(kit, t["rope"], 0.12, 0.018, z=0.03 + i * 0.01, n=10)
        kit.ball(t["rope"], (0.12 * math.cos(a), 0.12 * math.sin(a), 0.04), 0.04)
    kit.limb(t["rope"], (0.1, 0, 0.03), (0.4, -0.2, 0.02), 0.015)


def _feather(kit, t):
    kit.ball(t["bone"], (0, 0, 0.03), 0.3, scale=(1.2, 0.35, 0.08), rot=(0, 0, 0.5))
    kit.limb(t["dark_wood"], (-0.35, -0.2, 0.04), (0.35, 0.2, 0.04), 0.01)
    for s in (-1, 1):
        kit.ball(t["amber"], (0.3, s * 0.2 - 0.25, 0.04), 0.05)


def _skull(kit, t):
    kit.ball(t["bone"], (0, 0, 0.18), 0.18, scale=(1.2, 0.9, 1.0))
    kit.box(t["bone"], (0.16, 0, 0.06), (0.14, 0.14, 0.08))
    for s in (-1, 1):
        kit.ball(kit.mat("eye_hole", (0.04, 0.03, 0.03), noise=0.0), (0.17, s * 0.07, 0.2), 0.04)


def _stake(kit, t):
    for i in range(3):
        kit.limb(t["wood"], (-0.3, -0.15 + i * 0.15, 0.03), (0.3, -0.12 + i * 0.15, 0.03), 0.03)
        kit.cone(t["dark_wood"], (0.38, -0.12 + i * 0.15, 0.03), 0.03, 0.0, 0.14, sides=5, rot=(0, 1.5708, 0))


def _scales(kit, t):
    kit.post(t["bronze"], 0, 0, 0.5, 0.015)
    kit.limb(t["bronze"], (0, -0.3, 0.48), (0, 0.3, 0.48), 0.012)
    for s in (-1, 1):
        kit.cone(t["bronze"], (0, s * 0.3, 0.25), 0.1, 0.06, 0.04, sides=10)
        kit.limb(t["rope"], (0, s * 0.3, 0.27), (0, s * 0.3, 0.48), 0.004, sides=4)


def _idol(kit, t):
    kit.box(t["dark_stone"], (0, 0, 0.3), (0.18, 0.15, 0.6), rot=(0, 0, 0.3))
    kit.ball(t["spirit"], (0.06, -0.06, 0.45), 0.05)


def _hammer(kit, t):
    kit.limb(t["dark_wood"], (-0.35, -0.15, 0.03), (0.25, 0.1, 0.03), 0.022)
    kit.box(t["iron"], (0.28, 0.11, 0.07), (0.12, 0.28, 0.13), rot=(0, 0, 0.4))


def _bough(kit, t):
    kit.limb(t["wood"], (-0.4, -0.15, 0.03), (0.4, 0.15, 0.03), 0.02)
    for i in range(5):
        x = -0.25 + i * 0.15
        kit.ball(t["leaf"], (x, x * 0.38 + (0.06 if i % 2 else -0.06), 0.04), 0.07, scale=(1.6, 0.8, 0.3))


def _haunch(kit, t):
    kit.ball(kit.mat("meat", (0.45, 0.18, 0.12), noise=0.4), (0, 0, 0.12), 0.2, scale=(1.4, 1.0, 0.8))
    kit.limb(t["bone"], (0.25, 0, 0.12), (0.45, 0.05, 0.12), 0.03)


def _lamp(kit, t):
    kit.cylinder(t["iron"], (0, 0, 0.2), 0.12, 0.3, sides=6)
    kit.ball(t["spirit"], (0, 0, 0.2), 0.08)
    kit.cone(t["iron"], (0, 0, 0.4), 0.13, 0.03, 0.1, sides=6)


def _veil(kit, t):
    kit.ball(kit.mat("veil", (0.30, 0.36, 0.26), noise=0.4), (0, 0, 0.03), 0.38, scale=(1.1, 0.9, 0.06))
    for i in range(4):
        kit.cone(t["dark_wood"], (-0.2 + i * 0.13, 0.2 - i * 0.1, 0.06), 0.02, 0.0, 0.1, sides=4)


LOOKS = {name[1:]: fn for name, fn in list(globals().items()) if name.startswith("_") and name != "_m" and callable(fn) and not name.startswith("__")}


def look(kit, name):
    """Builds the relic look `name`."""
    LOOKS[name](kit, _m(kit))


def item(kit, base):
    """Builds the item base `base` (data/items.json)."""
    t = _m(kit)
    if base == "flint_blade":
        blade(kit, t["flint"], t["dark_wood"], length=0.5, width=0.09)
    elif base == "bone_spear":
        spear(kit, t["wood"], t["bone"])
    elif base == "obsidian_edge":
        blade(kit, t["obsidian"], t["dark_wood"], length=0.55, width=0.1)
    elif base == "hide_armour":
        garment(kit, t["hide"], t["dark_wood"])
    elif base == "fur_cloak":
        _pelt(kit, t)
    elif base == "claw_necklace":
        _tooth(kit, t)
    elif base == "antler_charm":
        kit.limb(t["bone"], (-0.2, 0, 0.03), (0.2, 0.05, 0.03), 0.03)
        for s in (-1, 1):
            kit.limb(t["bone"], (0.0, 0.0, 0.03), (0.12, s * 0.2, 0.05), 0.02)
    elif base == "amber_amulet":
        ring_of(kit, t["rope"], 0.22, 0.008, n=16)
        kit.ball(t["amber"], (0, -0.22, 0.05), 0.07)
    elif base == "bronze_sword":
        blade(kit, t["bronze"], t["dark_wood"], length=0.7, width=0.07, guard=t["bronze"])
    elif base == "bronze_axe":
        kit.limb(t["dark_wood"], (-0.35, -0.15, 0.03), (0.3, 0.12, 0.03), 0.022)
        kit.box(t["bronze"], (0.25, 0.15, 0.04), (0.08, 0.22, 0.03), rot=(0, 0, 0.4))
    elif base == "bronze_scale":
        garment(kit, t["bronze"], t["hide"])
    elif base == "bronze_torc":
        _torc(kit, {**t, "gold": t["bronze"]})
    elif base == "iron_spear":
        spear(kit, t["wood"], t["iron"])
    elif base == "steel_longsword":
        blade(kit, t["steel"], t["hide"], length=0.85, width=0.06, guard=t["iron"])
    elif base == "mail_hauberk":
        garment(kit, t["iron"], t["steel"], mail=True)
    elif base == "steel_plate":
        garment(kit, t["steel"], t["iron"])
        kit.ball(t["steel"], (0.05, 0, 0.08), 0.18, scale=(1.2, 1.0, 0.4))
    elif base == "reliquary":
        kit.box(t["gold"], (0, 0, 0.12), (0.3, 0.2, 0.24))
        kit.gable(t["gold"], (0, 0, 0.24), 0.3, 0.2, 0.1)
        kit.ball(t["spirit"], (0.0, -0.1, 0.14), 0.04)
    elif base == "wolfmothers_fang":
        blade(kit, t["bone"], t["fur"], length=0.6, width=0.1)
    elif base == "skyfall_shard":
        blade(kit, kit.glow("sky_iron", (0.55, 0.65, 0.95), 1.0), t["dark_wood"], length=0.65, width=0.09)
    elif base == "mammoth_mantle":
        _pelt(kit, {**t, "fur": kit.mat("mammoth_fur", (0.34, 0.24, 0.16), noise=0.6, scale=36.0)})
        kit.cone(t["bone"], (0.5, -0.12, 0.08), 0.04, 0.0, 0.25, sides=6, rot=(0, 1.5708, -0.4))
    elif base == "barrow_kings_ring":
        ring_of(kit, t["gold"], 0.14, 0.03, n=14)
        kit.ball(t["spirit"], (0.14, 0, 0.06), 0.05)
    elif base == "sunstone_torc":
        _torc(kit, t)
        kit.ball(kit.glow("sun", (1.0, 0.75, 0.3), 2.0), (0, 0, 0.05), 0.06)
    elif base == "oathkeeper":
        blade(kit, t["steel"], t["cloth_blue"], length=0.9, width=0.07, guard=t["gold"])
    elif base == "hollow_kings_mail":
        garment(kit, kit.mat("dark_mail", (0.18, 0.18, 0.22), rough=0.4, noise=0.2), t["spirit"], mail=True)
    else:
        raise ValueError("no item art for %s" % base)
