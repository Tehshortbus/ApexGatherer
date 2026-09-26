"""Draws ApexGatherer's textures into Media/ (32-bit TGA, white where they get tinted in game).

  Icon.tga  the addon icon: a gold peak with a spark at the summit, on a round teal badge
  Dot.tga   the HUD trail's footprint
  North.tga the HUD's north arrow (a chevron pointing up)
  Knob.tga  a route/taboo point you can drag: a white knob with a dark rim
  Add.tga   the handle that adds a point: a dark disc with a white plus
  PinRing.tga the ring around a node that tracking shows (sized in game to fit the minimap's blip)
  Marker*.tga the node pins, in pairs: a picture and the part of it tinted for the node
              Rock + Ore, Leaves + Bloom, Water + Fish, Chest + Fittings
  MaskRound.tga, MaskHole.tga  masks for the zone map round the HUD's minimap: a disc with a soft
              edge (the HUD's circle), and a soft hole (where the minimap's terrain is)

The icon is drawn in a 128-unit design space but written at 32 px: WoW doesn't shrink addon
TGAs smoothly (no mipmaps), so an icon shown at ~21 px has to be close to that size already.

Run from the addon folder: python3 dev/make_media.py
"""
import math
import struct

SUPER = 8   # samples per pixel along each axis, for smooth edges


def write_tga(path, size, pixels):
    """pixels: rows of (r, g, b, a) floats 0..1, top row first"""
    data = bytearray()
    for row in pixels:
        for r, g, b, a in row:
            data += bytes((round(b * 255), round(g * 255), round(r * 255), round(a * 255)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header + bytes(data))


def render(size, shade, design=None, clear=(0.0, 0.0, 0.0)):
    """shade(x, y) -> (r, g, b, a) at a point in 0..design; averaged over SUPER x SUPER samples.
    Fully transparent pixels get the colour `clear`, so filtering doesn't pull dark fringes in."""
    design = design or size
    k = design / size
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SUPER):
                for sx in range(SUPER):
                    r, g, b, a = shade((px + (sx + 0.5) / SUPER) * k, (py + (sy + 0.5) / SUPER) * k)
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            n = SUPER * SUPER
            alpha = acc[3] / n
            if alpha > 0:
                row.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], alpha))
            else:
                row.append(tuple(clear) + (0.0,))
        rows.append(row)
    return rows


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def inside_triangle(x, y, a, b, c):
    def side(p, q):
        return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0])
    d1, d2, d3 = side(a, b), side(b, c), side(c, a)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def icon(x, y):
    cx = cy = 64.0
    d = math.hypot(x - cx, y - cy)
    if d > 62:
        return (0, 0, 0, 0)
    # gold rim
    if d > 57:
        return mix((1.0, 0.86, 0.45), (0.55, 0.36, 0.1), (d - 57) / 5) + (1.0,)
    # the badge: teal, lighter in the middle
    color = mix((0.13, 0.36, 0.40), (0.04, 0.12, 0.15), d / 57)
    apex, left, right, foot = (64, 22), (20, 98), (108, 98), (58, 98)
    if y <= 98:
        # the peak's lit left face and shaded right face
        if inside_triangle(x, y, apex, left, foot):
            color = mix((1.0, 0.85, 0.42), (0.78, 0.52, 0.16), (y - 22) / 76)
        elif inside_triangle(x, y, apex, foot, right):
            color = mix((0.82, 0.58, 0.2), (0.48, 0.29, 0.07), (y - 22) / 76)
        # a smaller ridge in front, bottom right, lit and shaded the same way
        if inside_triangle(x, y, (86, 58), (66, 98), (84, 98)):
            color = mix((0.93, 0.7, 0.28), (0.6, 0.38, 0.1), (y - 58) / 40)
        elif inside_triangle(x, y, (86, 58), (84, 98), (106, 98)):
            color = mix((0.7, 0.47, 0.14), (0.42, 0.25, 0.06), (y - 58) / 40)
    # the spark at the summit: a four-pointed star with a soft glow
    sx, sy = x - 64, y - 20
    star = max(0.0, 1 - (abs(sx) * 0.9 + abs(sy) * 0.18) / 3.2) + max(0.0, 1 - (abs(sy) * 0.9 + abs(sx) * 0.18) / 3.2)
    glow = max(0.0, 1 - math.hypot(sx, sy) / 11) ** 2 * 0.6
    color = mix(color, (1.0, 1.0, 0.9), min(1.0, star + glow))
    return color + (1.0,)


def dot(x, y, size=32):
    d = math.hypot(x - size / 2, y - size / 2)
    return (1.0, 1.0, 1.0, max(0.0, min(1.0, (13 - d) / 3)))


def north(x, y):
    # a chevron: the triangle (16,3)-(29,28)-(3,28) with a notch cut up from its base
    body = inside_triangle(x, y, (16, 3), (29, 28), (3, 28))
    notch = inside_triangle(x, y, (16, 17), (24, 29), (8, 29))
    return (1.0, 1.0, 1.0, 1.0 if body and not notch else 0.0)


def knob(x, y, size=32):
    d = math.hypot(x - size / 2, y - size / 2)
    if d > 14:
        return (0.05, 0.05, 0.05, max(0.0, 15 - d))
    if d > 10.5:
        return (0.05, 0.05, 0.05, 1.0)
    shade = 1.0 - 0.18 * max(0.0, (y - 10) / 12)   # a little shading toward the bottom
    return (shade, shade, shade, 1.0)


def add(x, y, size=32):
    d = math.hypot(x - size / 2, y - size / 2)
    if d > 13:
        return (0.0, 0.0, 0.0, max(0.0, 14 - d) * 0.75)
    cx, cy = abs(x - size / 2), abs(y - size / 2)
    plus = (cx < 2 and cy < 8) or (cy < 2 and cx < 8)
    return (1.0, 1.0, 1.0, 1.0) if plus else (0.0, 0.0, 0.0, 0.75)


def pin_ring(x, y, size=32):
    # a solid line near the texture's edge, so the texture's size is the ring's size; its inside
    # edge is at 11.75 of 16, which the default size puts on the rim of the minimap's blip
    d = math.hypot(x - size / 2, y - size / 2)
    return (1.0, 1.0, 1.0, max(0.0, min(1.0, 2.5 - abs(d - 13.25))))


# Node markers: each is a picture (kept as drawn) plus a part drawn in white and grey that the
# game tints for the node (the ore's colour, the herb's blossom, the fish, the chest's fittings).
OUTLINE = 1.6   # design units of dark edge around every shape


def edged(inside, fill, edge):
    """inside: how far a point is inside the shape (negative outside); fill: colour inside"""
    if inside < 0:
        return (edge[0], edge[1], edge[2], max(0.0, 1 + inside))   # a soft outer edge
    if inside < OUTLINE:
        return edge + (1.0,)
    return fill + (1.0,)


def circle_in(x, y, cx, cy, r):
    return r - math.hypot(x - cx, y - cy)


def ellipse_in(x, y, cx, cy, rx, ry, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    dx, dy = x - cx, y - cy
    u, v = dx * c + dy * s, -dx * s + dy * c
    k = math.hypot(u / rx, v / ry)
    return (1 - k) * min(rx, ry)


def polygon_in(x, y, pts):
    """signed distance inside a convex polygon given clockwise on screen (y down)"""
    best = math.inf
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        ex, ey = bx - ax, by - ay
        length = math.hypot(ex, ey)
        best = min(best, ((x - ax) * ey - (y - ay) * ex) / -length)
    return best


# the rock: a lumpy boulder, lit from the top left
ROCK_LUMPS = ((16, 19, 11), (9, 21, 7), (23, 21, 7.5), (14, 12, 7), (20, 13, 6.5))


def rock_inside(x, y):
    return min(max(circle_in(x, y, *lump) for lump in ROCK_LUMPS), 28.5 - y)


def marker_rock(x, y):
    inside = rock_inside(x, y)
    light = 1 - ((x - 8) * 0.5 + (y - 6)) / 30
    fill = mix((0.30, 0.28, 0.27), (0.66, 0.63, 0.60), light)
    # a crack or two
    if abs((y - 20) - 0.45 * (x - 6)) < 0.6 and 9 < x < 16 or abs((x - 21) + 0.3 * (y - 22)) < 0.6 and 19 < y < 27:
        fill = mix(fill, (0.12, 0.1, 0.1), 0.7)
    return edged(inside, fill, (0.08, 0.07, 0.06))


# the ore: big nuggets set in the rock's face, kept inside its outline
NUGGET_SCALE = 1.2
NUGGETS = (((5.5, 18.5), (11, 12.5), (15.5, 18), (10, 24.5)),
           ((16, 10), (22.5, 7.5), (25, 14), (18.5, 16.5)),
           ((16.5, 21.5), (23, 17.5), (27, 23.5), (20.5, 27.5)))


def grown(pts):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return tuple((cx + (x - cx) * NUGGET_SCALE, cy + (y - cy) * NUGGET_SCALE) for x, y in pts), cx, cy


BIG_NUGGETS = tuple(grown(pts) for pts in NUGGETS)


def marker_ore(x, y):
    room = rock_inside(x, y) - OUTLINE   # what's left inside the rock's dark edge
    if room < -1:
        return (0, 0, 0, 0)
    for pts, cx, cy in BIG_NUGGETS:
        inside = min(polygon_in(x, y, pts), room)
        if inside > -1:
            # a lit upper-left facet and a shaded lower-right one
            shade = 1.0 if (x - cx) + (y - cy) < 0 else 0.68
            if inside < 1.1:
                return (0.16, 0.14, 0.12, max(0.0, min(1.0, 1 + inside)))
            return (shade, shade, shade, 1.0)
    return (0, 0, 0, 0)


# the herb: leaves and a stem under a blossom
LEAVES = ((10, 21, 7.5, 3.2, -0.75), (22, 21, 7.5, 3.2, 0.75), (16, 23.5, 6, 2.6, 1.5708))


def marker_leaves(x, y):
    inside = max(ellipse_in(x, y, *leaf) for leaf in LEAVES)
    inside = max(inside, min(1.4 - abs(x - 16), 29 - y, y - 10))   # the stem
    fill = mix((0.14, 0.42, 0.12), (0.42, 0.78, 0.26), 1 - (y - 14) / 16)
    # the leaves' middle veins
    for cx, cy, _, _, angle in LEAVES[:2]:
        if abs((x - cx) * math.sin(angle) - (y - cy) * math.cos(angle)) < 0.45 and abs(x - cx) < 5:
            fill = mix(fill, (0.1, 0.3, 0.08), 0.6)
    return edged(inside, fill, (0.04, 0.16, 0.04))


def marker_bloom(x, y):
    cx, cy = 16, 10
    dx, dy = x - cx, y - cy
    r, a = math.hypot(dx, dy), math.atan2(dy, dx)
    petal = 4.2 + 4.2 * abs(math.cos(2.5 * (a + math.pi / 2)))   # five petals, one pointing up
    inside = petal - r
    if inside < -1:
        return (0, 0, 0, 0)
    if inside < 0.9:
        return (0.14, 0.12, 0.12, max(0.0, min(1.0, 1 + inside)))
    if r < 2.6:
        return (0.55, 0.5, 0.45, 1.0)          # the heart, darker than the petals
    shade = 1.0 - 0.3 * max(0.0, (dx + dy) / 12)
    return (shade, shade, shade, 1.0)


# the pool: rippling water
def marker_water(x, y):
    inside = circle_in(x, y, 16, 16.5, 13.5)
    d = math.hypot(x - 16, y - 16.5)
    fill = mix((0.30, 0.62, 0.92), (0.08, 0.28, 0.58), d / 13)
    for ripple in (5.5, 10):
        if abs(d - ripple) < 0.8:
            fill = mix(fill, (0.75, 0.9, 1.0), 0.75)
    return edged(inside, fill, (0.02, 0.1, 0.24))


# the fish swimming in it
def marker_fish(x, y):
    body = ellipse_in(x, y, 14, 16.5, 8, 4.3)
    tail = polygon_in(x, y, ((20.5, 16.5), (26.5, 11.5), (26.5, 21.5)))
    inside = max(body, tail)
    if inside < -1:
        return (0, 0, 0, 0)
    if inside < 0.9:
        return (0.1, 0.1, 0.12, max(0.0, min(1.0, 1 + inside)))
    if math.hypot(x - 9.5, y - 15.5) < 1.2:
        return (0.05, 0.05, 0.05, 1.0)          # the eye
    shade = 1.0 - 0.35 * max(0.0, (y - 14) / 6)
    return (shade, shade, shade, 1.0)


# the chest: a wooden box with a rounded lid
def chest_inside(x, y):
    body = min(x - 4, 28 - x, y - 14, 28 - y)
    lid = min(ellipse_in(x, y, 16, 14, 12, 7), 15 - y)
    return max(body, lid)


def marker_chest(x, y):
    inside = chest_inside(x, y)
    fill = mix((0.62, 0.38, 0.17), (0.38, 0.21, 0.08), (y - 7) / 21)
    if y > 14 and (y - 14) % 4.5 < 0.6:
        fill = mix(fill, (0.2, 0.1, 0.04), 0.6)   # the planks
    if 13.8 < y < 15.4:
        fill = mix(fill, (0.15, 0.08, 0.03), 0.8)   # the lid's seam
    return edged(inside, fill, (0.1, 0.05, 0.02))


# its metal fittings: two straps and a lock
def marker_fittings(x, y):
    if chest_inside(x, y) < OUTLINE:
        return (0, 0, 0, 0)
    lock = min(x - 13, 19 - x, y - 12.5, 21 - y)
    if lock > -0.8:
        if lock < 0.9:
            return (0.12, 0.1, 0.08, 1.0)
        if math.hypot(x - 16, y - 16) < 1.1 or (abs(x - 16) < 0.5 and 16 < y < 19):
            return (0.05, 0.04, 0.03, 1.0)     # the keyhole
        return (1.0, 1.0, 1.0, 1.0)
    for sx in (8.5, 23.5):
        if abs(x - sx) < 1.7:
            shade = 0.95 - 0.35 * (y - 7) / 21
            return (shade, shade, shade, 1.0) if abs(x - sx) < 1.2 else (0.12, 0.1, 0.08, 1.0)
    return (0, 0, 0, 0)


def mask_round(x, y, size=128):
    # opaque to 97% of the radius, fading out by its edge
    d = math.hypot(x - size / 2, y - size / 2) / (size / 2)
    return (1.0, 1.0, 1.0, max(0.0, min(1.0, (1.0 - d) / 0.03)))


def mask_hole(x, y, size=128):
    # clear to 90% of the radius, fading in by its edge; the game sizes it so the fade straddles
    # the minimap's rim, and clamps to white past the texture, so all round it shows
    d = math.hypot(x - size / 2, y - size / 2) / (size / 2)
    t = max(0.0, min(1.0, (d - 0.9) / 0.1))
    return (1.0, 1.0, 1.0, t * t * (3 - 2 * t))


MARKERS = {
    "MarkerRock": (marker_rock, (0.08, 0.07, 0.06)),
    "MarkerOre": (marker_ore, (0.16, 0.14, 0.12)),
    "MarkerLeaves": (marker_leaves, (0.04, 0.16, 0.04)),
    "MarkerBloom": (marker_bloom, (0.14, 0.12, 0.12)),
    "MarkerWater": (marker_water, (0.02, 0.1, 0.24)),
    "MarkerFish": (marker_fish, (0.1, 0.1, 0.12)),
    "MarkerChest": (marker_chest, (0.1, 0.05, 0.02)),
    "MarkerFittings": (marker_fittings, (0.12, 0.1, 0.08)),
}


if __name__ == "__main__":
    write_tga("Media/Icon.tga", 32, render(32, icon, design=128, clear=(0.55, 0.36, 0.1)))
    write_tga("Media/Dot.tga", 32, render(32, dot))
    write_tga("Media/North.tga", 32, render(32, north, clear=(1.0, 1.0, 1.0)))
    write_tga("Media/Knob.tga", 32, render(32, knob, clear=(0.05, 0.05, 0.05)))
    write_tga("Media/Add.tga", 32, render(32, add))
    write_tga("Media/PinRing.tga", 32, render(32, pin_ring, clear=(1.0, 1.0, 1.0)))
    for name, (shade, clear) in MARKERS.items():
        write_tga("Media/%s.tga" % name, 32, render(32, shade, clear=clear))
    write_tga("Media/MaskRound.tga", 128, render(128, mask_round, clear=(1.0, 1.0, 1.0)))
    write_tga("Media/MaskHole.tga", 128, render(128, mask_hole, clear=(1.0, 1.0, 1.0)))
    print("Media/Icon.tga, Dot.tga, North.tga, Knob.tga, Add.tga, PinRing.tga, the node markers and masks written")
