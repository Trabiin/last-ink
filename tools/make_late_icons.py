#!/usr/bin/env python3
"""Icons for issue #189 (the late economy): the fourth research nodes, the studies with ranks, the chapter
research branches and the tavern feast. Same method as tools/make_item_icons.py (PixelLab Pro generate-image-v2
at 32x32 anchored to an existing research icon, 8 concepts a call, picked by eye, palette-snapped).

    python3 tools/make_late_icons.py gen 0            # batch 0 -> /tmp/claude-0/icons189/b0_<k>.png + b0_sheet.png
    python3 tools/make_late_icons.py gen all
    python3 tools/make_late_icons.py pick 0 3 17 ...  # option index per concept, in order -> assets/icons

Spend goes to tools/art_spend_items.jsonl (phase 189)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault("ICON_OUT", "/tmp/claude-0/icons189")
import make_item_icons as base  # noqa: E402
import pixellab  # noqa: E402

CONCEPTS = [
    ("ward_beacons", "a tall iron beacon lamp burning a bright blue flame, rays of light"),
    ("ward_study", "an open notebook full of sketches of a white jagged edge, a pencil on it"),
    ("log_relays", "a galloping horse's horseshoe with a small rolled message scroll tied to it"),
    ("log_study", "a stack of three ledgers with a brass compass on top"),
    ("ink_wells", "a stone well brimming with glowing black ink"),
    ("ink_study", "an inkwell with three quills of different coloured inks, red blue and gold"),
    ("arms_temper", "a sword blade with a page of writing folded into the steel, glowing edge"),
    ("arms_study", "a drill manual book with crossed swords on the cover"),
    ("cw_masks", "a black and gold masquerade half mask with a ribbon"),
    ("cw_charts", "a rolled chart of a dark lake with a red X mark"),
    ("cw_duels", "two crossed slim rapiers with a red rose between them"),
    ("co_seawalls", "a stone sea wall with a breaking wave stopped mid splash"),
    ("co_wrecks", "a ship's wheel half sunk with a coil of rope"),
    ("co_sentences", "a torn scroll with an unfinished line of writing trailing off into dots"),
    ("sp_errata", "a small paper correction slip pinned over a page with a red pin"),
    ("sp_countersign", "a quill signing a gold document with two signatures"),
    ("sp_last_word", "a golden open book with a single glowing word at the bottom of the page"),
    ("feast", "a roast pig on a platter with a tankard of ale and bread"),
]
BATCHES = [CONCEPTS[i:i + 8] for i in range(0, len(CONCEPTS), 8)]
base.BATCHES = BATCHES
base.OUT = os.environ["ICON_OUT"]
base.STYLE_REF = os.path.join(base.ROOT, "assets/icons/ward_lampwright.png")


def gen(b):
    pl = pixellab.PL(phase="189")
    os.makedirs(base.OUT, exist_ok=True)
    concepts = BATCHES[b]
    letters = "ABCDEFGH"
    desc = base.STYLE.replace("Eight different icons", "%d different icons" % len(concepts)) \
        + " ".join("%s) %s." % (letters[i], c[1]) for i, c in enumerate(concepts))
    before = pl.balance()
    job = pixellab.generate_styled(pl, desc, (32, 32), base.STYLE_REF, seed=189 + b)
    done = pl.wait_jobs([job], what="late icons batch %d" % b)
    after = pl.balance()
    files = pixellab.save_styled(done[job], os.path.join(base.OUT, "b%d" % b))
    base.sheet(b, files)
    print("batch %d: %d options, cost $%.4f (balance %.4f -> %.4f)" % (b, len(files), before - after, before, after))


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        todo = range(len(BATCHES)) if sys.argv[2] == "all" else [int(sys.argv[2])]
        for b in todo:
            gen(b)
    elif sys.argv[1] == "pick":
        base.pick(int(sys.argv[2]), [int(a) for a in sys.argv[3:]])
