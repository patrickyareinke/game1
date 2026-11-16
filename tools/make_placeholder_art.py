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
    atlas = Image.new("RGBA", (CELL_W * 10, CELL_H))
    tiles = [grass_tile(rng) for _ in range(4)]
    tiles += [grass_tile(rng, flowers=True) for _ in range(2)]
    tiles += [overlay_tile(rng, DIRT, "dirt") for _ in range(2)]
    tiles += [overlay_tile(rng, WATER, "water") for _ in range(2)]
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


if __name__ == "__main__":
    make_terrain()
    make_tree()
    make_bush()
    make_rock()
    make_crate()
    make_stick()
    make_player()
