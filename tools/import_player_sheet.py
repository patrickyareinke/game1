"""Turn character sprite sheet images into the game's frame sheets:
  tools/player_source.png -> assets/sprites/player_sheet.png  (the hero)
  tools/girl_source.png   -> assets/sprites/girl_sheet.png    (victory scene)

Run:  python tools/import_player_sheet.py      (needs: pip install pillow numpy)

Source layout: 6 rows (idle, walk, run, attack, hurt, sleep), 10 frames per
row: 0-3 facing down, 4-6 facing right, 7-9 facing up (sleep: 8 frames).
The source is drawn about 4x, so frames are scaled down 4x and snapped to a
small palette to get clean pixels again.

Output: 10 columns x 6 rows of 34x34 frames, feet at the bottom centre.
"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "player_source.png")
OUT = os.path.join(HERE, "..", "assets", "sprites", "player_sheet.png")
CELL = 34                      # output frame size
SHEETS = [   # source, output, source pixels per game pixel, x where frames start
    ("player_source.png", "player_sheet.png", 4, 395),
    ("girl_source.png", "girl_sheet.png", 3, 262),
]
COLORS = 40


def foreground(a):
    """Character pixels = everything not connected to the sheet background.
    Background is flood-filled from the corner with a tight colour match, so
    near-black hair inside a sprite outline is kept."""
    from scipy import ndimage
    near_bg = np.abs(a - a[5, 5]).sum(2) <= 16
    lab, _ = ndimage.label(near_bg)
    outside = lab == lab[5, 5]
    fg = ~outside
    fg = ndimage.binary_opening(fg, iterations=1)   # drop stray specks
    return fg


def bands(mask, axis_len, min_len):
    out, start = [], None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if not v and start is not None:
            if i - start > min_len:
                out.append((start, i))
            start = None
    return out


def import_sheet(src_name, out_name, SCALE, LEFT_IGNORE):
    SRC = os.path.join(HERE, src_name)
    OUT = os.path.join(HERE, "..", "assets", "sprites", out_name)
    img = Image.open(SRC).convert("RGB")
    a = np.array(img).astype(int)
    fg = foreground(a)
    fg[:, :LEFT_IGNORE] = False

    rows = bands(fg.sum(1) > 0, a.shape[0], 20)
    assert len(rows) == 6, rows
    frames = []                # (row, col, rgb crop, alpha crop)
    for r, (y0, y1) in enumerate(rows):
        segs = bands(fg[y0:y1].sum(0) > 0, a.shape[1], 8)
        for c, (x0, x1) in enumerate(segs):
            m = fg[y0:y1, x0:x1]
            ys, xs = np.nonzero(m)
            ax = x0 + int(np.median(xs))          # body anchor (robust to punches)
            size = CELL * SCALE
            left, top = ax - size // 2, y1 - size
            box = (left, top, left + size, y1)
            rgb = img.crop(box)
            alpha = Image.fromarray((fg[max(top, 0):y1, :].astype(np.uint8) * 255)).crop(
                (left, 0 if top >= 0 else -top, left + size, size if top >= 0 else size - top))
            # keep only this frame's pixels (neighbours could leak into the box)
            am = np.array(alpha)
            am[:, : max(0, x0 - left)] = 0
            am[:, max(0, x1 - left):] = 0
            frames.append((r, c, rgb, Image.fromarray(am)))

    # downscale: each output pixel = median colour of the character's pixels
    # in its 4x4 block (keeps edges crisp); transparent if mostly background
    small = []
    fg_pixels = []
    for r, c, rgb, al in frames:
        ra = np.array(rgb).astype(int)
        aa = np.array(al) > 0
        out = np.zeros((CELL, CELL, 4), np.uint8)
        for y in range(CELL):
            for x in range(CELL):
                blk = aa[y * SCALE:(y + 1) * SCALE, x * SCALE:(x + 1) * SCALE]
                if blk.sum() >= SCALE * SCALE * 0.44:
                    px = ra[y * SCALE:(y + 1) * SCALE, x * SCALE:(x + 1) * SCALE][blk]
                    col = np.median(px, axis=0)
                    out[y, x] = (*col.astype(np.uint8), 255)
                    fg_pixels.append(col)
        small.append((r, c, out))

    # one shared palette, built from the character's pixels only
    fp = np.array(fg_pixels, np.uint8).reshape(1, -1, 3)
    pal = Image.fromarray(fp, "RGB").quantize(COLORS, method=Image.Quantize.MEDIANCUT)

    sheet = Image.new("RGBA", (CELL * 10, CELL * 6))
    for r, c, out in small:
        rgb = Image.fromarray(out[:, :, :3], "RGB")
        q = rgb.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGBA")
        q.putalpha(Image.fromarray(out[:, :, 3]))
        sheet.paste(q, (c * CELL, r * CELL))
    sheet.save(OUT)
    print("wrote", os.path.relpath(OUT, os.path.join(HERE, "..")), sheet.size, len(small), "frames")


def make_face():
    """HUD portraits (16x16): the head of the first idle frame."""
    sheet = Image.open(OUT).convert("RGBA")
    al = np.array(sheet.crop((0, 0, CELL, CELL)))[:, :, 3]
    top = int(np.nonzero(al.sum(1))[0][0])           # first row with pixels
    face = sheet.crop((CELL // 2 - 8, top, CELL // 2 + 8, top + 16))
    icons = os.path.join(HERE, "..", "assets", "icons")
    face.save(os.path.join(icons, "face.png"))
    hurt = face.copy()
    px = hurt.load()
    for y in range(9, 13):                          # flushed cheeks
        for x in (4, 5, 10, 11):
            r, g, b, a2 = px[x, y]
            if a2:
                px[x, y] = (min(255, r + 50), int(g * 0.75), int(b * 0.75), a2)
    for (x, y) in ((14, 4), (14, 5), (13, 6)):
        px[x, y] = (140, 210, 245, 255)              # sweat drop
    hurt.save(os.path.join(icons, "face_hurt.png"))
    print("wrote assets/icons/face.png, face_hurt.png")


def make_blush():
    """Overlay for the hero's front idle frame: rosy cheeks and a smile.
    Pixel positions match frame 0 of player_sheet.png (eyes on row 10)."""
    img = Image.new("RGBA", (CELL, CELL))
    px = img.load()
    for (x, y) in ((14, 11), (15, 11), (19, 11), (20, 11)):
        px[x, y] = (236, 92, 104, 255)            # cheeks
    for (x, y) in ((13, 11), (21, 11), (14, 10), (20, 10)):
        px[x, y] = (226, 120, 120, 150)           # soft glow around them
    for (x, y) in ((16, 12), (17, 12), (18, 12)):
        px[x, y] = (246, 226, 214, 255)           # smile (teeth)
    for (x, y) in ((15, 12), (19, 12)):
        px[x, y] = (60, 20, 20, 255)              # mouth corners
    px[17, 13] = (60, 20, 20, 255)
    img.save(os.path.join(HERE, "..", "assets", "sprites", "player_blush.png"))
    print("wrote assets/sprites/player_blush.png")


if __name__ == "__main__":
    for args in SHEETS:
        import_sheet(*args)
    make_face()
    make_blush()
