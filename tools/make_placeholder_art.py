"""Generate placeholder SNES-style pixel art for the game.

Run:  python tools/make_placeholder_art.py
Needs: pip install pillow

Everything here is temporary art. To use your own, draw PNGs with the SAME
size and layout and overwrite the files in assets/ (see README).
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
OUTLINE = (34, 22, 38, 255)


def c(hex_str, a=255):
    h = hex_str.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def add_outline(img, color=OUTLINE):
    """SNES-style 1px dark outline around every opaque pixel."""
    w, h = img.size
    src = img.copy().load()
    px = img.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                    px[x, y] = color
                    break
    return img


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, os.path.join(ROOT, "..")))


# ---------------------------------------------------------------------------
# Terrain atlas: 10 cells of 40x20. The 32x16 iso diamond sits at offset (4,2).
#   0-3 grass, 4-5 grass with flowers, 6-7 dirt, 8-9 water
# Grass is a full diamond; dirt/water are slightly larger with ragged edges so
# they blend into the grass drawn underneath (no visible grid).
# ---------------------------------------------------------------------------
CELL_W, CELL_H = 40, 20
GRASS = [c("3f7d2b"), c("4e9632"), c("5fad3b"), c("7cc84a")]
DIRT = [c("6b4f2c"), c("86653a"), c("9e7c4a"), c("b8955e")]
WATER = [c("23548a"), c("2d68a6"), c("3a7fc0"), c("9fd2ee")]
ROCK = [c("54504c"), c("6c6862"), c("85807a"), c("a29c94")]
CAVE = [c("3e3640"), c("4c4450"), c("5a5060"), c("766a78")]
CAVE_WALL = [c("0c0a10"), c("15111a"), c("1e1924"), c("2a2332")]


def in_diamond(x, y):
    """Pixel-exact 32x16 diamond (with 1px bleed) in cell coordinates."""
    lx, ly = x - 4, y - 2
    if not 0 <= ly < 16:
        return False
    half = (ly + 1) * 2 if ly < 8 else (16 - ly) * 2
    return 16 - half - 1 <= lx < 16 + half + 1


def ragged(x, y, rng, grow=1.18):
    dx = abs(x + 0.5 - 20) / (16 * grow)
    dy = abs(y + 0.5 - 10) / (8 * grow)
    return dx + dy < 0.9 + rng.random() * 0.12


def blobs(px, mask, rng, color, count, size):
    for _ in range(count):
        bx, by = rng.randrange(CELL_W), rng.randrange(CELL_H)
        for _ in range(size):
            if mask(bx, by):
                px[bx, by] = color
            bx += rng.choice((-1, 0, 1))
            by += rng.choice((-1, 0, 0, 1))
            bx, by = max(0, min(CELL_W - 1, bx)), max(0, min(CELL_H - 1, by))


def stone_tile(rng, pal):
    """Opaque diamond like grass, but rocky (mountain) or dark (cave floor)."""
    img = Image.new("RGBA", (CELL_W, CELL_H))
    px = img.load()
    m = in_diamond
    for y in range(CELL_H):
        for x in range(CELL_W):
            if m(x, y):
                px[x, y] = pal[1]
    blobs(px, m, rng, pal[0], 7, 6)
    blobs(px, m, rng, pal[2], 6, 5)
    for _ in range(5):
        x, y = rng.randrange(6, 34), rng.randrange(3, 16)
        if m(x, y) and m(x + 1, y):
            px[x, y] = pal[3]
            px[x + 1, y] = pal[2]
    return img


def grass_tile(rng, flowers=False):
    img = Image.new("RGBA", (CELL_W, CELL_H))
    px = img.load()
    m = in_diamond
    for y in range(CELL_H):
        for x in range(CELL_W):
            if m(x, y):
                px[x, y] = GRASS[1]
    blobs(px, m, rng, GRASS[0], 6, 5)
    blobs(px, m, rng, GRASS[2], 6, 5)
    # grass tufts: light blade with dark root
    for _ in range(7):
        x, y = rng.randrange(6, 34), rng.randrange(3, 17)
        if m(x, y) and m(x, y + 1):
            px[x, y] = GRASS[3]
            px[x, y + 1] = GRASS[0]
    if flowers:
        for _ in range(3):
            x, y = rng.randrange(8, 32), rng.randrange(4, 15)
            col = rng.choice([c("f4f0e0"), c("f2d64b"), c("e98ab8")])
            if m(x, y):
                px[x, y] = col
                if m(x, y + 1):
                    px[x, y + 1] = GRASS[0]
    return img


def overlay_tile(rng, pal, kind):
    img = Image.new("RGBA", (CELL_W, CELL_H))
    px = img.load()
    mask = {}
    for y in range(CELL_H):
        for x in range(CELL_W):
            mask[(x, y)] = ragged(x, y, rng)
    m = lambda x, y: mask.get((x, y), False)
    for (x, y), inside in mask.items():
        if inside:
            px[x, y] = pal[1]
    blobs(px, m, rng, pal[0], 5, 6)
    blobs(px, m, rng, pal[2], 5, 6)
    if kind == "dirt":  # pebbles
        for _ in range(4):
            x, y = rng.randrange(8, 32), rng.randrange(4, 16)
            if m(x, y):
                px[x, y] = pal[3]
                if m(x + 1, y + 1):
                    px[x + 1, y + 1] = pal[0]
    else:  # water glints: short horizontal streaks
        for _ in range(3):
            x, y = rng.randrange(8, 28), rng.randrange(4, 16)
            for i in range(rng.randrange(2, 5)):
                if m(x + i, y):
                    px[x + i, y] = pal[3]
    return img


def make_terrain():
    rng = random.Random(7)
    atlas = Image.new("RGBA", (CELL_W * 16, CELL_H))
    tiles = [grass_tile(rng) for _ in range(4)]
    tiles += [grass_tile(rng, flowers=True) for _ in range(2)]
    tiles += [overlay_tile(rng, DIRT, "dirt") for _ in range(2)]
    tiles += [overlay_tile(rng, WATER, "water") for _ in range(2)]
    tiles += [stone_tile(rng, ROCK) for _ in range(2)]
    tiles += [stone_tile(rng, CAVE) for _ in range(2)]
    tiles += [stone_tile(rng, CAVE_WALL) for _ in range(2)]
    for i, t in enumerate(tiles):
        atlas.paste(t, (i * CELL_W, 0))
    save(atlas, "tiles", "terrain.png")


# ---------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------
def shadow(img, cx, cy, rx, ry):
    """Soft drop shadow drawn AFTER outlining (so it is not outlined)."""
    sh = Image.new("RGBA", img.size)
    ImageDraw.Draw(sh).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(0, 0, 0, 70))
    return Image.alpha_composite(sh, img)


def make_tree():
    img = Image.new("RGBA", (34, 46))
    d = ImageDraw.Draw(img)
    # trunk
    d.rectangle((14, 28, 19, 42), fill=c("6b4423"))
    d.rectangle((18, 28, 19, 42), fill=c("4e3018"))
    d.rectangle((14, 28, 14, 42), fill=c("8a5a30"))
    d.rectangle((12, 41, 21, 42), fill=c("6b4423"))
    # canopy: dark base, mid, light (lit from top-left)
    for (x, y, r) in [(17, 16, 13), (8, 21, 7), (26, 21, 7), (17, 25, 8)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c("2a5e26"))
    for (x, y, r) in [(15, 14, 10), (8, 19, 5), (24, 18, 6)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c("3c8530"))
    for (x, y, r) in [(13, 11, 5), (21, 13, 3), (8, 17, 2)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c("58a83c"))
    px = img.load()
    rng = random.Random(3)
    for _ in range(14):
        x, y = rng.randrange(6, 28), rng.randrange(4, 28)
        if px[x, y][3]:
            px[x, y] = c("7cc84a") if y < 16 else c("1f4a1d")
    add_outline(img)
    save(shadow(img, 17, 42, 10, 3), "sprites", "tree.png")


def make_bush():
    img = Image.new("RGBA", (20, 16))
    d = ImageDraw.Draw(img)
    for (x, y, r) in [(7, 9, 5), (13, 9, 5), (10, 6, 5)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c("2f6a28"))
    for (x, y, r) in [(9, 6, 3), (13, 8, 2)]:
        d.ellipse((x - r, y - r, x + r, y + r), fill=c("4a9a36"))
    px = img.load()
    for (x, y) in [(6, 9), (12, 11), (14, 6), (9, 11)]:
        px[x, y] = c("d8384a")
        px[x, y - 1] = c("f58a96")
    add_outline(img)
    save(shadow(img, 10, 14, 7, 2), "sprites", "bush.png")


def make_rock():
    img = Image.new("RGBA", (18, 14))
    d = ImageDraw.Draw(img)
    d.ellipse((1, 2, 16, 12), fill=c("6e6e7c"))
    d.ellipse((2, 2, 13, 9), fill=c("8e8e9c"))
    d.ellipse((4, 3, 9, 6), fill=c("b4b4c2"))
    d.line((10, 8, 13, 10), fill=c("55555f"))
    add_outline(img)
    save(shadow(img, 9, 12, 7, 2), "sprites", "rock.png")


def make_crate():
    """Isometric wooden block that exactly fills one tile (35x35)."""
    img = Image.new("RGBA", (35, 35))
    d = ImageDraw.Draw(img)
    d.polygon([(1, 9), (17, 17), (17, 33), (1, 25)], fill=c("9c7444"))
    d.polygon([(17, 17), (33, 9), (33, 25), (17, 33)], fill=c("7a5634"))
    d.polygon([(17, 1), (33, 9), (17, 17), (1, 9)], fill=c("c8a064"))
    # plank lines
    for i in (1, 2, 3):
        y = 9 + i * 4
        d.line((1, y, 17, y + 8), fill=c("7e5a34"))
        d.line((17, y + 8, 33, y), fill=c("5e4026"))
    d.line((9, 5, 25, 13), fill=c("a88450"))
    add_outline(img)
    save(img, "sprites", "crate.png")


def make_stick():
    img = Image.new("RGBA", (16, 5))
    d = ImageDraw.Draw(img)
    d.line((1, 2, 14, 2), fill=c("8a5a30"))
    d.line((1, 1, 13, 1), fill=c("b07a44"))
    d.line((1, 3, 3, 3), fill=c("5e3a1c"))
    add_outline(img)
    save(img, "sprites", "stick.png")


# ---------------------------------------------------------------------------
# Player: 4x4 sheet of 18x26 frames.
#   rows: 0 down, 1 up, 2 left, 3 right      cols: walk frames 0..3
#   feet at (9, 24) inside each frame
# ---------------------------------------------------------------------------
HAIR, HAIR_L, HAIR_D = c("8a4f24"), c("b56e34"), c("5e3416")
SKIN, SKIN_D, EYE = c("f2c29a"), c("d0956c"), c("2a1a2e")
TUN, TUN_L, TUN_D = c("2f8f7a"), c("4cb59a"), c("1f6656")
BELT, PANTS, PANTS_D, BOOT = c("5a3a1a"), c("c9a46a"), c("9c7a48"), c("4a2c1a")
FW, FH = 18, 26


def draw_frame(direction, f):
    img = Image.new("RGBA", (FW, FH))
    px = img.load()

    def r(x0, y0, x1, y1, col):  # inclusive rect, +1 padding for the outline
        for yy in range(y0, y1 + 1):
            for xx in range(x0, x1 + 1):
                px[xx + 1, yy + 1] = col

    bob = 1 if f in (1, 3) else 0
    side = direction in ("left", "right")

    # legs
    if not side:
        lift_l = 1 if f == 1 else 0
        lift_r = 1 if f == 3 else 0
        r(5, 18 - lift_l, 7, 21 - lift_l, PANTS)
        r(5, 22 - lift_l, 7, 22, BOOT)
        r(8, 18 - lift_r, 10, 21 - lift_r, PANTS_D)
        r(8, 22 - lift_r, 10, 22, BOOT)
    else:
        if f in (0, 2):
            r(7, 18, 9, 21, PANTS_D)
            r(6, 18, 8, 21, PANTS)
            r(5, 22, 9, 22, BOOT)
        else:
            front, back = ((3, 5), (9, 11)) if f == 1 else ((9, 11), (3, 5))
            r(back[0], 18, back[1], 21, PANTS_D)
            r(back[0] - 1, 22, back[1], 22, BOOT)
            r(front[0], 18, front[1], 21, PANTS)
            r(front[0] - 1, 22, front[1], 22, BOOT)

    b = bob  # upper body sinks 1px on step frames
    if not side:
        # torso + arms
        r(4, 11 + b, 11, 17, TUN)
        r(4, 11 + b, 4, 17, TUN_L)
        r(11, 11 + b, 11, 17, TUN_D)
        r(4, 16, 11, 16, BELT)
        arm_l = 1 if f == 3 else 0
        arm_r = 1 if f == 1 else 0
        r(3, 11 + b, 3, 14 + b + arm_l, TUN_L)
        r(3, 15 + b + arm_l, 3, 16 + b + arm_l, SKIN)
        r(12, 11 + b, 12, 14 + b + arm_r, TUN_D)
        r(12, 15 + b + arm_r, 12, 16 + b + arm_r, SKIN_D)
        # head
        r(5, 1 + b, 10, 1 + b, HAIR)
        r(4, 2 + b, 11, 5 + b, HAIR)
        r(6, 2 + b, 8, 2 + b, HAIR_L)
        if direction == "down":
            r(5, 5 + b, 10, 9 + b, SKIN)
            r(6, 10 + b, 9, 10 + b, SKIN)
            r(10, 6 + b, 10, 9 + b, SKIN_D)
            r(4, 5 + b, 4, 8 + b, HAIR)
            r(11, 5 + b, 11, 8 + b, HAIR_D)
            r(5, 5 + b, 10, 5 + b, HAIR)  # fringe
            r(7, 5 + b, 7, 5 + b, SKIN)
            px[6 + 1, 7 + b + 1] = EYE
            px[9 + 1, 7 + b + 1] = EYE
        else:  # up: back of the head
            r(4, 5 + b, 11, 8 + b, HAIR)
            r(5, 9 + b, 10, 9 + b, HAIR_D)
            r(6, 10 + b, 9, 10 + b, SKIN_D)
            r(5, 3 + b, 7, 4 + b, HAIR_L)
    else:
        # torso, facing left (right is mirrored later)
        r(5, 11 + b, 10, 17, TUN)
        r(10, 11 + b, 10, 17, TUN_D)
        r(5, 11 + b, 5, 17, TUN_L)
        r(5, 16, 10, 16, BELT)
        # head
        r(5, 1 + b, 10, 1 + b, HAIR)
        r(4, 2 + b, 11, 5 + b, HAIR)
        r(6, 2 + b, 8, 2 + b, HAIR_L)
        r(4, 5 + b, 8, 9 + b, SKIN)
        r(5, 10 + b, 8, 10 + b, SKIN)
        r(3, 7 + b, 3, 7 + b, SKIN)  # nose
        r(9, 5 + b, 11, 9 + b, HAIR)
        r(10, 6 + b, 11, 9 + b, HAIR_D)
        r(4, 5 + b, 6, 5 + b, HAIR)  # fringe
        px[5 + 1, 7 + b + 1] = EYE
        # front arm swings
        ax = {0: 7, 1: 5, 2: 7, 3: 9}[f]
        r(ax, 11 + b, ax + 1, 14 + b, TUN_L)
        r(ax, 15 + b, ax + 1, 16 + b, SKIN)

    add_outline(img)
    if direction == "right":
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


def make_player():
    sheet = Image.new("RGBA", (FW * 4, FH * 4))
    for row, direction in enumerate(("down", "up", "left", "right")):
        for f in range(4):
            src = "left" if direction == "right" else direction
            frame = draw_frame(src, f)
            if direction == "right":
                frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
            sheet.paste(frame, (f * FW, row * FH))
    save(sheet, "sprites", "player.png")


# ---------------------------------------------------------------------------
# Item / spell icons (16x16, outlined)       assets/icons/<id>.png
# ---------------------------------------------------------------------------
def icon():
    return Image.new("RGBA", (16, 16))


def flask(liquid, light):
    img = icon()
    d = ImageDraw.Draw(img)
    d.rectangle((6, 3, 9, 6), fill=c("c8d8e8"))
    d.rectangle((6, 2, 9, 2), fill=c("8a5a30"))
    d.ellipse((3, 6, 12, 14), fill=c("c8d8e8"))
    d.ellipse((4, 8, 11, 13), fill=liquid)
    d.point([(5, 9), (5, 10), (6, 8)], fill=light)
    return add_outline(img)


def make_icons():
    # stick
    img = icon(); d = ImageDraw.Draw(img)
    d.line((3, 13, 12, 3), fill=c("8a5a30"), width=2)
    d.line((3, 12, 11, 3), fill=c("b07a44"))
    save(add_outline(img), "icons", "stick.png")
    # spellbook
    img = icon(); d = ImageDraw.Draw(img)
    d.rectangle((3, 2, 12, 13), fill=c("5a2e8a"))
    d.rectangle((11, 3, 12, 12), fill=c("f0ead8"))
    d.rectangle((3, 2, 4, 13), fill=c("3a1a5e"))
    d.point([(8, 5), (7, 6), (8, 6), (9, 6), (8, 7), (6, 7), (10, 7), (8, 8)], fill=c("f2d64b"))
    save(add_outline(img), "icons", "spellbook.png")
    save(flask(c("d89a28"), c("f8d878")), "icons", "oil.png")
    save(flask(c("3a7fc0"), c("a8d8f0")), "icons", "water.png")
    # ash
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((2, 8, 13, 14), fill=c("6e6e72"))
    d.ellipse((4, 6, 11, 12), fill=c("9a9a9e"))
    d.point([(6, 8), (9, 10), (5, 11), (10, 8)], fill=c("3e3e42"))
    d.point([(7, 7)], fill=c("d0d0d4"))
    save(add_outline(img), "icons", "ash.png")
    # coin
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((3, 3, 12, 12), fill=c("c8901c"))
    d.ellipse((4, 4, 11, 11), fill=c("f2c94a"))
    d.rectangle((7, 6, 8, 9), fill=c("c8901c"))
    d.point([(5, 5), (6, 5)], fill=c("fff2b0"))
    save(add_outline(img), "icons", "coin.png")
    # spells
    img = icon(); d = ImageDraw.Draw(img)
    d.polygon([(2, 13), (7, 6), (5, 11)], fill=c("e05a1c"))
    d.ellipse((5, 3, 13, 11), fill=c("d8381c"))
    d.ellipse((6, 4, 12, 10), fill=c("f08a28"))
    d.ellipse((8, 5, 11, 8), fill=c("f8e070"))
    save(add_outline(img), "icons", "fireball.png")
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((3, 3, 12, 12), fill=c("5e4026"))
    d.ellipse((4, 4, 10, 10), fill=c("86603a"))
    d.point([(6, 6), (7, 9), (9, 7)], fill=c("3e2a18"))
    d.point([(5, 5)], fill=c("b08a5a"))
    d.rectangle((8, 12, 8, 14), fill=c("5e4026"))
    save(add_outline(img), "icons", "mudball.png")
    img = icon(); d = ImageDraw.Draw(img)
    d.rounded_rectangle((3, 4, 12, 13), radius=2, fill=c("9a6ae0"))
    for x in (5, 7, 9, 11):
        d.line((x, 4, x, 7), fill=c("6a3ab0"))
    d.rectangle((2, 8, 4, 11), fill=c("b48af0"))
    d.point([(5, 9), (6, 10), (9, 10)], fill=c("d8c0ff"))
    save(add_outline(img), "icons", "fiststamp.png")


def make_slime(name, base, light, shine, eye, extra=None):
    """2 frames of 18x16, feet at (9, 14)."""
    sheet = Image.new("RGBA", (36, 16))
    for f, box in enumerate([(2, 5, 15, 14), (1, 7, 16, 14)]):
        img = Image.new("RGBA", (18, 16))
        d = ImageDraw.Draw(img)
        d.ellipse(box, fill=base)
        d.ellipse((box[0] + 1, box[1], box[2] - 3, box[3] - 3), fill=light)
        d.point([(box[0] + 3, box[1] + 2), (box[0] + 4, box[1] + 2)], fill=shine)
        ey = box[1] + 4
        d.point([(7, ey), (11, ey), (7, ey + 1), (11, ey + 1)], fill=eye)
        if extra:
            extra(d, box, f)
        add_outline(img)
        sheet.paste(img, (f * 18, 0))
    save(sheet, "sprites", name + ".png")


def make_slimes():
    # Oil slime: dark amber with a glossy sheen
    make_slime("slime_oil", c("8a5a14"), c("c8861e"), c("ffe8a0"), c("1a1208"),
               lambda d, b, f: d.point([(b[2] - 4, b[3] - 3), (b[2] - 5, b[3] - 2)], fill=c("5a3a0c")))

    # Ash slime: grey with glowing ember spots and a smoke wisp
    def embers(d, b, f):
        d.point([(b[0] + 3, b[3] - 3), (b[2] - 3, b[3] - 4), (9, b[3] - 2)], fill=c("f06a1c"))
        d.point([(10 + f, b[1] - 2), (11, b[1] - 3 + f)], fill=c("b8b8bc"))
    make_slime("slime_ash", c("4e4e56"), c("7a7a84"), c("c8c8d0"), c("f8a030"), embers)

    # Water slime: blue with bubbles inside
    def bubbles(d, b, f):
        d.ellipse((b[2] - 6, b[3] - 5, b[2] - 4, b[3] - 3), outline=c("c8ecff"))
        d.point([(b[0] + 4, b[3] - 3)], fill=c("c8ecff"))
    make_slime("slime_water", c("2a6ab8"), c("4a9ae0"), c("e0f6ff"), c("0c1a3a"), bubbles)


def make_projectiles():
    img = Image.new("RGBA", (12, 12)); d = ImageDraw.Draw(img)
    d.ellipse((1, 1, 10, 10), fill=c("d8381c"))
    d.ellipse((2, 2, 8, 8), fill=c("f08a28"))
    d.ellipse((3, 3, 6, 6), fill=c("f8e070"))
    save(img, "sprites", "fireball_proj.png")
    img = Image.new("RGBA", (10, 10)); d = ImageDraw.Draw(img)
    d.ellipse((1, 1, 8, 8), fill=c("5e4026"))
    d.ellipse((2, 2, 6, 6), fill=c("86603a"))
    d.point([(3, 3)], fill=c("b08a5a"))
    save(add_outline(img), "sprites", "mudball_proj.png")


def make_faces():
    """16x16 HUD portraits: normal and hurt (HP <= 3)."""
    for name, hurt in (("face", False), ("face_hurt", True)):
        img = icon(); d = ImageDraw.Draw(img)
        d.rectangle((3, 4, 12, 13), fill=SKIN)
        d.rectangle((12, 6, 12, 12), fill=SKIN_D)
        d.rectangle((4, 13, 11, 14), fill=SKIN)
        d.rectangle((3, 1, 12, 4), fill=HAIR)
        d.rectangle((2, 3, 3, 9), fill=HAIR)
        d.rectangle((12, 3, 13, 8), fill=HAIR_D)
        d.rectangle((5, 1, 8, 1), fill=HAIR_L)
        d.point([(4, 5), (6, 5), (9, 5), (11, 5)], fill=HAIR)
        if hurt:
            for (x, y) in ((5, 7), (9, 7)):
                d.point([(x, y), (x + 1, y + 1), (x + 1, y), (x, y + 1)], fill=EYE)
            d.line((6, 11, 9, 11), fill=EYE)
            d.point([(6, 12), (9, 12)], fill=EYE)
            d.point([(12, 3), (12, 4)], fill=c("8ad0f0"))  # sweat drop
        else:
            d.rectangle((5, 7, 5, 8), fill=EYE)
            d.rectangle((10, 7, 10, 8), fill=EYE)
            d.line((6, 11, 9, 11), fill=c("b0604a"))
            d.point([(5, 11), (10, 10)], fill=c("b0604a"))
        save(add_outline(img), "icons", name + ".png")


def make_slap():
    """Open magic hand for the Slap Hand upgrade."""
    img = icon(); d = ImageDraw.Draw(img)
    d.rounded_rectangle((4, 6, 12, 14), radius=2, fill=c("9a6ae0"))
    for x in (4, 6, 8, 10):
        d.rectangle((x, 1, x + 1, 7), fill=c("9a6ae0"))
    d.rectangle((1, 7, 4, 9), fill=c("9a6ae0"))
    for x in (5, 7, 9, 11):
        d.point([(x, 2), (x, 3)], fill=c("d8c0ff"))
    add_outline(img)
    save(img, "icons", "slap.png")


def make_upgrade_icons():
    """16x16 icons for the 9 spell upgrades: assets/icons/up_<key>.png"""
    RED, ORANGE, YELLOW = c("d8381c"), c("f08a28"), c("f8e070")
    MUD, MUD_L, MUD_D = c("6e4a2a"), c("9a7046"), c("3e2a18")
    VIO, VIO_L, VIO_D = c("9a6ae0"), c("d8c0ff"), c("6a3ab0")

    def fireball(d, cx, cy, r):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=RED)
        d.ellipse((cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1), fill=ORANGE)
        if r >= 3:
            d.ellipse((cx - r // 2, cy - r // 2, cx, cy), fill=YELLOW)

    # Big Fireball: huge ball with a flame tail and sparkle
    img = icon(); d = ImageDraw.Draw(img)
    d.polygon([(0, 15), (6, 6), (9, 10)], fill=RED)
    fireball(d, 9, 7, 6)
    d.point([(14, 1), (13, 2), (15, 2), (14, 3)], fill=c("fff8d0"))
    save(add_outline(img), "icons", "up_big.png")

    # Triple Fireball: three small balls in a fan
    img = icon(); d = ImageDraw.Draw(img)
    for (x, y) in ((3, 3), (12, 3), (8, 12)):
        fireball(d, x, y, 2)
        d.point([(x, y)], fill=YELLOW)
    save(add_outline(img), "icons", "up_triple.png")

    # Lavaball: glowing lava pool with a falling drop and bubbles
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((1, 9, 14, 15), fill=c("7a1a0c"))
    d.ellipse((2, 10, 13, 14), fill=c("e0501c"))
    d.ellipse((4, 11, 9, 13), fill=c("f8b030"))
    d.point([(11, 11), (6, 12)], fill=c("fff0a0"))
    d.ellipse((6, 1, 10, 6), fill=RED)
    d.ellipse((7, 2, 9, 4), fill=ORANGE)
    d.point([(8, 7)], fill=RED)
    save(add_outline(img), "icons", "up_lava.png")

    # Sticky Puddle: flat mud puddle with ripples
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((0, 7, 15, 15), fill=MUD_D)
    d.ellipse((1, 8, 14, 14), fill=MUD)
    d.ellipse((4, 9, 11, 13), outline=MUD_L)
    d.point([(7, 11), (8, 11)], fill=MUD_L)
    d.ellipse((5, 1, 10, 6), fill=MUD)
    d.point([(6, 2)], fill=MUD_L)
    save(add_outline(img), "icons", "up_puddle.png")

    # Ricochet Mud: mudball with a bouncing dotted arc
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((9, 1, 15, 7), fill=MUD)
    d.point([(10, 2), (11, 2)], fill=MUD_L)
    d.ellipse((1, 11, 5, 15), fill=MUD_D)
    add_outline(img)
    for (x, y) in ((3, 9), (4, 7), (6, 6), (7, 8), (8, 10), (9, 12), (10, 10), (11, 9)):
        img.putpixel((x, y), c("f2e6c8"))  # bounce trail, not outlined
    save(img, "icons", "up_bounce.png")

    # Quicksand: sand swirl pulling something under
    img = icon(); d = ImageDraw.Draw(img)
    d.ellipse((0, 5, 15, 15), fill=c("b8955e"))
    d.ellipse((3, 7, 12, 13), fill=c("9e7c4a"))
    d.ellipse((5, 8, 10, 12), fill=c("86653a"))
    d.ellipse((7, 9, 8, 11), fill=c("5e4026"))
    d.arc((1, 6, 14, 14), 200, 340, fill=c("e0c890"))
    d.ellipse((6, 1, 10, 5), fill=c("5ec04e"))  # a slime sinking in
    d.point([(7, 3), (9, 3)], fill=c("1a2a14"))
    save(add_outline(img), "icons", "up_quicksand.png")

    # Slap Hand: open hand with motion lines
    img = icon(); d = ImageDraw.Draw(img)
    d.rounded_rectangle((6, 6, 14, 14), radius=2, fill=VIO)
    for x in (6, 8, 10, 12):
        d.rectangle((x, 1, x + 1, 7), fill=VIO)
        d.point([(x, 2)], fill=VIO_L)
    d.rectangle((3, 8, 6, 10), fill=VIO)
    for y in (5, 9, 13):
        d.line((0, y, 2, y), fill=c("f2e6c8"))
    save(add_outline(img), "icons", "up_slap.png")

    # Double Fist: two fists, one behind the other
    img = icon(); d = ImageDraw.Draw(img)
    for (ox, oy, col, lines) in ((0, 0, VIO_D, VIO), (6, 6, VIO, VIO_D)):
        d.rounded_rectangle((ox + 1, oy + 1, ox + 9, oy + 8), radius=1, fill=col)
        for x in (3, 5, 7):
            d.line((ox + x, oy + 1, ox + x, oy + 3), fill=lines)
    d.point([(9, 9), (10, 9)], fill=VIO_L)
    save(add_outline(img), "icons", "up_double.png")

    # Fast Fist: fist with speed lines and a ground crack
    img = icon(); d = ImageDraw.Draw(img)
    d.rounded_rectangle((5, 2, 13, 10), radius=2, fill=VIO)
    for x in (7, 9, 11):
        d.line((x, 7, x, 10), fill=VIO_D)
    d.point([(6, 3), (7, 3)], fill=VIO_L)
    for x in (6, 9, 12):
        d.line((x, 0, x, 1), fill=c("f2e6c8"))
    d.line((2, 14, 6, 12), fill=c("5e4026"))
    d.line((6, 12, 9, 15), fill=c("5e4026"))
    d.line((9, 13, 14, 12), fill=c("5e4026"))
    save(add_outline(img), "icons", "up_fast.png")


def make_tools_and_materials():
    WOOD_L, WOOD, WOOD_D = c("b07a44"), c("8a5a30"), c("5e3a1c")
    STEEL_L, STEEL, STEEL_D = c("e0e4ec"), c("a8b0bc"), c("6a7280")
    # inventory icons
    img = icon(); d = ImageDraw.Draw(img)
    d.line((3, 14, 11, 4), fill=WOOD, width=2)
    d.polygon([(8, 2), (13, 1), (15, 5), (12, 8)], fill=STEEL)
    d.line((13, 2, 15, 5), fill=STEEL_L)
    save(add_outline(img), "icons", "axe.png")
    img = icon(); d = ImageDraw.Draw(img)
    d.line((4, 14, 10, 5), fill=WOOD, width=2)
    d.arc((2, 1, 16, 12), 200, 340, fill=STEEL, width=2)
    d.point([(4, 5), (14, 5)], fill=STEEL_D)
    save(add_outline(img), "icons", "pickaxe.png")
    img = icon(); d = ImageDraw.Draw(img)
    for y in (4, 8):
        d.rectangle((2, y, 13, y + 3), fill=WOOD)
        d.line((2, y, 13, y), fill=WOOD_L)
        d.ellipse((11, y, 14, y + 3), fill=c("d8b078"))
        d.point([(12, y + 1)], fill=WOOD_D)
    save(add_outline(img), "icons", "wood.png")
    img = icon(); d = ImageDraw.Draw(img)
    d.polygon([(2, 12), (4, 6), (9, 4), (13, 7), (14, 13), (8, 14)], fill=c("8e8e9c"))
    d.polygon([(4, 7), (9, 5), (10, 9), (5, 10)], fill=c("b4b4c2"))
    d.line((9, 10, 12, 12), fill=c("5e5e6a"))
    save(add_outline(img), "icons", "stone.png")
    # held versions (swing sprites): handle starts at (1, 3), points right
    img = Image.new("RGBA", (18, 9)); d = ImageDraw.Draw(img)
    d.line((1, 4, 15, 4), fill=WOOD); d.line((1, 3, 14, 3), fill=WOOD_L)
    d.polygon([(12, 1), (16, 0), (17, 7), (13, 6)], fill=STEEL)
    d.line((16, 1, 16, 6), fill=STEEL_L)
    save(add_outline(img), "sprites", "axe_held.png")
    img = Image.new("RGBA", (18, 13)); d = ImageDraw.Draw(img)
    d.line((1, 6, 14, 6), fill=WOOD); d.line((1, 5, 13, 5), fill=WOOD_L)
    d.line((14, 1, 14, 11), fill=STEEL, width=2)
    d.point([(13, 1), (13, 11)], fill=STEEL_D)
    save(add_outline(img), "sprites", "pickaxe_held.png")


def make_village():
    # Hut: 2x2 tile footprint (64x32 diamond), walls + thatched pyramid roof.
    W, H, T = 68, 62, 28              # image size, footprint top at y=T
    img = Image.new("RGBA", (W, H)); d = ImageDraw.Draw(img)
    cx = 34
    top, right, bottom, left = (cx, T), (cx + 32, T + 16), (cx, T + 32), (cx - 32, T + 16)
    wall = 18
    up = lambda p, h: (p[0], p[1] - h)
    d.polygon([left, bottom, up(bottom, wall), up(left, wall)], fill=c("8a6a44"))
    d.polygon([bottom, right, up(right, wall), up(bottom, wall)], fill=c("6e5232"))
    for i in range(1, 4):  # planks
        d.line((left[0], left[1] - i * 5, bottom[0], bottom[1] - i * 5), fill=c("6e5232"))
        d.line((bottom[0], bottom[1] - i * 5, right[0], right[1] - i * 5), fill=c("5a4228"))
    # door (left wall) and window (right wall)
    d.polygon([(cx - 18, T + 25), (cx - 10, T + 29), (cx - 10, T + 16), (cx - 18, T + 12)], fill=c("3e2a18"))
    d.polygon([(cx + 12, T + 20), (cx + 20, T + 16), (cx + 20, T + 9), (cx + 12, T + 13)], fill=c("f8d070"))
    d.line((cx + 16, T + 11, cx + 16, T + 18), fill=c("5a4228"))
    # roof
    e = 3
    l2, b2, r2 = (left[0] - e, left[1] - wall), (bottom[0], bottom[1] - wall + e), (right[0] + e, right[1] - wall)
    apex = (cx, T + 16 - wall - 24)
    d.polygon([l2, b2, apex], fill=c("d4aa58"))
    d.polygon([b2, r2, apex], fill=c("a87e3a"))
    for i in range(1, 5):  # thatch lines
        k = i / 5
        d.line((l2[0] + (apex[0] - l2[0]) * k, l2[1] + (apex[1] - l2[1]) * k,
                b2[0] + (apex[0] - b2[0]) * k, b2[1] + (apex[1] - b2[1]) * k), fill=c("b08a44"))
        d.line((b2[0] + (apex[0] - b2[0]) * k, b2[1] + (apex[1] - b2[1]) * k,
                r2[0] + (apex[0] - r2[0]) * k, r2[1] + (apex[1] - r2[1]) * k), fill=c("8a6430"))
    add_outline(img)
    save(shadow(img, cx, T + 18, 30, 14), "sprites", "hut.png")

    # Fireplace: stone ring with logs and 3 animated flame frames (24x28 each)
    sheet = Image.new("RGBA", (72, 28))
    rng = random.Random(5)
    for f in range(3):
        img = Image.new("RGBA", (24, 28)); d = ImageDraw.Draw(img)
        d.ellipse((2, 17, 21, 26), fill=c("3a2a20"))
        d.line((5, 22, 18, 19), fill=c("6b4423"), width=2)
        d.line((5, 19, 18, 23), fill=c("8a5a30"), width=2)
        for a in range(10):
            import math
            ang = a / 10 * math.tau
            x, y = 12 + math.cos(ang) * 9, 21.5 + math.sin(ang) * 4.5
            d.ellipse((x - 2, y - 1.5, x + 2, y + 1.5), fill=c("8e8e9c") if a % 2 else c("a8a8b4"))
        sway = (-1, 0, 1)[f]
        d.polygon([(7, 20), (12 + sway, 4 + f), (17, 20)], fill=c("e0501c"))
        d.polygon([(9, 20), (12 - sway, 9 + f % 2), (15, 20)], fill=c("f8a030"))
        d.polygon([(10, 20), (12 + sway, 13), (14, 20)], fill=c("f8e070"))
        add_outline(img)
        for _ in range(2):  # sparks
            img.putpixel((rng.randrange(6, 18), rng.randrange(0, 8)), c("f8e070"))
        sheet.paste(img, (f * 24, 0))
    save(sheet, "sprites", "fireplace.png")


def make_mountain():
    """Mountain decoration (peaks, boulders) and cave mouths."""
    import math
    def peak(w, h, snow, name, seed):
        rng = random.Random(seed)
        img = Image.new("RGBA", (w, h)); d = ImageDraw.Draw(img)
        cx, base = w // 2, h - 4
        apex = (cx + rng.randint(-3, 3), 2)
        left, right, front = (2, base - 6), (w - 3, base - 6), (cx, base)
        d.polygon([left, front, apex], fill=c("8a847c"))
        d.polygon([front, right, apex], fill=c("5e5a54"))
        for _ in range(8):  # cracks / ledges, only inside the rock
            y = rng.randint(apex[1] + 6, base - 6)
            x = rng.randint(6, w - 7)
            x2 = x + rng.randint(3, 7)
            if img.getpixel((x, y))[3] and img.getpixel((min(x2, w - 1), min(y + 2, h - 1)))[3]:
                d.line((x, y, x2, y + 2), fill=c("4a4640"))
        if snow:
            sh = h // 3
            d.polygon([(apex[0] - sh // 2, apex[1] + sh), (apex[0], apex[1]), (apex[0] + sh // 2, apex[1] + sh),
                       (apex[0] + 2, apex[1] + sh - 3), (apex[0] - 3, apex[1] + sh - 2)], fill=c("eef2f8"))
        add_outline(img)
        save(shadow(img, cx, base - 2, w // 2 - 4, 4), "sprites", name)
    peak(72, 70, True, "peak_big.png", 1)
    peak(50, 48, False, "peak.png", 2)
    peak(32, 28, False, "boulder.png", 3)

    for name, inner in (("cave_mouth.png", c("0c0810")), ("cave_exit.png", c("f8e8b0"))):
        img = Image.new("RGBA", (40, 34)); d = ImageDraw.Draw(img)
        d.polygon([(2, 31), (6, 10), (14, 3), (26, 3), (34, 10), (38, 31)], fill=c("6c6862"))
        d.polygon([(2, 31), (6, 10), (14, 3), (20, 3), (20, 31)], fill=c("85807a"))
        d.ellipse((9, 9, 31, 40), fill=inner)
        if name == "cave_exit.png":
            d.ellipse((13, 14, 27, 40), fill=c("fffbe8"))
        add_outline(img)
        img = img.crop((0, 0, 40, 33))
        save(img, "sprites", name)


def make_boss():
    """Hive Mantis: body, claw cage (closed / open), heart (2 frames)."""
    CH, CH_L, CH_D = c("4a2a5e"), c("6e3e8a"), c("2a163a")
    STRIPE, EYE = c("8a5aa8"), c("f03a2a")
    BONE, BONE_D = c("e0d4b0"), c("8a7a5a")
    W, H = 128, 100
    img = Image.new("RGBA", (W, H)); d = ImageDraw.Draw(img)
    cx = W // 2
    # legs (behind)
    for side in (-1, 1):
        for i, (kx, ky, fx) in enumerate(((30, 50, 46), (34, 62, 52), (28, 74, 44))):
            knee = (cx + side * kx, ky - 8)
            foot = (cx + side * fx, ky + 18)
            d.line((cx + side * 12, ky, knee[0], knee[1]), fill=CH_D, width=3)
            d.line((knee[0], knee[1], foot[0], foot[1]), fill=CH_D, width=2)
    # abdomen (behind, higher)
    d.ellipse((cx - 30, 4, cx + 30, 52), fill=CH)
    for y in (14, 24, 34, 44):
        d.arc((cx - 30, y - 18, cx + 30, y + 10), 20, 160, fill=STRIPE, width=2)
    d.ellipse((cx - 20, 8, cx - 4, 22), fill=CH_L)
    # thorax
    d.ellipse((cx - 24, 34, cx + 24, 86), fill=CH)
    d.ellipse((cx - 20, 38, cx + 4, 60), fill=CH_L)
    d.ellipse((cx - 10, 50, cx + 10, 72), fill=c("1a0c22"))  # heart cavity
    # head
    d.polygon([(cx - 16, 34), (cx + 16, 34), (cx, 54)], fill=CH)
    d.polygon([(cx - 16, 34), (cx, 34), (cx, 54)], fill=CH_L)
    d.ellipse((cx - 17, 28, cx - 7, 38), fill=EYE)
    d.ellipse((cx + 7, 28, cx + 17, 38), fill=EYE)
    d.point([(cx - 14, 30), (cx + 10, 30)], fill=c("ffd0c0"))
    d.line((cx - 4, 52, cx - 7, 58), fill=BONE, width=2)
    d.line((cx + 4, 52, cx + 7, 58), fill=BONE, width=2)
    # antennae
    d.line((cx - 6, 30, cx - 24, 2), fill=CH_D, width=1)
    d.line((cx + 6, 30, cx + 24, 2), fill=CH_D, width=1)
    add_outline(img)
    save(shadow(img, cx, 90, 50, 8), "sprites", "boss_body.png")

    # claw cage, closed: two scythe claws crossing over the heart (center 32,26)
    img = Image.new("RGBA", (64, 52)); d = ImageDraw.Draw(img)
    for side in (-1, 1):
        x0 = 32 + side * 26
        d.line((x0, 4, 32 + side * 20, 20), fill=CH, width=5)              # upper arm
        d.arc((32 - 22 if side > 0 else 32 - 4, 8, 32 + 4 if side > 0 else 32 + 22, 48),
              90 if side > 0 else 270, 270 if side > 0 else 90, fill=BONE, width=4)
        for k in range(4):  # spikes pointing inward
            y = 16 + k * 8
            d.line((32 + side * 12, y, 32 + side * 4, y + 3), fill=BONE_D, width=2)
    d.line((14, 28, 50, 28), fill=BONE, width=2)
    d.line((18, 38, 46, 38), fill=BONE, width=2)
    add_outline(img)
    save(img, "sprites", "boss_cage.png")

    # claw cage, open: claws pulled wide apart
    img = Image.new("RGBA", (112, 52)); d = ImageDraw.Draw(img)
    for side in (-1, 1):
        sx = 56 + side * 30
        d.line((56 + side * 16, 10, sx, 4), fill=CH, width=5)
        d.arc((sx - 14, 2, sx + 14, 46), 300 if side > 0 else 120, 60 if side > 0 else 240, fill=BONE, width=4)
        for k in range(3):
            y = 14 + k * 9
            d.line((sx + side * 10, y, sx + side * 16, y + 3), fill=BONE_D, width=2)
    add_outline(img)
    save(img, "sprites", "boss_cage_open.png")

    # heart: 2 frames of 20x20
    sheet = Image.new("RGBA", (40, 20))
    for f, r in enumerate((7, 8)):
        img = Image.new("RGBA", (20, 20)); d = ImageDraw.Draw(img)
        d.ellipse((10 - r, 10 - r, 10 + r, 10 + r), fill=c("b0142a"))
        d.ellipse((10 - r + 2, 10 - r + 2, 10 + r - 3, 10 + r - 3), fill=c("e8304a"))
        d.ellipse((6, 5, 9, 8), fill=c("ffa0b0"))
        d.line((10, 3, 12, 14), fill=c("7a0a1a"))
        d.line((5, 10, 15, 12), fill=c("7a0a1a"))
        add_outline(img)
        sheet.paste(img, (f * 20, 0))
    save(sheet, "sprites", "boss_heart.png")


def make_big_mountain():
    """One very big front mountain with the cave opening at its base.
    Foot point (cave floor, bottom centre) at (100, 154)."""
    W, H = 200, 164
    rng = random.Random(11)
    img = Image.new("RGBA", (W, H)); d = ImageDraw.Draw(img)
    L, R, D = c("8e877e"), c("605a53"), c("4a4640")
    # side peak (behind, left)
    d.polygon([(4, 132), (48, 34), (86, 120)], fill=c("7a746c"))
    d.polygon([(48, 34), (86, 120), (60, 136)], fill=c("57524c"))
    # main peak
    base_l, base_r, front, apex = (2, 136), (197, 132), (100, 156), (104, 4)
    d.polygon([base_l, apex, front], fill=L)
    d.polygon([apex, base_r, front], fill=R)
    # snow caps
    d.polygon([(104, 4), (84, 44), (92, 40), (98, 48), (104, 40), (112, 50), (120, 42), (128, 46)], fill=c("eef2f8"))
    d.polygon([(104, 4), (128, 46), (120, 42), (112, 50), (104, 40)], fill=c("c8d0dc"))
    d.polygon([(48, 34), (38, 56), (46, 52), (52, 58), (60, 52)], fill=c("eef2f8"))
    # ridges and cracks (inside the rock only)
    for _ in range(26):
        x, y = rng.randint(12, 188), rng.randint(40, 140)
        x2, y2 = x + rng.randint(-8, 8), y + rng.randint(3, 9)
        if img.getpixel((x, y))[3] and img.getpixel((max(0, min(W - 1, x2)), min(H - 1, y2)))[3]:
            d.line((x, y, x2, y2), fill=D)
    d.line((104, 4, 100, 156), fill=c("6e6860"))
    # cave opening with a stone arch frame
    d.ellipse((74, 108, 126, 176), fill=c("5a554e"))
    d.ellipse((80, 114, 120, 176), fill=c("0c0810"))
    for a in range(9):
        import math
        ang = math.pi + a / 8 * math.pi
        x, y = 100 + math.cos(ang) * 24, 142 + math.sin(ang) * 30
        d.ellipse((x - 4, y - 3, x + 4, y + 3), fill=c("9a948a") if a % 2 else c("7a746c"))
    img = img.crop((0, 0, W, 158))
    add_outline(img)
    save(shadow(img, 100, 150, 90, 8), "sprites", "mountain_big.png")


if __name__ == "__main__":
    make_terrain()
    make_tree()
    make_bush()
    make_rock()
    make_crate()
    make_stick()
    make_player()
    make_icons()
    make_slimes()
    make_projectiles()
    make_faces()
    make_slap()
    make_upgrade_icons()
    make_tools_and_materials()
    make_village()
    make_mountain()
    make_big_mountain()
    make_boss()
