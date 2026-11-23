#!/usr/bin/env python3
"""Free repairs for animation strips whose generated frames drift away from the character (issue #166).

The generator sometimes turns a character round mid-idle (a face appears on the back of the head), makes a
held item pop in or swap hands, or melts a face from frame to frame. Two repairs, both built from the
character's own approved rotation frame (rot_<dir>.png), so no new art is invented:

  breathe  rebuild an idle strip as a calm breathing loop of the rotation frame: the body above the hips
           sinks one pixel on the middle frames. Used where an idle strip is broken beyond saving.
  bob      keep an idle strip's own frames but let the upper body sink one pixel on the middle frames, built
           from the strip's first frame. Used where most of the idle is fine but the top half is frozen while
           the rest moves (the Reedling facing north-east).
  swell    rebuild an attack strip as the rotation frame swelling up (the wind-up), a short squash as it
           fires, then rest. Used for spitters seen from behind, where the generator opened a mouth in the
           back of the head; the projectile itself is drawn by the game.
  ends     put the rotation frame (the idle face) on an attack strip's first and last frame, so every
           direction starts from and returns to the same face (the Reedling ended some directions with its
           eyes shut and others open).
  lock     keep a walk/idle strip's motion but paste the rotation frame's head/body band (aligned to each
           frame's bob) over every frame, so the face and markings stay the same. Used for simple shapes
           whose legs carry the motion (the Nibbler).

    python3 tools/fix_frames.py               # apply every repair listed in tools/ai_fixes.json
    python3 tools/fix_frames.py breathe velvette idle_north
    python3 tools/fix_frames.py lock nibbler walk_south 0.7
    python3 tools/fix_frames.py bob reedling idle_north-east 0.75
    python3 tools/fix_frames.py swell reedling attack_north

Both repairs rebuild from rot_<dir>.png, so running them again is harmless. git keeps the generated strips
(see docs/AI_AUDIT.md).
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SPRITES = json.load(open(os.path.join(ROOT, "data", "sprites.json")))["sprites"]


def _path(sid, name):
    return os.path.join(ROOT, "assets", "sprites", sid, name + ".png")


def _frame_size(sid):
    return tuple(SPRITES.get(sid, {}).get("size", [44, 44]))


def _rot(sid, name):
    direction = name.split("_", 1)[1]
    return Image.open(_path(sid, "rot_" + direction)).convert("RGBA").crop((0, 0) + _frame_size(sid))


def breathe(sid, name):
    """Rebuilds the strip (same frame count) from the rotation frame with a one-pixel breath."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    n = strip.size[0] // fw
    base = _rot(sid, name)
    feet_y = SPRITES.get(sid, {}).get("feet", [fw // 2, fh - 8])[1]
    top = base.getchannel("A").getbbox()[1]
    hips = top + int((feet_y - top) * 0.62)  # rows above this rise and fall
    low = base.copy()
    upper = base.crop((0, 0, fw, hips))
    low.paste((0, 0, 0, 0), (0, 0, fw, hips + 1))
    low.alpha_composite(upper, (0, 1))
    # 4 frames: rest, rest, sink, sink; longer strips repeat the pattern.
    pattern = [base, base, low, low]
    out = Image.new("RGBA", strip.size, (0, 0, 0, 0))
    for i in range(n):
        out.paste(pattern[i % 4], (i * fw, 0))
    out.save(_path(sid, name))


def bob(sid, name, ratio=0.62, own=False):
    """Frames 3-4 (of each 4) get frame 1's upper body one pixel lower; rows below stay the frame's own.
    Frame 1 is never changed and rows below the cut are never written, so running it again is harmless.
    own: frames 3-4 sink their own upper body instead (keeps a fluttering scarf moving); rebuilt from the
    generated strip in git history's first frame order, so only run it on a fresh strip."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    first = strip.crop((0, 0, fw, fh))
    feet_y = SPRITES.get(sid, {}).get("feet", [fw // 2, fh - 8])[1]
    top = first.getchannel("A").getbbox()[1]
    cut = top + int((feet_y - top) * ratio)
    upper = first.crop((0, 0, fw, cut))
    for i in range(strip.size[0] // fw):
        if i % 4 < 2:
            continue
        frame = strip.crop((i * fw, 0, (i + 1) * fw, fh))
        top_part = frame.crop((0, 0, fw, cut)) if own else upper
        frame.paste((0, 0, 0, 0), (0, 0, fw, cut + 1))
        frame.alpha_composite(top_part, (0, 1))
        strip.paste(frame, (i * fw, 0))
    strip.save(_path(sid, name))


# Extra (width, height) in pixels per frame, cycled over the strip: swell, hold, squash as it fires, rest.
SWELL = [(0, 0), (2, 1), (2, 2), (4, 2), (4, 3), (2, -1), (0, 0), (0, 0)]


def _stretch(im, dw, dh):
    """Grows (or shrinks) an image by repeating (or dropping) interior rows/columns spread evenly, so the
    outline stays one pixel thick instead of doubling at the edges like a plain resize."""
    def pick(n, d):
        inner = list(range(3, n - 3))
        if d == 0 or not inner:
            return list(range(n))
        marks = {inner[(k * len(inner)) // abs(d) + len(inner) // (2 * abs(d))] for k in range(abs(d))}
        idx = []
        for i in range(n):
            if d < 0 and i in marks:
                continue
            idx.append(i)
            if d > 0 and i in marks:
                idx.append(i)
        return idx
    w, h = im.size
    cols, rows = pick(w, dw), pick(h, dh)
    src = im.load()
    out = Image.new("RGBA", (len(cols), len(rows)), (0, 0, 0, 0))
    dst = out.load()
    for y, sy in enumerate(rows):
        for x, sx in enumerate(cols):
            dst[x, y] = src[sx, sy]
    return out


def ends(sid, name):
    """First and last frame become the rotation frame; the frames between are untouched."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    base = _rot(sid, name)
    n = strip.size[0] // fw
    for i in (0, n - 1):
        strip.paste((0, 0, 0, 0), (i * fw, 0, (i + 1) * fw, fh))
        strip.paste(base, (i * fw, 0))
    strip.save(_path(sid, name))


def swell(sid, name):
    """Rebuilds the strip from the rotation frame grown around its feet; frame count stays the same."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    base = _rot(sid, name)
    x0, y0, x1, y1 = base.getchannel("A").getbbox()
    body = base.crop((x0, y0, x1, y1))
    cx = (x0 + x1) / 2.0
    out = Image.new("RGBA", strip.size, (0, 0, 0, 0))
    n = strip.size[0] // fw
    for i in range(n):
        dw, dh = SWELL[i * len(SWELL) // n] if n != len(SWELL) else SWELL[i]
        w, h = body.size[0] + dw, body.size[1] + dh
        grown = _stretch(body, dw, dh)
        out.alpha_composite(grown, (i * fw + int(round(cx - w / 2.0)), y1 - h))
    out.save(_path(sid, name))


def _best_offset(can, frame, rows):
    """(dx, dy) that lines the canonical silhouette's band up with the frame's."""
    ca, fa = can.getchannel("A").load(), frame.getchannel("A").load()
    w, h = can.size
    best = None
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            miss = 0
            for y in range(rows[0], rows[1]):
                for x in range(w):
                    X, Y = x + dx, y + dy
                    f = fa[X, Y] if 0 <= X < w and 0 <= Y < h else 0
                    if (ca[x, y] > 0) != (f > 0):
                        miss += 1
            if best is None or miss < best[0]:
                best = (miss, dx, dy)
    return best[1], best[2]


def lock(sid, name, band=0.7):
    """Pastes the rotation frame's top band (face, markings) over every frame at its best alignment."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    can = _rot(sid, name)
    bb = can.getchannel("A").getbbox()
    rows = (bb[1], bb[1] + int((bb[3] - bb[1]) * band))
    cp = can.load()
    for i in range(strip.size[0] // fw):
        frame = strip.crop((i * fw, 0, (i + 1) * fw, fh))
        dx, dy = _best_offset(can, frame, rows)
        fp = frame.load()
        for y in range(rows[0], rows[1]):
            for x in range(fw):
                X, Y = x + dx, y + dy
                if cp[x, y][3] and 0 <= X < fw and 0 <= Y < fh:
                    fp[X, Y] = cp[x, y]
        # Anything of the old frame left above the band's outline is the drifted shape: clear it.
        for y in range(0, rows[1] + dy):
            for x in range(fw):
                sx, sy = x - dx, y - dy
                inside = 0 <= sx < fw and 0 <= sy < fh and cp[sx, sy][3]
                if not inside and sy < rows[1] - 1:
                    fp[x, y] = (0, 0, 0, 0)
        strip.paste(frame, (i * fw, 0))
    strip.save(_path(sid, name))


LIFT = {6: ([1, 2, 1, 0, 0, 0], [0, 0, 0, 1, 2, 1]), 8: ([1, 2, 2, 1, 0, 0, 0, 0], [0, 0, 0, 0, 1, 2, 2, 1])}


def _leg_span(base, feet):
    """x range of the legs: the run of opaque columns in the bottom rows around the feet x (gaps of up to 2)."""
    a = base.getchannel("A").load()
    w = base.size[0]
    fx, fy = feet
    cols = [any(a[x, y] for y in range(fy - 2, min(base.size[1], fy + 2))) for x in range(w)]
    lo = hi = fx
    while lo > 0 and (cols[lo - 1] or (lo > 2 and (cols[lo - 2] or cols[lo - 3]))):
        lo -= 1
    while hi < w - 1 and (cols[hi + 1] or (hi < w - 3 and (cols[hi + 2] or cols[hi + 3]))):
        hi += 1
    while not cols[lo]:
        lo += 1
    while not cols[hi]:
        hi -= 1
    return lo, hi


SWAY = [0, 1, 1, 0, -1, -1]


def step(sid, name, legs=0.22, split=None, span=None, sink=False, from_rot=False, hem=0, hem_x=None):
    """Front and back walks whose legs stand still: the legs (the bottom `legs` share of the body, between the
    feet columns) are taken from the rotation frame and each foot lifts in turn, 1-2 px; the frame's own body,
    arms and items above stay. Built from rot_<dir>.png, so running it again is harmless."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    n = strip.size[0] // fw
    base = _rot(sid, name)
    feet = SPRITES[sid]["feet"]
    top = base.getchannel("A").getbbox()[1]
    y0 = feet[1] - int((feet[1] - top) * legs)
    lo, hi = span or _leg_span(base, feet)
    mid = split if split is not None else (lo + hi + 1) // 2
    lift_l, lift_r = LIFT.get(n, LIFT[6])
    left = base.crop((lo, y0, mid, fh))
    right = base.crop((mid, y0, hi + 1, fh))
    for i in range(n):
        frame = base.copy() if from_rot else strip.crop((i * fw, 0, (i + 1) * fw, fh))
        body = frame.crop((0, 0, fw, y0))
        if hem:
            sway = SWAY[i % len(SWAY)]
            hx0, hx1 = hem_x or (lo - 1, hi + 1)  # only the robe above the legs, not items beside it
            band = body.crop((hx0, y0 - hem, hx1 + 1, y0))
            body.paste((0, 0, 0, 0), (hx0, y0 - hem, hx1 + 1, y0))
            body.alpha_composite(band, (hx0 + sway, y0 - hem))
        out = frame.copy()
        out.paste((0, 0, 0, 0), (0, 0, fw, y0))
        out.paste((0, 0, 0, 0), (lo, y0, hi + 1, fh))
        out.alpha_composite(left, (lo, y0 - lift_l[i % len(lift_l)]))
        out.alpha_composite(right, (mid, y0 - lift_r[i % len(lift_r)]))
        out.alpha_composite(body, (0, 1 if sink and i % 3 == 0 else 0))
        strip.paste(out, (i * fw, 0))
    strip.save(_path(sid, name))


def legs(sid, name, donor, y0, span, dx=0):
    """Legs that cross or tangle (rule 2): the rows from y0 down, between span's columns, are replaced frame by
    frame with the legs of a direction Ojon OK'd (donor strip, same frame count), shifted dx to line up with
    the feet. Items beside the legs (an axe) are outside the span and stay. Running it again is harmless."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    src = Image.open(_path(sid, donor)).convert("RGBA")
    fw, fh = _frame_size(sid)
    lo, hi = span
    for i in range(strip.size[0] // fw):
        frame = strip.crop((i * fw, 0, (i + 1) * fw, fh))
        leg = src.crop((i * fw + lo, y0, i * fw + hi + 1, fh))
        frame.paste((0, 0, 0, 0), (lo + dx, y0, hi + 1 + dx, fh))
        body = frame.crop((0, 0, fw, y0))
        frame.alpha_composite(leg, (lo + dx, y0))
        frame.alpha_composite(body, (0, 0))
        strip.paste(frame, (i * fw, 0))
    strip.save(_path(sid, name))


def patch(sid, name, rect, src=None, only=None):
    """An item or hand that goes wrong in some frames (a staff let go of, a lantern that flares): the
    rectangle (x0, y0, x1, y1) is cleared and refilled from the rotation frame (or from frame `src` of the same
    strip, counted from 1), moved with each frame's bob; `only` limits it to those frames (from 1). Running it again is harmless when the source is the
    rotation frame."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    can = _rot(sid, name) if src is None else strip.crop(((src - 1) * fw, 0, src * fw, fh))
    x0, y0, x1, y1 = rect
    piece = can.crop((x0, y0, x1 + 1, y1 + 1))
    bb = can.getchannel("A").getbbox()
    rows = (bb[1], bb[1] + int((bb[3] - bb[1]) * 0.5))
    for i in range(strip.size[0] // fw):
        if only and i + 1 not in only:
            continue
        frame = strip.crop((i * fw, 0, (i + 1) * fw, fh))
        dx, dy = _best_offset(can, frame, rows)
        frame.paste((0, 0, 0, 0), (x0 + dx, y0 + dy, x1 + 1 + dx, y1 + 1 + dy))
        frame.alpha_composite(piece, (x0 + dx, y0 + dy))
        strip.paste(frame, (i * fw, 0))
    strip.save(_path(sid, name))


def outline(sid, name, rect):
    """An item whose bottom edge has no black outline (rule 29, Jessamy's lantern): inside the rectangle
    (x0, y0, x1, y1), every empty pixel just below a coloured pixel turns into outline ink. Already outlined
    edges are left alone, so running it again is harmless."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    x0, y0, x1, y1 = rect
    px = strip.load()
    ink = (12, 10, 16, 255)
    for i in range(strip.size[0] // fw):
        for x in range(i * fw + x0, i * fw + x1 + 1):
            for y in range(y0, y1):
                p, q = px[x, y], px[x, y + 1]
                if p[3] and sum(p[:3]) >= 90 and not q[3]:
                    px[x, y + 1] = ink
    strip.save(_path(sid, name))


def unglow(sid, name, rect):
    """Stray lantern-glow pixels left where the glow flared (Jessamy's walk south): inside the rectangle, bright
    yellow pixels take the colour of the nearest pixel on their left that isn't glow. Idempotent."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    x0, y0, x1, y1 = rect
    px = strip.load()

    def glow(p):
        return p[3] and p[0] > 200 and p[1] > 150 and p[2] < 140

    for i in range(strip.size[0] // fw):
        for y in range(y0, y1 + 1):
            for x in range(i * fw + x0, i * fw + x1 + 1):
                if glow(px[x, y]):
                    k = x - 1
                    while k > i * fw and glow(px[k, y]):
                        k -= 1
                    px[x, y] = px[k, y]
    strip.save(_path(sid, name))


def center(sid, name, head=0.3):
    """A walk that drifts sideways instead of going forward (rule 28, Jessamy's walk north): each frame moves
    left or right by whole pixels so its head sits where the rotation frame's head sits. Idempotent."""
    strip = Image.open(_path(sid, name)).convert("RGBA")
    fw, fh = _frame_size(sid)
    base = _rot(sid, name)
    feet_y = SPRITES[sid]["feet"][1]
    top = base.getchannel("A").getbbox()[1]
    rows = (top, top + int((feet_y - top) * head))

    def head_x(im):
        a = im.getchannel("A").load()
        xs = [x for y in range(*rows) for x in range(fw) if a[x, y]]
        return sum(xs) / len(xs)

    ref = head_x(base)
    for i in range(strip.size[0] // fw):
        frame = strip.crop((i * fw, 0, (i + 1) * fw, fh))
        dx = round(ref - head_x(frame))
        if dx:
            moved = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            moved.alpha_composite(frame, (dx, 0)) if dx > 0 else moved.alpha_composite(frame.crop((-dx, 0, fw, fh)), (0, 0))
            strip.paste(moved, (i * fw, 0))
    strip.save(_path(sid, name))


def main(argv):
    if not argv:
        for fix in json.load(open(os.path.join(HERE, "ai_fixes.json")))["fixes"]:
            op, sid, name = fix["op"], fix["sprite"], fix["strip"]
            if fix.get("once"):
                print("skip     %s/%s  (applied once to the generated strip; running it again would add up)" % (sid, name))
                continue
            if op == "breathe":
                breathe(sid, name)
            elif op == "ends":
                ends(sid, name)
            elif op == "swell":
                swell(sid, name)
            elif op == "bob":
                bob(sid, name, fix.get("ratio", 0.62), fix.get("own", False))
            elif op == "center":
                center(sid, name)
            elif op == "unglow":
                unglow(sid, name, fix["rect"])
            elif op == "outline":
                outline(sid, name, fix["rect"])
            elif op == "patch":
                patch(sid, name, fix["rect"], fix.get("src"), fix.get("only"))
            elif op == "legs":
                legs(sid, name, fix["donor"], fix["y0"], fix["span"], fix.get("dx", 0))
            elif op == "step":
                step(sid, name, fix.get("legs", 0.22), fix.get("split"), fix.get("span"), fix.get("sink", False),
                     fix.get("from_rot", False), fix.get("hem", 0), fix.get("hem_x"))
            else:
                lock(sid, name, fix.get("band", 0.7))
            print("%-8s %s/%s  (%s)" % (op, sid, name, fix["why"]))
        return 0
    if argv[0] == "breathe":
        breathe(argv[1], argv[2])
    elif argv[0] == "ends":
        ends(argv[1], argv[2])
    elif argv[0] == "swell":
        swell(argv[1], argv[2])
    elif argv[0] == "bob":
        bob(argv[1], argv[2], float(argv[3]) if len(argv) > 3 else 0.62, "own" in argv[4:])
    elif argv[0] == "center":
        center(argv[1], argv[2])
    elif argv[0] == "unglow":  # unglow sid strip x0 y0 x1 y1
        unglow(argv[1], argv[2], [int(v) for v in argv[3:7]])
    elif argv[0] == "outline":  # outline sid strip x0 y0 x1 y1
        outline(argv[1], argv[2], [int(v) for v in argv[3:7]])
    elif argv[0] == "patch":  # patch sid strip x0 y0 x1 y1 [src]
        patch(argv[1], argv[2], [int(v) for v in argv[3:7]], int(argv[7]) if len(argv) > 7 and argv[7] != "rot" else None,
              [int(v) for v in argv[8].split(",")] if len(argv) > 8 else None)
    elif argv[0] == "legs":  # legs sid strip donor y0 lo hi dx
        legs(argv[1], argv[2], argv[3], int(argv[4]), (int(argv[5]), int(argv[6])), int(argv[7]))
    elif argv[0] == "step":  # step sid strip legs lo hi split
        step(argv[1], argv[2], float(argv[3]), int(argv[6]), (int(argv[4]), int(argv[5])), "sink" in argv[7:],
             "rot" in argv[7:], int(([a[4:] for a in argv[7:] if a.startswith("hem=")] or [0])[0]),
             ([tuple(int(v) for v in a[5:].split(":")) for a in argv[7:] if a.startswith("hemx=")] or [None])[0])
    elif argv[0] == "lock":
        lock(argv[1], argv[2], float(argv[3]) if len(argv) > 3 else 0.7)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
