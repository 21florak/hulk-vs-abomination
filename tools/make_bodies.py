#!/usr/bin/env python3
"""Sculpts smooth, organic body meshes for the two giants (original designs) and writes them as
OBJ files that Roblox Studio's 3D importer can read: models/HulkBody.obj, models/AbominationBody.obj.

Each body is split into the 15 R15 body parts (plus extra layers such as hair, bone, teeth and
eyes) so it bends with the character's animations. Shapes are signed-distance "clay": ellipsoids and
tapered capsules melted together with a smooth union, then meshed with marching cubes.

Usage: python3 tools/make_bodies.py [--preview]     (needs numpy and scikit-image; matplotlib for --preview)
"""
import json
import pathlib
import sys

import numpy as np
from skimage import measure

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "models"
RES = 0.06  # studs per voxel (body); small layers use finer voxels

# Reference R15 rig at scale 1 (Roblox faces -Z, left is -X). centers in studs, ground at y=0.
REF = {
    "Head": ((0, 5.35, 0), (1.2, 1.2, 1.2)),
    "UpperTorso": ((0, 3.95, 0), (2, 1.6, 1)),
    "LowerTorso": ((0, 2.95, 0), (2, 0.4, 1)),
    "LeftUpperArm": ((-1.5, 4.165, 0), (1, 1.17, 1)),
    "RightUpperArm": ((1.5, 4.165, 0), (1, 1.17, 1)),
    "LeftLowerArm": ((-1.5, 3.055, 0), (1, 1.05, 1)),
    "RightLowerArm": ((1.5, 3.055, 0), (1, 1.05, 1)),
    "LeftHand": ((-1.5, 2.38, 0), (1, 0.3, 1)),
    "RightHand": ((1.5, 2.38, 0), (1, 0.3, 1)),
    "LeftUpperLeg": ((-0.5, 2.15, 0), (1, 1.2, 1)),
    "RightUpperLeg": ((0.5, 2.15, 0), (1, 1.2, 1)),
    "LeftLowerLeg": ((-0.5, 0.925, 0), (1, 1.25, 1)),
    "RightLowerLeg": ((0.5, 0.925, 0), (1, 1.25, 1)),
    "LeftFoot": ((-0.5, 0.15, 0), (1, 0.3, 1)),
    "RightFoot": ((0.5, 0.15, 0), (1, 0.3, 1)),
}


# ---------------------------------------------------------------------------- SDF primitives
class E:  # ellipsoid
    def __init__(s, c, r, sub=False, k=None):
        s.c, s.r, s.sub, s.k = np.array(c, float), np.array(r, float), sub, k

    def d(s, p):
        q = (p - s.c) / s.r
        k0 = np.linalg.norm(q, axis=1)
        k1 = np.linalg.norm(q / s.r, axis=1)
        return k0 * (k0 - 1) / np.maximum(k1, 1e-6)

    def box(s):
        return s.c - s.r, s.c + s.r


class C:  # tapered capsule (round cone) from a (radius ra) to b (radius rb)
    def __init__(s, a, b, ra, rb, sub=False, k=None):
        s.a, s.b, s.ra, s.rb, s.sub, s.k = np.array(a, float), np.array(b, float), ra, rb, sub, k

    def d(s, p):
        ba = s.b - s.a
        h = np.clip(((p - s.a) @ ba) / (ba @ ba), 0, 1)
        return np.linalg.norm(p - s.a - h[:, None] * ba, axis=1) - (s.ra + (s.rb - s.ra) * h)

    def box(s):
        r = max(s.ra, s.rb)
        return np.minimum(s.a, s.b) - r, np.maximum(s.a, s.b) + r


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def field(prims, p, k):
    d = None
    for pr in prims:
        if pr.sub:
            continue
        v = pr.d(p)
        d = v if d is None else smin(d, v, pr.k or k)
    for pr in prims:
        if pr.sub:  # carve (smooth subtraction)
            kk = pr.k or k * 0.5
            d = -smin(-d, pr.d(p), kk)
    return d


def mesh(prims, k=0.12, res=RES):
    lo = np.min([pr.box()[0] for pr in prims if not pr.sub], axis=0) - 0.2
    hi = np.max([pr.box()[1] for pr in prims if not pr.sub], axis=0) + 0.2
    n = np.ceil((hi - lo) / res).astype(int) + 1
    axes = [lo[i] + np.arange(n[i]) * res for i in range(3)]
    g = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)
    vol = -field(prims, g, k).reshape(n)  # inside positive
    verts, faces, normals, _ = measure.marching_cubes(vol, 0, spacing=(res, res, res))
    return verts + lo, faces, normals


def mirror(prims):
    out = []
    for pr in prims:
        if isinstance(pr, E):
            out.append(E(pr.c * [-1, 1, 1], pr.r, pr.sub, pr.k))
        else:
            out.append(C(pr.a * [-1, 1, 1], pr.b * [-1, 1, 1], pr.ra, pr.rb, pr.sub, pr.k))
    return out


# ---------------------------------------------------------------------------- Hulk (left side; right is mirrored)
def hulk():
    P = {}
    P["UpperTorso"] = [
        E((0, 3.95, 0.02), (1.05, 0.85, 0.62)),  # ribcage
        E((-0.45, 4.22, -0.36), (0.55, 0.36, 0.3)), E((0.45, 4.22, -0.36), (0.55, 0.36, 0.3)),  # pecs
        E((0, 4.72, 0.12), (0.85, 0.32, 0.45)),  # traps
        C((0, 4.55, 0.05), (0, 5.0, 0.05), 0.46, 0.4),  # neck
        E((-1.28, 4.5, 0), (0.58, 0.52, 0.58)), E((1.28, 4.5, 0), (0.58, 0.52, 0.58)),  # delts
        E((-0.72, 3.75, 0.18), (0.55, 0.78, 0.5)), E((0.72, 3.75, 0.18), (0.55, 0.78, 0.5)),  # lats
        E((0, 4.25, 0.32), (0.95, 0.6, 0.42)),  # upper back
        E((-0.2, 3.55, -0.42), (0.22, 0.18, 0.14)), E((0.2, 3.55, -0.42), (0.22, 0.18, 0.14)),  # abs
        E((-0.2, 3.25, -0.4), (0.21, 0.17, 0.14)), E((0.2, 3.25, -0.4), (0.21, 0.17, 0.14)),
        E((0, 4.22, -0.58), (0.04, 0.3, 0.08), sub=True, k=0.08),  # pec cleft
    ]
    P["LowerTorso"] = [
        E((0, 2.98, 0.02), (0.92, 0.5, 0.6)),
        E((-0.38, 2.8, 0.22), (0.48, 0.42, 0.42)), E((0.38, 2.8, 0.22), (0.48, 0.42, 0.42)),
        E((0, 2.62, -0.1), (0.7, 0.3, 0.45)),
        E((-0.62, 2.8, -0.05), (0.32, 0.32, 0.32)), E((0.62, 2.8, -0.05), (0.32, 0.32, 0.32)),  # pants bunching
    ]
    P["LeftUpperArm"] = [
        C((-1.5, 4.68, 0), (-1.5, 3.6, 0), 0.42, 0.36),
        E((-1.52, 4.05, -0.2), (0.44, 0.52, 0.42)),  # biceps
        E((-1.5, 4.15, 0.2), (0.44, 0.58, 0.4)),  # triceps
        E((-1.42, 4.62, 0), (0.55, 0.42, 0.55)),  # delt tail
    ]
    P["LeftLowerArm"] = [
        C((-1.5, 3.6, 0.02), (-1.5, 2.58, 0), 0.5, 0.32),
        E((-1.7, 3.3, -0.08), (0.34, 0.48, 0.36)),  # brachioradialis
        E((-1.42, 3.3, 0.12), (0.36, 0.45, 0.36)),
        E((-1.5, 3.6, 0.2), (0.34, 0.3, 0.3)),  # elbow
    ]
    P["LeftHand"] = [
        E((-1.5, 2.28, -0.03), (0.42, 0.42, 0.46)),  # fist
        *[E((-1.5 + dx, 2.0, -0.26), (0.13, 0.13, 0.15)) for dx in (-0.27, -0.09, 0.09, 0.27)],  # knuckles
        C((-1.2, 2.3, -0.3), (-1.3, 2.05, -0.38), 0.13, 0.11),  # thumb
    ]
    P["LeftUpperLeg"] = [
        C((-0.52, 2.8, 0), (-0.5, 1.58, -0.02), 0.62, 0.45),
        E((-0.5, 2.2, -0.22), (0.5, 0.62, 0.42)),  # quads
        E((-0.68, 2.3, 0), (0.36, 0.55, 0.42)),
        E((-0.5, 2.3, 0.22), (0.46, 0.6, 0.38)),  # hamstrings
        E((-0.5, 1.62, -0.08), (0.48, 0.25, 0.45)),  # baggy knee
    ]
    P["LeftLowerLeg"] = [
        E((-0.5, 1.5, -0.1), (0.42, 0.3, 0.42)),  # knee
        C((-0.5, 1.55, 0), (-0.5, 0.35, 0), 0.44, 0.3),
        E((-0.5, 1.12, 0.17), (0.44, 0.5, 0.42)),  # calf
        E((-0.5, 0.55, 0), (0.4, 0.18, 0.4)),  # ragged hem bulge
    ]
    P["LeftFoot"] = [
        E((-0.5, 0.2, -0.18), (0.42, 0.22, 0.62)),
        E((-0.5, 0.28, 0.24), (0.3, 0.28, 0.3)),  # heel
        *[E((-0.5 + dx, 0.12, -0.72), (0.1, 0.1, 0.12)) for dx in (-0.25, -0.08, 0.08, 0.25)],  # toes
        C((-0.5, 0.3, 0.1), (-0.5, 0.55, 0.05), 0.3, 0.3),  # ankle
    ]
    P["Head"] = [
        E((0, 5.48, 0.06), (0.5, 0.55, 0.56)),  # cranium
        E((0, 5.04, -0.18), (0.5, 0.3, 0.42)),  # heavy jaw
        E((0, 5.0, -0.42), (0.3, 0.16, 0.16)),  # chin
        C((-0.42, 5.6, -0.4), (-0.06, 5.47, -0.52), 0.1, 0.12), C((0.42, 5.6, -0.4), (0.06, 5.47, -0.52), 0.1, 0.12),  # angry, slanted brow
        E((-0.3, 5.26, -0.38), (0.2, 0.16, 0.16)), E((0.3, 5.26, -0.38), (0.2, 0.16, 0.16)),  # cheekbones
        C((0, 5.45, -0.52), (0, 5.24, -0.6), 0.07, 0.12),  # nose
        E((-0.5, 5.36, 0.02), (0.08, 0.16, 0.12)), E((0.5, 5.36, 0.02), (0.08, 0.16, 0.12)),  # ears
        C((0, 4.85, 0.06), (0, 5.15, 0.04), 0.42, 0.42),  # neck
        E((-0.2, 5.37, -0.55), (0.13, 0.07, 0.1), sub=True, k=0.05), E((0.2, 5.37, -0.55), (0.13, 0.07, 0.1), sub=True, k=0.05),  # sockets
        E((0, 5.07, -0.6), (0.26, 0.085, 0.14), sub=True, k=0.04),  # snarling, bared mouth
        E((0, 5.6, -0.62), (0.03, 0.08, 0.06), sub=True, k=0.04),  # furrow
    ]
    P["Head_Hair"] = [
        E((0, 5.68, 0.06), (0.56, 0.4, 0.6)),
        E((0, 5.42, 0.36), (0.5, 0.45, 0.3)),
        E((0, 5.0, 0.0), (0.55, 0.55, 0.65), sub=True, k=0.05),  # keep it on top/back
        E((0, 5.42, -0.55), (0.6, 0.24, 0.22), sub=True, k=0.05),  # hairline above the brow
    ]
    P["Head_Mouth"] = [E((0, 5.07, -0.5), (0.24, 0.07, 0.08))]
    P["Head_Teeth"] = [E((0, 5.12, -0.53), (0.2, 0.03, 0.06)), E((0, 5.02, -0.53), (0.18, 0.028, 0.06))]
    P["Head_Eyes"] = [E((-0.2, 5.37, -0.5), (0.07, 0.035, 0.04)), E((0.2, 5.37, -0.5), (0.07, 0.035, 0.04))]
    return P


# ---------------------------------------------------------------------------- Abomination
def abomination():
    P = {}
    P["UpperTorso"] = [
        E((0, 3.95, 0.05), (0.92, 0.82, 0.55)),  # ribcage
        E((0, 4.35, 0.45), (0.85, 0.65, 0.5)),  # hunched upper back
        E((-0.38, 4.2, -0.3), (0.45, 0.3, 0.24)), E((0.38, 4.2, -0.3), (0.45, 0.3, 0.24)),  # lean pecs
        C((0, 4.6, 0.25), (0, 5.0, 0.05), 0.36, 0.3),  # forward neck
        E((-1.18, 4.48, 0.05), (0.48, 0.45, 0.5)), E((1.18, 4.48, 0.05), (0.48, 0.45, 0.5)),  # delts
        E((0, 3.4, -0.1), (0.62, 0.5, 0.42)),  # narrow belly
        *[C((s * 0.78, 3.72 - i * 0.2, -0.22), (s * 0.15, 3.92 - i * 0.2, -0.5), 0.045, 0.04) for i in range(3) for s in (-1, 1)],  # ribs showing through
        C((-0.9, 4.62, -0.18), (-0.1, 4.55, -0.42), 0.09, 0.07), C((0.9, 4.62, -0.18), (0.1, 4.55, -0.42), 0.09, 0.07),  # collarbones
        *[E((0, 4.75 - i * 0.24, 0.95 - i * 0.05), (0.13, 0.1, 0.12)) for i in range(7)],  # spine knobs
    ]
    P["UpperTorso_Bone"] = [
        *[C((s * 0.2, 4.7 - i * 0.28, 0.9 - i * 0.05), (s * 0.28, 5.15 - i * 0.3, 1.45 - i * 0.07), 0.12, 0.01) for i in range(5) for s in (-1, 1)],  # back spines
        *[C((s * (1.05 + j * 0.15), 4.8, 0.05 - j * 0.15), (s * (1.4 + j * 0.2), 5.35 - j * 0.1, 0.2 - j * 0.2), 0.12, 0.01) for j in range(3) for s in (-1, 1)],  # shoulder spikes
    ]
    P["LowerTorso"] = [
        E((0, 2.98, 0.05), (0.75, 0.45, 0.5)),
        E((-0.32, 2.8, 0.2), (0.38, 0.38, 0.36)), E((0.32, 2.8, 0.2), (0.38, 0.38, 0.36)),
        E((0, 3.0, 0.48), (0.12, 0.1, 0.12)), E((0, 2.78, 0.48), (0.12, 0.1, 0.12)),  # spine knobs
    ]
    P["LowerTorso_Bone"] = [C((0, 2.9, 0.5), (0, 3.15, 0.95), 0.1, 0.01)]
    P["LeftUpperArm"] = [
        C((-1.5, 4.65, 0.02), (-1.5, 3.6, 0), 0.34, 0.27),
        E((-1.52, 4.1, -0.12), (0.33, 0.45, 0.32)),
        E((-1.5, 4.15, 0.14), (0.32, 0.5, 0.3)),
        E((-1.45, 4.58, 0.04), (0.45, 0.38, 0.45)),
    ]
    P["LeftUpperArm_Bone"] = [C((-1.5, 3.68, 0.18), (-1.5, 3.55, 0.75), 0.15, 0.01)]  # elbow spur
    P["LeftLowerArm"] = [
        C((-1.5, 3.6, 0.04), (-1.5, 2.58, 0), 0.36, 0.22),
        E((-1.62, 3.3, -0.06), (0.26, 0.42, 0.28)),
        E((-1.5, 3.62, 0.15), (0.28, 0.24, 0.25)),
    ]
    P["LeftLowerArm_Bone"] = [C((-1.5, 3.3 - i * 0.28, 0.25), (-1.5, 3.45 - i * 0.28, 0.6), 0.08, 0.01) for i in range(3)]  # forearm blades
    P["LeftHand"] = [
        E((-1.5, 2.33, 0), (0.3, 0.3, 0.32)),
        *[C((-1.5 + dx, 2.18, -0.12), (-1.5 + dx * 1.2, 1.78, -0.2), 0.08, 0.06) for dx in (-0.2, -0.07, 0.07, 0.2)],  # long fingers
        C((-1.25, 2.3, -0.2), (-1.18, 2.05, -0.36), 0.08, 0.06),
    ]
    P["LeftHand_Bone"] = [C((-1.5 + dx * 1.2, 1.82, -0.2), (-1.5 + dx * 1.3, 1.48, -0.38), 0.065, 0.005) for dx in (-0.2, -0.07, 0.07, 0.2)]  # claws
    P["LeftUpperLeg"] = [
        C((-0.5, 2.8, 0.02), (-0.5, 1.58, 0), 0.48, 0.32),
        E((-0.5, 2.25, -0.16), (0.4, 0.58, 0.34)),
        E((-0.5, 2.3, 0.18), (0.36, 0.55, 0.3)),
    ]
    P["LeftLowerLeg"] = [
        E((-0.5, 1.52, -0.05), (0.32, 0.26, 0.32)),
        C((-0.5, 1.55, 0), (-0.5, 0.35, 0.02), 0.32, 0.2),
        E((-0.5, 1.15, 0.14), (0.32, 0.45, 0.32)),
    ]
    P["LeftLowerLeg_Bone"] = [C((-0.5, 1.5, -0.2), (-0.5, 1.75, -0.65), 0.15, 0.01)]  # knee spur
    P["LeftFoot"] = [
        E((-0.5, 0.2, -0.15), (0.34, 0.2, 0.55)),
        E((-0.5, 0.26, 0.24), (0.24, 0.24, 0.26)),
        C((-0.5, 0.3, 0.05), (-0.5, 0.55, 0.02), 0.22, 0.22),
        *[C((-0.5 + dx, 0.16, -0.55), (-0.5 + dx * 1.2, 0.1, -0.8), 0.08, 0.06) for dx in (-0.2, 0, 0.2)],
    ]
    P["LeftFoot_Bone"] = [C((-0.5 + dx * 1.2, 0.12, -0.78), (-0.5 + dx * 1.3, 0.04, -1.05), 0.065, 0.005) for dx in (-0.2, 0, 0.2)]
    P["Head"] = [
        E((0, 5.45, 0.18), (0.42, 0.48, 0.6)),  # long, swept-back skull
        E((0, 5.1, -0.22), (0.36, 0.26, 0.4)),  # jutting jaw
        E((0, 5.0, -0.45), (0.24, 0.14, 0.16)),  # chin
        E((0, 5.5, -0.32), (0.42, 0.11, 0.16)),  # brow
        E((-0.28, 5.28, -0.3), (0.16, 0.13, 0.17)), E((0.28, 5.28, -0.3), (0.16, 0.13, 0.17)),  # hard cheekbones
        C((0, 4.85, 0.12), (0, 5.15, 0.08), 0.3, 0.32),  # neck
        E((-0.19, 5.38, -0.45), (0.12, 0.09, 0.12), sub=True, k=0.05), E((0.19, 5.38, -0.45), (0.12, 0.09, 0.12), sub=True, k=0.05),  # sunken sockets
        E((0, 5.08, -0.58), (0.28, 0.09, 0.2), sub=True, k=0.04),  # gaping maw
        E((-0.28, 5.1, -0.35), (0.06, 0.12, 0.12), sub=True, k=0.04), E((0.28, 5.1, -0.35), (0.06, 0.12, 0.12), sub=True, k=0.04),  # gaunt hollows
    ]
    P["Head_Ears"] = [C((s * 0.38, 5.42, 0.1), (s * 0.62, 5.62, 0.75), 0.12, 0.015) for s in (-1, 1)]  # long swept-back ears
    P["Head_Bone"] = [E((0, 5.84, 0.25), (0.08, 0.1, 0.45))] + [C((s * 0.17, 5.78, -0.05), (s * 0.24, 6.05, 0.35), 0.06, 0.01) for s in (-1, 1)]  # skull ridge + brow horns
    P["Head_Teeth"] = [C((dx, 5.16, -0.5), (dx, 5.02, -0.53), 0.035, 0.005) for dx in (-0.18, -0.06, 0.06, 0.18)] + [C((dx, 4.99, -0.5), (dx, 5.11, -0.53), 0.03, 0.005) for dx in (-0.12, 0, 0.12)]
    P["Head_Mouth"] = [E((0, 5.08, -0.46), (0.26, 0.08, 0.14))]
    P["Head_Eyes"] = [E((-0.19, 5.38, -0.42), (0.05, 0.035, 0.04)), E((0.19, 5.38, -0.42), (0.05, 0.035, 0.04))]
    return P


# ---------------------------------------------------------------------------- assemble
def complete(P):
    """Mirror Left* parts (and their layers) to Right*."""
    out = dict(P)
    for name, prims in P.items():
        if name.startswith("Left"):
            out["Right" + name[4:]] = mirror(prims)
    return out


def build(P):
    parts = {}
    for name, prims in complete(P).items():
        layer = "_" in name
        v, f, n = mesh(prims, k=0.06 if layer else 0.12, res=(0.02 if name.endswith(("Teeth", "Eyes")) else 0.04) if layer else RES)
        parts[name] = (v, f, n)
        print(f"  {name:22s} {len(f):6d} tris")
    return parts


def write_obj(path, parts):
    lines = ["# Generated by tools/make_bodies.py (original design)"]
    offset = 1
    for name, (v, f, n) in parts.items():
        lines.append(f"o {name}")
        lines.append(f"g {name}")
        lines += [f"v {x:.4f} {y:.4f} {z:.4f}" for x, y, z in v]
        lines += [f"vn {x:.4f} {y:.4f} {z:.4f}" for x, y, z in n]
        lines += [f"f {a + offset}//{a + offset} {b + offset}//{b + offset} {c + offset}//{c + offset}" for a, b, c in f]
        offset += len(v)
    path.write_text("\n".join(lines) + "\n")


def metadata(parts):
    meta = {}
    for name, (v, _, _) in parts.items():
        lo, hi = v.min(0), v.max(0)
        meta[name] = {"center": ((lo + hi) / 2).round(4).tolist(), "size": (hi - lo).round(4).tolist()}
    return meta


def preview(parts, path, colors):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LightSource
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    fig = plt.figure(figsize=(14, 9), facecolor="#202024")
    light = np.array([-0.35, 0.55, -0.75])
    light /= np.linalg.norm(light)
    tris, cols = [], []
    for name, (v, f, n) in parts.items():
        layer = name.split("_")[1] if "_" in name else ("Pants" if name in colors.get("pants_parts", ()) else "Skin")
        base = np.array(colors[layer])
        fn = n[f].mean(1)
        shade = np.clip(fn @ light, 0, 1) * 0.8 + 0.2
        tris.append(v[f])
        cols.append(np.clip(base[None, :] * shade[:, None], 0, 1))
    tris, cols = np.concatenate(tris), np.concatenate(cols)
    for i, (az, title) in enumerate(((-90, "front"), (-55, "3/4"), (90, "back"))):
        ax = fig.add_subplot(1, 3, i + 1, projection="3d", facecolor="#202024")
        tri = tris[:, :, [0, 2, 1]]  # y-up -> z-up
        ax.add_collection3d(Poly3DCollection(tri, facecolors=cols, edgecolors="none"))
        ax.set_xlim(-2, 2); ax.set_ylim(-2, 2); ax.set_zlim(0.2, 6.2)
        ax.set_box_aspect((4, 4, 6))
        ax.view_init(elev=6, azim=az)
        ax.set_axis_off()
        ax.set_title(title, color="w")
    plt.tight_layout()
    plt.savefig(path, dpi=90, facecolor=fig.get_facecolor())
    plt.close(fig)


def write_lua(meta):
    """The game reads this to fit each imported mesh onto its body part."""
    def v3(xs):
        return "Vector3.new(" + ", ".join(f"{x:g}" for x in xs) + ")"

    lines = ["-- Generated by tools/make_bodies.py: where each body mesh sits on the reference R15 rig.", "return {"]
    for key, entries in meta.items():
        lines.append(f"\t{key} = {{")
        for name, m in entries.items():
            lines.append(f"\t\t{name} = {{ center = {v3(m['center'])}, size = {v3(m['size'])} }},")
        lines.append("\t},")
    lines.append("}")
    (ROOT / "src/server/Services/BodyMeshes.lua").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    meta = {"ref": {k: {"center": list(c), "size": list(s)} for k, (c, s) in REF.items()}}
    looks = {
        "Hulk": (hulk, {"Skin": (0.30, 0.54, 0.18), "Pants": (0.23, 0.18, 0.33), "Hair": (0.07, 0.07, 0.06), "Teeth": (0.9, 0.88, 0.8), "Eyes": (0.8, 1, 0.6), "Mouth": (0.12, 0.03, 0.03),
                        "pants_parts": ("LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg")}),
        "Abomination": (abomination, {"Skin": (0.44, 0.48, 0.42), "Bone": (0.72, 0.68, 0.6), "Ears": (0.44, 0.48, 0.42), "Teeth": (0.85, 0.82, 0.72), "Eyes": (1, 0.63, 0.2), "Mouth": (0.12, 0.03, 0.03)}),
    }
    for label, (make, colors) in looks.items():
        print(label)
        parts = build(make())
        write_obj(OUT / f"{label}Body.obj", parts)
        meta[label] = metadata(parts)
        if "--preview" in sys.argv:
            preview(parts, OUT / f"{label}Preview.png", colors)
    (OUT / "bodies.json").write_text(json.dumps(meta, indent=1))
    write_lua(meta)
