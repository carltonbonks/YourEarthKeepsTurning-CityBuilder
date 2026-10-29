"""Barrow-wight (data/enemies.json "barrow_wight"): a gaunt grey-green dead thing in grave rags with an old blade."""


def build(kit):
    dead = kit.mat("dead_skin", (0.52, 0.58, 0.52), noise=0.3)
    rag = kit.mat("grave_rag", (0.30, 0.32, 0.30), noise=0.5)
    rust = kit.mat("rust", (0.42, 0.28, 0.18), rough=0.6, noise=0.5)
    eye = kit.mat("eye", (0.60, 0.95, 0.90), noise=0.0)
    me = kit.humanoid(dead, rag, dead, cloak=rag, boots=rag, bulk=0.85)
    hx, hy, hz = me["head"]
    for s in (-1, 1):
        kit.ball(eye, (hx + 0.12, s * 0.05, hz + 0.02), 0.025)
    x, y, z = me["hand_r"]
    kit.box(rust, (x + 0.05, y, z + 0.4), (0.05, 0.03, 0.75), rot=(0, 0.3, 0), on=me["arm_r"])
