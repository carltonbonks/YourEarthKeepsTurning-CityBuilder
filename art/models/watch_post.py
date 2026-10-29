"""Watch post (data/buildings.json "watch_post"): a raised wooden platform on four legs with a
hide screen and a ladder, where an archer keeps watch."""


def build(kit):
    t = kit.town_mats()
    for sx in (-1, 1):
        for sy in (-1, 1):
            kit.post(t["wood"], sx * 0.55, sy * 0.55, 2.6, 0.08, lean=(-sx * 0.12, -sy * 0.12))
    kit.box(t["dark_wood"], (0, 0, 2.3), (1.05, 1.05, 0.1))
    # Bracing across the legs, and a ladder up the camera's side.
    kit.limb(t["wood"], (-0.55, -0.55, 0.3), (0.5, -0.5, 1.9), 0.035)
    kit.limb(t["wood"], (0.55, -0.55, 0.3), (0.5, 0.5, 1.9), 0.035)
    for s in (-0.16, 0.16):
        kit.limb(t["wood"], (0.95, s, 0), (0.5, s, 2.3), 0.03)
    for i in range(6):
        z = 0.3 + i * 0.33
        x = 0.95 - 0.45 * z / 2.3
        kit.limb(t["wood"], (x, -0.16, z), (x, 0.16, z), 0.02, sides=4)
    # A hide screen round the platform and a pointed roof.
    corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
    for (ax, ay), (bx, by) in zip(corners, corners[1:] + corners[:1]):
        kit.limb(t["wood"], (ax, ay, 2.75), (bx, by, 2.75), 0.03)
    kit.box(t["hide"], (0, -0.5, 2.55), (0.9, 0.04, 0.32))
    kit.box(t["hide"], (-0.5, 0, 2.55), (0.04, 0.9, 0.32))
    for sx in (-1, 1):
        for sy in (-1, 1):
            kit.post(t["wood"], sx * 0.45, sy * 0.45, 3.3, 0.035)
    kit.cone(t["thatch"], (0, 0, 3.55), 0.85, 0.05, 0.6, sides=4, rot=(0, 0, 0.785))
