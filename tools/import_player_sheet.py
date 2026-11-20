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
CELL = 34                      # frame size in game pixels
HIRES = 2                      # texture detail per game pixel (drawn at 1/HIRES scale)
OUT_CELL = CELL * HIRES        # frame size in the texture: 68x68
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

    # resample to OUT_CELL with a sharp filter: keeps the drawing's detail and
    # soft shading (closer to the source art than 1 colour per game pixel)
    sheet = Image.new("RGBA", (OUT_CELL * 10, OUT_CELL * 6))
    for r, c, rgb, al in frames:
        frame = rgb.resize((OUT_CELL, OUT_CELL), Image.LANCZOS).convert("RGBA")
        mask = al.resize((OUT_CELL, OUT_CELL), Image.BOX).point(lambda v: 255 if v >= 120 else 0)
        frame.putalpha(mask)
        sheet.paste(frame, (c * OUT_CELL, r * OUT_CELL))
    sheet.save(OUT)
    print("wrote", os.path.relpath(OUT, os.path.join(HERE, "..")), sheet.size, len(frames), "frames")


def make_face():
    """HUD portraits (16x16): the head of the first idle frame."""
    sheet = Image.open(OUT).convert("RGBA")
    al = np.array(sheet.crop((0, 0, OUT_CELL, OUT_CELL)))[:, :, 3]
    top = int(np.nonzero(al.sum(1))[0][0])           # first row with pixels
    face = sheet.crop((OUT_CELL // 2 - 16, top, OUT_CELL // 2 + 16, top + 32))
    icons = os.path.join(HERE, "..", "assets", "icons")
    face.save(os.path.join(icons, "face.png"))
    hurt = face.copy()
    px = hurt.load()
    for y in range(18, 25):                         # flushed cheeks
        for x in (7, 8, 9, 10, 21, 22, 23, 24):
            r, g, b, a2 = px[x, y]
            if a2:
                px[x, y] = (min(255, r + 50), int(g * 0.75), int(b * 0.75), a2)
    for (x, y) in ((27, 7), (27, 8), (26, 9), (27, 9), (28, 9), (26, 10), (27, 10), (28, 10), (27, 11)):
        px[x, y] = (140, 210, 245, 255)              # sweat drop
    hurt.save(os.path.join(icons, "face_hurt.png"))
    print("wrote assets/icons/face.png, face_hurt.png")


def make_blush():
    """Overlay for the hero's front idle frame (hi-res): rosy cheeks, smile.
    Positions are the 34 px frame's (eyes on row 10) times HIRES."""
    from PIL import ImageDraw
    img = Image.new("RGBA", (OUT_CELL, OUT_CELL))
    d = ImageDraw.Draw(img)
    for cx in (14.5 * HIRES, 20.5 * HIRES):
        d.ellipse((cx - 3, 11 * HIRES - 1, cx + 3, 11 * HIRES + 3), fill=(232, 90, 104, 150))
        d.ellipse((cx - 2, 11 * HIRES, cx + 2, 11 * HIRES + 2), fill=(240, 96, 110, 220))
    y = 12 * HIRES + 1
    d.chord((15.5 * HIRES, y - 3, 19.5 * HIRES, y + 4), 0, 180, fill=(246, 230, 220, 255), outline=(70, 24, 24, 255))
    img.save(os.path.join(HERE, "..", "assets", "sprites", "player_blush.png"))
    print("wrote assets/sprites/player_blush.png")


if __name__ == "__main__":
    for args in SHEETS:
        import_sheet(*args)
    make_face()
    make_blush()
