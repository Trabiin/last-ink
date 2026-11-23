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


def bob(sid, name, ratio=0.62):
    """Frames 3-4 (of each 4) get frame 1's upper body one pixel lower; rows below stay the frame's own.
    Frame 1 is never changed and rows below the cut are never written, so running it again is harmless."""
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
        frame.paste((0, 0, 0, 0), (0, 0, fw, cut + 1))
        frame.alpha_composite(upper, (0, 1))
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


def main(argv):
    if not argv:
        for fix in json.load(open(os.path.join(HERE, "ai_fixes.json")))["fixes"]:
            op, sid, name = fix["op"], fix["sprite"], fix["strip"]
            if op == "breathe":
                breathe(sid, name)
            elif op == "ends":
                ends(sid, name)
            elif op == "swell":
                swell(sid, name)
            elif op == "bob":
                bob(sid, name, fix.get("ratio", 0.62))
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
        bob(argv[1], argv[2], float(argv[3]) if len(argv) > 3 else 0.62)
    elif argv[0] == "lock":
        lock(argv[1], argv[2], float(argv[3]) if len(argv) > 3 else 0.7)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
