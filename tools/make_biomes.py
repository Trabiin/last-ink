#!/usr/bin/env python3
"""Builds the biome mission maps (docs/ART_ROADMAP.md phase 4, map pool issue #113): 80 x 60 maps, three
layouts per biome, so repeat missions differ. Each map writes its objective spots as @spot lines (wardstone,
Blot, rescue spots, caches for Raid / Salvage, spawn points); scripts/mission_types.gd picks among them per
mission, and moves the Blank's wall a little, so the same map plays differently from one visit to the next.

Layout "a" is the original Act 1 shape (the party comes in from the west, the Blank's wall at tile 69);
"b" comes in from the south-west and "c" from the north-west. Cache spots are picked after the props are
placed, on ground the party can reach, so adding them never moves a tree.

Each biome is a recipe: a ground set, a winding road from the party start to the Blot, side trails to the
rescue spots and spawn clearings, a dense border, and props scattered by noise so they clump into groves,
reed beds or rock fields instead of an even sprinkle. Free-standing prop chars sit at their bottom-centre
tile (scripts/prop.gd). Edit the recipes and rerun:
    python3 tools/make_biomes.py
"""
import math
import os
import random

W, H = 80, 60
HERE = os.path.dirname(os.path.abspath(__file__))
MAPS = os.path.join(HERE, "..", "maps")

# Objective layouts. routes: (from, to, path width scale, wiggle) carved in this order. cache: rough places for
# Raid / Salvage caches (snapped to reachable open ground); the east ones sit near the Blank for Salvage.
LAYOUTS = {
    "a": {"start": (12, 31), "blank": 69, "sign": (14, 28),
          "ward": [(50, 31)], "blot": [(64, 30)], "rescue": [(60, 9), (60, 50), (59, 22)],
          "spawns": [(31, 10), (58, 24), (40, 26), (52, 33), (60, 38), (36, 40), (47, 44)],
          "routes": [((12, 31), (50, 31), 1.0, 4.5), ((50, 31), (64, 30), 1.0, 3.0),
                     ((44, 28), (60, 9), 0.8, 4.5), ((50, 31), (60, 50), 0.8, 4.5), ((44, 28), (59, 22), 0.8, 4.5)],
          "cache": [(28, 14), (36, 44), (44, 20), (24, 46), (56, 14), (58, 44), (62, 24), (62, 36)]},
    "b": {"start": (14, 50), "blank": 66, "sign": (17, 47),
          "ward": [(44, 26), (48, 40)], "blot": [(59, 18), (59, 42)], "rescue": [(54, 8), (56, 52), (30, 10)],
          "spawns": [(24, 38), (34, 28), (44, 14), (50, 46), (28, 18), (54, 30), (40, 50)],
          "routes": [((14, 50), (44, 26), 1.0, 4.5), ((44, 26), (48, 40), 0.9, 3.0), ((44, 26), (59, 18), 1.0, 3.0),
                     ((48, 40), (59, 42), 1.0, 3.0), ((44, 26), (54, 8), 0.8, 4.5), ((48, 40), (56, 52), 0.8, 4.5),
                     ((30, 36), (30, 10), 0.8, 4.0)],
          "cache": [(22, 30), (36, 16), (26, 10), (40, 52), (52, 12), (58, 30), (56, 48), (34, 40)]},
    "c": {"start": (10, 10), "blank": 72, "sign": (13, 7),
          "ward": [(46, 38), (54, 22)], "blot": [(66, 44), (66, 20)], "rescue": [(62, 10), (50, 54), (24, 50)],
          "spawns": [(22, 24), (32, 14), (42, 30), (56, 40), (30, 44), (60, 30), (48, 10)],
          "routes": [((10, 10), (54, 22), 1.0, 4.5), ((54, 22), (46, 38), 1.0, 3.5), ((54, 22), (66, 20), 1.0, 3.0),
                     ((46, 38), (66, 44), 1.0, 3.0), ((54, 22), (62, 10), 0.8, 4.0), ((46, 38), (50, 54), 0.8, 4.0),
                     ((30, 18), (24, 50), 0.8, 4.5)],
          "cache": [(20, 34), (36, 24), (40, 48), (28, 54), (60, 34), (64, 52), (66, 30), (44, 8)]},
}

# Prop sizes in tiles (width, height) for spacing: from the sprites, rounded up.
SIZE = {"fortree": (3, 4), "tree": (3, 4), "fungus": (2, 2), "log": (2, 2), "fern": (3, 2), "roots": (3, 3),
        "totem": (2, 3), "reeds": (2, 2), "marshstump": (2, 2), "lilypad": (2, 1), "planks": (3, 2),
        "boulder": (2, 2), "outcrop": (2, 2), "inkspring": (2, 2), "roadlamp": (1, 2), "drygrass": (2, 2),
        "taxbanner": (1, 3), "milestone": (2, 3), "barricade": (3, 3), "seized": (3, 3), "dock": (4, 3),
        "mill": (6, 6), "tollbooth": (6, 6), "fence": (3, 2), "crates": (2, 2), "barrels": (2, 2),
        "house_a": (6, 6), "house_b": (6, 6), "house_c": (6, 6), "house_d": (6, 6), "house_e": (7, 6),
        "house_f": (6, 6), "house_g": (6, 6), "house_h": (6, 6), "stall": (4, 4), "garden": (3, 2),
        "fountain": (3, 3), "produce": (3, 2),
        # Chapter 2 (issue #28): the Abbey's lands
        "yew": (3, 4), "pine": (3, 4), "ruin": (2, 2), "candles": (1, 2), "chapel": (6, 6), "grave": (1, 2),
        # Chapter 3 (issue #29): the Velvet Causeway
        "townhall": (7, 7), "lamppost": (1, 3), "mask_stall": (4, 4), "balustrade": (3, 2)}

BIOMES = {
    # The Frayed Meadow's own layout "a" is hand-made (maps/frayed_meadow.txt); b and c are generated.
    "meadow": {
        "name": "The Frayed Meadow", "mood": "grade=1.0,1.0,0.98 mist=1.0 motes=1.0,0.97,0.85", "ground": "meadow", "seed": 61,
        "layouts": "bc",
        "sign": "THE FRAYED MEADOW|pop. 212   pop. 40   pop. ?",
        "props": {"T": "bush", "t": "shrub", "r": "rock", "R": "rock_big", "S": "stump", "o": "pond", "b": "bones",
                  "F": "tree", "Z": "drygrass", "N": "fern", "P": "boulder"},
        "border": ["T", "F", "T"],
        "scatter": [("t", 0.05, 0.35), ("T", 0.03, 0.5), ("Z", 0.04, 0.35), ("r", 0.02, 0.3), ("N", 0.015, 0.4),
                    ("F", 0.012, 0.6), ("b", 0.004, 0.0)],
        "path_r": 1.2,
        # Landmarks: a stump circle, a pond with a boulder, a lone tree with bones under it.
        "landmarks": [("S", (34, 8)), ("S", (38, 9)), ("S", (36, 12)), ("S", (32, 11)), ("o", (44, 46)),
                      ("P", (47, 49)), ("F", (22, 22)), ("b", (24, 24))],
        "groves": [("T", 5, 5, 8), ("F", 3, 6, 6), ("Z", 3, 4, 6)],
    },
    "gallows": {
        "name": "Gallows Ferry", "mood": "grade=0.88,0.92,1.0 mist=1.6 motes=0.7,0.75,0.65", "ground": "marsh", "seed": 71,
        "sign": "GALLOWS FERRY|Crossing: 2 Gilt.|Crossing back: negotiable.",
        "props": {"D": "reeds", "M": "marshstump", "Y": "lilypad", "K": "planks", "J": "dock", "X": "crates",
                  "B": "barrels", "E": "fence", "F": "tree", "A": "roadlamp", "Z": "drygrass"},
        "border": ["F", "D"],
        "scatter": [("D", 0.07, 0.35), ("Y", 0.03, 0.5), ("F", 0.03, 0.55), ("M", 0.015, 0.3), ("Z", 0.03, 0.3)],
        "path_r": 1.5, "patches": (6, 0.62),
        # Landmarks: the ferry landing (docks, planks, cargo), lamps on the towpath.
        "landmarks": [("J", (34, 32)), ("J", (40, 34)), ("K", (30, 36)), ("K", (46, 30)), ("X", (36, 28)),
                      ("B", (39, 27)), ("X", (43, 37)), ("A", (26, 30)), ("A", (50, 32)), ("E", (24, 24))],
        "groves": [("D", 5, 5, 8), ("F", 2, 6, 6), ("Y", 3, 4, 5)],
    },
    "gutterwoods": {
        "name": "The Gutterwoods", "mood": "grade=0.80,0.93,0.86 mist=1.3 motes=0.75,0.95,0.6", "ground": "forest", "seed": 11,
        "sign": "GUTTERWOODS|Letters left here are delivered.|Eventually.",
        "props": {"F": "fortree", "U": "fungus", "L": "log", "N": "fern", "O": "roots", "Q": "totem", "I": "inkspring"},
        "border": ["F"],
        "scatter": [("F", 0.10, 0.55), ("N", 0.05, 0.35), ("U", 0.03, 0.4), ("L", 0.015, 0.2),
                    ("O", 0.015, 0.45), ("Q", 0.004, 0.0)],
        "path_r": 1.2,
        # Landmarks: a totem ring round an ink spring (north clearing), a fungus-ringed giant root, a log crossing.
        "landmarks": [("I", (31, 14)), ("Q", (27, 13)), ("Q", (35, 13)), ("Q", (31, 10)), ("U", (28, 17)), ("U", (34, 17)),
                      ("Q", (20, 26)), ("Q", (44, 18)), ("O", (33, 33)), ("U", (30, 34)), ("U", (36, 35)), ("U", (33, 36)),
                      ("O", (55, 30)), ("L", (52, 32)), ("L", (58, 33)), ("N", (54, 34))],
        "groves": [("F", 8, 7, 14), ("U", 3, 3, 5), ("N", 4, 4, 6)],
    },
    "saltreed": {
        "name": "Saltreed Marsh", "mood": "grade=0.82,0.88,0.96 mist=2.0 motes=0.55,0.6,0.5", "ground": "marsh", "seed": 23,
        "sign": "SALTREED|Mind the water.|The water minds you.",
        "props": {"D": "reeds", "M": "marshstump", "Y": "lilypad", "K": "planks", "F": "fortree", "N": "fern"},
        "border": ["D", "F"],
        "scatter": [("D", 0.11, 0.3), ("Y", 0.04, 0.5), ("M", 0.025, 0.3), ("F", 0.02, 0.6), ("N", 0.02, 0.4)],
        "path_r": 1.3, "patches": (7, 0.58),
        "landmarks": [("K", (24, 30)), ("K", (38, 28)), ("K", (56, 31))],
        "groves": [("D", 6, 5, 9), ("F", 2, 6, 6), ("Y", 3, 4, 5)],
    },
    "oldmill": {
        "name": "Old Mill Crossing", "mood": "grade=0.92,0.92,0.95 mist=1.5 motes=1.0,0.95,0.8", "ground": "marsh", "seed": 37,
        "sign": "OLD MILL CROSSING|Flour: none.|Miller: also none.",
        "props": {"D": "reeds", "M": "marshstump", "Y": "lilypad", "K": "planks", "J": "dock", "W": "mill",
                  "X": "crates", "B": "barrels", "E": "fence", "F": "tree", "Z": "drygrass"},
        "border": ["F", "D"],
        "scatter": [("D", 0.06, 0.35), ("Z", 0.05, 0.3), ("F", 0.03, 0.55), ("M", 0.015, 0.3), ("Y", 0.02, 0.55)],
        "path_r": 1.6, "patches": (8, 0.66),
        "landmarks": [("W", (30, 24)), ("J", (36, 40)), ("X", (25, 26)), ("B", (34, 27)), ("E", (22, 35)),
                      ("E", (26, 36)), ("K", (44, 36))],
        "groves": [("D", 4, 5, 8), ("F", 2, 6, 6), ("Z", 3, 4, 6)],
    },
    "lampwick": {
        "name": "Wickham Hills", "mood": "grade=1.04,0.98,0.86 mist=0.5 motes=1.0,0.9,0.55", "ground": "hills", "seed": 41,
        "sign": "LAMPWICK HILLS|Ink spring ahead.|Do not drink. Do not write.",
        "props": {"P": "boulder", "C": "outcrop", "I": "inkspring", "A": "roadlamp", "Z": "drygrass", "F": "tree"},
        "border": ["C", "P", "F"],
        "scatter": [("Z", 0.08, 0.3), ("P", 0.04, 0.45), ("C", 0.03, 0.55), ("F", 0.015, 0.6)],
        "path_r": 1.3, "patches": (6, 0.72),
        "landmarks": [("I", (40, 20)), ("I", (30, 38)), ("A", (22, 30)), ("A", (36, 30)), ("A", (46, 28))],
        "groves": [("P", 3, 5, 7), ("C", 3, 4, 5), ("Z", 4, 4, 6)],
    },
    "tithe_road": {
        "name": "The Tithe Road", "mood": "grade=1.02,0.96,0.89 mist=0.7 motes=0.9,0.85,0.75", "ground": "town", "seed": 53,
        "sign": "THE TITHE ROAD|Concord property.|Tolls are not optional.",
        "props": {"V": "taxbanner", "G": "milestone", "B": "barricade", "H": "seized", "A": "roadlamp",
                  "W": "tollbooth", "F": "tree", "P": "boulder", "Z": "drygrass"},
        "border": ["F", "P"],
        "scatter": [("Z", 0.06, 0.3), ("F", 0.04, 0.55), ("P", 0.02, 0.4)],
        "path_r": 2.0,
        "landmarks": [("W", (32, 26)), ("V", (28, 28)), ("V", (40, 28)), ("G", (20, 29)), ("G", (46, 34)),
                      ("B", (44, 30)), ("H", (56, 27)), ("H", (38, 36)), ("A", (24, 34)), ("A", (52, 28))],
        "groves": [("F", 3, 6, 7), ("Z", 4, 4, 6), ("P", 2, 4, 4)],
    },
    # Chapter 2 (issue #28): Saint Ledger's Abbey region. Ground sets and the new props are tracked placeholders
    # (data/placeholders.json) until the art batch replaces them under the same ids.
    "abbey": {
        "name": "Saint Ledger's Abbey", "mood": "grade=0.88,0.88,0.98 mist=1.3 motes=1.0,0.92,0.7", "ground": "abbey", "seed": 83,
        "sign": "SAINT LEDGER'S ABBEY|Silence in the cloister.|Silence everywhere else, too.",
        "props": {"Y": "yew", "G": "grave", "C": "candles", "U": "ruin", "P": "boulder", "N": "fern", "Z": "drygrass"},
        "border": ["Y", "U", "Y"],
        "scatter": [("G", 0.03, 0.65), ("N", 0.03, 0.4), ("Z", 0.03, 0.3), ("U", 0.015, 0.5), ("Y", 0.02, 0.6),
                    ("P", 0.008, 0.3)],
        "path_r": 1.4,
        # Landmarks: an old graveyard round a votive stand, a fallen arch, a yew over three graves.
        "landmarks": [("C", (30, 20)), ("G", (27, 18)), ("G", (33, 18)), ("G", (27, 23)), ("G", (33, 23)),
                      ("U", (42, 40)), ("U", (45, 41)), ("Y", (22, 40)), ("G", (20, 42)), ("G", (25, 42)), ("C", (48, 26))],
        "groves": [("G", 4, 4, 7), ("Y", 3, 5, 5), ("U", 2, 4, 4)],
    },
    "lakeshore": {
        "name": "The Lake Road", "mood": "grade=0.92,0.94,1.0 mist=1.7 motes=1.0,0.9,0.7", "ground": "lakeshore", "seed": 89,
        "sign": "THE LAKE ROAD|Candleford 2 mi.|Mind the wax on the boards.",
        "props": {"D": "reeds", "M": "marshstump", "Y": "lilypad", "K": "planks", "J": "dock", "X": "crates",
                  "B": "barrels", "F": "tree", "C": "candles", "Z": "drygrass"},
        "border": ["F", "D"],
        "scatter": [("D", 0.06, 0.35), ("Y", 0.03, 0.5), ("F", 0.03, 0.55), ("Z", 0.03, 0.3), ("M", 0.012, 0.3)],
        "path_r": 1.5, "patches": (7, 0.62),
        # Landmarks: a wax jetty (docks, crates, barrels), votive candles on the shore road.
        "landmarks": [("J", (36, 33)), ("J", (42, 35)), ("X", (38, 29)), ("B", (41, 28)), ("K", (30, 36)),
                      ("C", (26, 30)), ("C", (48, 30))],
        "groves": [("D", 5, 5, 8), ("F", 2, 6, 6), ("Y", 3, 4, 5)],
    },
    "scarth": {
        "name": "Scarth Pass", "mood": "grade=0.9,0.95,1.04 mist=0.9 motes=0.9,0.95,1.0", "ground": "mountain", "seed": 97,
        "sign": "SCARTH PASS|Pilgrims' hostel 1 mi.|Road east: closed (white).",
        "props": {"I": "pine", "P": "boulder", "Q": "outcrop", "U": "ruin", "Z": "drygrass", "A": "roadlamp"},
        "border": ["I", "Q", "P"],
        "scatter": [("I", 0.05, 0.55), ("Z", 0.05, 0.3), ("P", 0.03, 0.45), ("Q", 0.025, 0.55), ("U", 0.006, 0.3)],
        "path_r": 1.3, "patches": (6, 0.72),
        # Landmarks: a ruined wayside shrine, lamps along the pilgrims' road.
        "landmarks": [("U", (38, 22)), ("U", (41, 23)), ("A", (22, 30)), ("A", (36, 30)), ("A", (48, 28))],
        "groves": [("I", 6, 6, 10), ("Q", 3, 4, 5), ("P", 3, 5, 6)],
    },
    # Chapter 3 (issue #29): the Velvet Causeway, a bridge-city on the ink lake. Ground set, balustrades and mask
    # stalls are tracked placeholders (data/placeholders.json) until the art batch replaces them under the same ids.
    "causeway": {
        "name": "The Velvet Causeway", "mood": "grade=0.9,0.86,1.0 mist=1.2 motes=1.0,0.88,0.65", "ground": "causeway", "seed": 101,
        "sign": "THE VELVET CAUSEWAY|Mind the steps.|There are fewer than yesterday.",
        "props": {"L": "lamppost", "K": "balustrade", "M": "mask_stall", "X": "crates", "B": "barrels", "J": "dock",
                  "Q": "banner", "H": "house_d", "E": "house_e", "W": "fountain"},
        "border": ["H", "K", "E"],
        "scatter": [("K", 0.05, 0.4), ("L", 0.03, 0.35), ("X", 0.02, 0.4), ("B", 0.02, 0.4), ("M", 0.008, 0.3)],
        "path_r": 1.8, "patches": (7, 0.6),
        # Landmarks: a fountain square under lamps, a mask market, a landing stage on the lake.
        "landmarks": [("W", (30, 22)), ("L", (26, 20)), ("L", (35, 20)), ("M", (40, 40)), ("M", (46, 41)), ("Q", (43, 37)),
                      ("J", (22, 44)), ("J", (27, 45)), ("X", (24, 40))],
        "groves": [("K", 4, 4, 6), ("L", 3, 4, 5), ("X", 2, 4, 4)],
    },
}


TWIN_RADIUS = 3


def variants(kind):
    base = os.path.join(HERE, "..", "assets", "props", kind)
    n = 1
    while os.path.exists("%s_v%d.png" % (base, n)):
        n += 1
    return n


def variant_of(kind, x, y):
    seed = x * 31 + y  # same as scripts/prop.gd
    return (seed * 7 + seed // 5) % variants(kind)


def value_noise(seed, cell):
    rnd = random.Random(seed)
    grid = {}

    def g(ix, iy):
        if (ix, iy) not in grid:
            grid[(ix, iy)] = rnd.random()
        return grid[(ix, iy)]

    def f(x, y):
        gx, gy = x / cell, y / cell
        x0, y0 = math.floor(gx), math.floor(gy)
        tx, ty = gx - x0, gy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * tx
        b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * tx
        return a + (b - a) * ty
    return f


# Props that sit at their top-left tile in scripts/prop.gd (KINDS with a footprint) rather than their bottom-centre.
TOPLEFT = {"bush": (2, 2), "stump": (2, 2), "rock_big": (2, 2), "pond": (2, 2), "shrub": (1, 1), "rock": (1, 1),
           "house": (5, 5), "tavern": (5, 5), "townhall": (5, 5), "well": (3, 3), "cart": (3, 2), "lamppost": (1, 2),
           "noticeboard": (3, 2), "grave": (1, 2), "banner": (1, 2), "bench": (3, 1)}
# Chars area.gd knows without an @prop line.
BUILTIN = {"T": "bush", "t": "shrub", "r": "rock", "R": "rock_big", "S": "stump", "o": "pond", "b": "bones", "k": "skull"}
# Walk-through props (scripts/prop.gd NOBLOCK): they never block a path.
NOBLOCK = {"fern", "drygrass", "reeds", "lilypad", "planks", "dock", "roots", "fungus", "inkspring", "bones", "skull"}


def cells_of(kind, x, y):
    if kind in TOPLEFT:
        w, h = TOPLEFT[kind]
        return {(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)}
    w, h = SIZE.get(kind, (2, 2))
    return {(xx, yy) for yy in range(y - h + 1, y + 1) for xx in range(x - w // 2, x - w // 2 + w)}


def reachable(start, blocked, blank):
    """Tiles the party can walk to from start: inside the border band, west of the Blank, not under a prop."""
    seen = {start}
    todo = [start]
    while todo:
        x, y = todo.pop()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 1 <= nx < min(W - 1, blank - 1) and 1 <= ny < H - 1 and (nx, ny) not in seen and (nx, ny) not in blocked:
                seen.add((nx, ny))
                todo.append((nx, ny))
    return seen


def pick_caches(wanted, reach, blocked, avoid):
    """Snap each rough cache place to the nearest reachable tile with open ground all round it."""
    out = []
    for cx, cy in wanted:
        best = None
        for r in range(0, 9):
            for y in range(cy - r, cy + r + 1):
                for x in range(cx - r, cx + r + 1):
                    if max(abs(x - cx), abs(y - cy)) != r or (x, y) not in reach:
                        continue
                    if any((x + dx, y + dy) in blocked for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                        continue
                    if any(abs(x - a) + abs(y - b2) < 5 for a, b2 in avoid + out):
                        continue
                    best = (x, y)
                    break
                if best:
                    break
            if best:
                break
        if best:
            out.append(best)
    return out


def spot_lines(L, reach, blocked, marks):
    lines = []
    fixed = [L["start"]] + L["ward"] + L["blot"] + L["rescue"] + [m[1] for m in marks]
    for name, pts in [("ward", L["ward"]), ("blot", L["blot"]), ("rescue", L["rescue"])] + [(m[0], [m[1]]) for m in marks]:
        for pt in pts:
            if pt not in reach:
                print("  warning: %s spot %s is not reachable" % (name, pt))
    caches = pick_caches(L["cache"], reach, blocked, fixed)
    if len(caches) < 6:
        print("  warning: only %d cache spots" % len(caches))
    lines.append("@spot start %d,%d" % L["start"])
    for name, pts in [("ward", L["ward"]), ("blot", L["blot"]), ("rescue", L["rescue"]), ("cache", caches),
                      ("spawn", L["spawns"])]:
        lines.append("@spot %s %s" % (name, " ".join("%d,%d" % p for p in pts)))
    named = {}
    for name, pt in marks:
        named.setdefault(name, []).append(pt)
    for name, pts in named.items():
        lines.append("@spot %s %s" % (name, " ".join("%d,%d" % p for p in pts)))
    return lines


def build(bid, b, lid="a", out_name=None, extra=None):
    L = dict(LAYOUTS[lid])
    extra = extra or {}
    BLANK = extra.get("blank", L["blank"])
    START, SIGN_AT = L["start"], L["sign"]
    seed = b["seed"] + {"a": 0, "b": 101, "c": 202}[lid] + extra.get("seed", 0)
    rnd = random.Random(seed)
    g = [['.' for _ in range(W)] for _ in range(H)]
    taken = set()  # tiles a prop or a clearing already holds
    blocked = set()  # tiles under a prop you cannot walk through

    def disc(cx, cy, r):
        for y in range(max(0, int(cy - r - 1)), min(H, int(cy + r + 2))):
            for x in range(max(0, int(cx - r - 1)), min(W, int(cx + r + 2))):
                if (x - cx) ** 2 + ((y - cy) / 0.85) ** 2 <= r * r:
                    g[y][x] = ':'

    def road(a, c, r, wiggle=4.5):
        # A wandering line: midpoints pushed sideways, then sampled densely.
        pts = [a]
        n = max(2, int(math.dist(a, c) / 6))
        for i in range(1, n):
            t = i / n
            pts.append((a[0] + (c[0] - a[0]) * t + rnd.uniform(-wiggle, wiggle),
                        a[1] + (c[1] - a[1]) * t + rnd.uniform(-wiggle, wiggle)))
        pts.append(c)
        for p, q in zip(pts, pts[1:]):
            steps = int(math.dist(p, q) * 3) + 1
            for i in range(steps + 1):
                t = i / steps
                disc(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, r)

    def clear(cx, cy, r):
        for y in range(H):
            for x in range(W):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    taken.add((x, y))

    r = b["path_r"]
    for a, c, scale, wig in L["routes"] + extra.get("routes", []):
        road(a, c, r * scale, wig)
    for s in L["spawns"]:
        if rnd.random() < 0.6:
            disc(s[0], s[1], 2.2)
    if "patches" in b:  # open ground of the biome's own floor: bog in the marsh, scree on the hills
        cell, cut = b["patches"]
        pn = value_noise(seed * 7 + 1, cell)
        fine = value_noise(seed * 7 + 2, cell / 2.5)
        wx, wy = value_noise(seed * 7 + 3, cell * 1.3), value_noise(seed * 7 + 4, cell * 1.3)
        for y in range(H):
            for x in range(W):
                # Domain-warped, two octaves: lobed, wandering shapes instead of the square blobs of plain noise.
                qx, qy = x + (wx(x, y) - 0.5) * cell * 1.6, y + (wy(x, y) - 0.5) * cell * 1.6
                if pn(qx, qy) * 0.75 + fine(qx, qy) * 0.25 > cut * 0.75 + 0.18:
                    g[y][x] = ':'
    disc(START[0], START[1], 2.5)
    for bl in L["blot"]:
        disc(bl[0], bl[1], 3.0)
    for x in range(W):  # paths stay a little ragged
        for y in range(H):
            if g[y][x] == ':' and rnd.random() < 0.04:
                g[y][x] = '.'
    # What must stay open: the start, the wardstones, the Blots, rescue spots, spawn points, the road itself.
    keep = [(START, 4)] + [(w, 4) for w in L["ward"]] + [(bl, 4) for bl in L["blot"]] + [(SIGN_AT, 2)] \
        + [(p, 3) for p in L["rescue"]] + [(s, 2) for s in L["spawns"]] + [(m[1], m[2] if len(m) > 2 else 3) for m in extra.get("marks", [])]
    for p, rr in keep:
        clear(p[0], p[1], rr)
    for y in range(H):
        for x in range(W):
            if g[y][x] == ':':
                taken.add((x, y))

    props = dict(b["props"])
    props.update(extra.get("props", {}))
    chars = {k: k for k in props}
    placed = []
    assert not (set(chars) - set(BUILTIN)) & set("TtrRSobkfe@:0123456789"), "prop chars clash with the map legend"

    def place(key, x, y, force=False):
        kind = props[key]
        cells = cells_of(kind, x, y)
        if any(not (0 <= cx < W and 0 <= cy < H) for cx, cy in cells):
            return False
        if cells & taken and not force:
            return False
        # No identical twin: the game picks a variant from the tile (scripts/prop.gd), so skip a spot where this
        # prop would show the same variant as one of its kind within TWIN_RADIUS tiles (tools/audit_art.py).
        v = variant_of(kind, x, y)
        for (px, py, pk, pv) in placed:
            if pk == kind and pv == v and abs(px - x) <= TWIN_RADIUS and abs(py - y) <= TWIN_RADIUS:
                return False
        placed.append((x, y, kind, v))
        taken.update(cells)
        if kind not in NOBLOCK:
            blocked.update(cells)
        g[y][x] = chars[key]
        return True

    # Set pieces first (personal missions): placed exactly where the recipe says, on cleared ground.
    for key, at in extra.get("setpiece", []):
        if not place(key, at[0], at[1], force=True):
            print("  warning: set piece %s did not fit at %s" % (props[key], at))
    for key, at in b.get("landmarks", []) + extra.get("landmarks", []):
        if not place(key, at[0], at[1]):
            # nudge a landmark until it fits next to the road
            for d in range(1, 6):
                if any(place(key, at[0] + dx, at[1] + dy) for dx, dy in ((d, 0), (-d, 0), (0, d), (0, -d))):
                    break

    # Border: a thick ragged band of the biome's blockers.
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            edge = min(x, y, W - 1 - x, H - 1 - y)
            if edge <= 3 or (edge <= 6 and rnd.random() < 0.4):
                key = rnd.choice(b["border"])
                h = SIZE.get(props[key], (2, 2))[1]
                place(key, min(W - 2, x + rnd.randint(0, 1)), min(H - 1, y + h - 1 + rnd.randint(0, 1)))

    # Groves: a few tight clusters of one prop round a centre, thinning out from the middle, so the map has
    # places (a stand of trees, a reed bed, a rock field) and open ground between them.
    for key, count, radius, n in b.get("groves", []):
        for _ in range(count):
            for _try in range(40):
                cx, cy = rnd.randint(6, W - 7), rnd.randint(6, H - 7)
                if (cx, cy) not in taken and cx < BLANK - 2:
                    break
            for _ in range(n * 3):
                if not n:
                    break
                ang, dist = rnd.uniform(0, 6.283), abs(rnd.gauss(0, radius / 2))
                if place(key, int(cx + math.cos(ang) * dist), int(cy + math.sin(ang) * dist * 0.8)):
                    n -= 1

    # Scatter: each prop thinned by its own noise field so it clumps, with little between the clumps.
    for key, dens, clump in b["scatter"]:
        noise = value_noise(seed * 31 + ord(key[0]), 9)
        for y in range(H):
            for x in range(W):
                n = noise(x, y)
                chance = dens * (0.6 * (1.0 - clump) + clump * 6.0 * max(0.0, n - 0.55) ** 1.2)
                if x >= BLANK - 1:
                    chance *= 0.5  # the Blank's side is emptier
                if rnd.random() < chance:
                    place(key, x, y)
    # Flowers / ground scraps on open grass
    for y in range(H):
        for x in range(W):
            if g[y][x] == '.' and (x, y) not in taken and rnd.random() < 0.03:
                g[y][x] = 'f'

    for s in L["spawns"]:
        g[s[1]][s[0]] = 'e'
    g[START[1]][START[0]] = '@'
    g[SIGN_AT[1]][SIGN_AT[0]] = '1'

    reach = reachable(START, blocked, BLANK)
    name = extra.get("name", b["name"])
    head = ["# Last Ink map: %s (80 x 60 tiles of 16px). Generated by tools/make_biomes.py: edit that script, not this file." % name,
            "# Same legend as frayed_meadow.txt; the @prop lines below name this biome's props (free-standing, placed at",
            "# their bottom-centre tile). @spot lines are the objective spots missions pick from (layout \"%s\")." % lid,
            "@name " + name, "@blank %d" % BLANK, "@ground " + b["ground"], "@mood " + extra.get("mood", b["mood"])]
    for k, kind in props.items():
        if k not in BUILTIN:
            head.append("@prop%s %s" % (chars[k], kind))
    head.append("@sign1 " + extra.get("sign", b["sign"]))
    head += spot_lines(L, reach, blocked, [(m[0], m[1]) for m in extra.get("marks", [])])
    head.append("---")
    path = os.path.join(MAPS, (out_name or bid) + ".txt")
    with open(path, "w") as f:
        f.write("\n".join(head) + "\n" + "\n".join("".join(row) for row in g) + "\n")
    print("wrote", path)


def annotate(name, lid="a"):
    """Adds @spot lines to a hand-made map (frayed_meadow) without touching its rows."""
    path = os.path.join(MAPS, name + ".txt")
    text = open(path).read().split("\n")
    sep = text.index("---")
    head = [l for l in text[:sep] if not l.startswith("@spot ") and not l.startswith("# @spot")]
    rows = [l for l in text[sep + 1:] if l.strip()]
    L = dict(LAYOUTS[lid])
    L["spawns"] = [(x, y) for y, row in enumerate(rows) for x, ch in enumerate(row) if ch == "e"] or L["spawns"]
    blank = L["blank"]
    for l in head:
        if l.startswith("@blank "):
            blank = int(l[7:])
    blocked = set()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            kind = BUILTIN.get(ch)
            if kind and kind not in NOBLOCK:
                blocked |= cells_of(kind, x, y)
    reach = reachable(L["start"], blocked, blank)
    head += ["# @spot lines: objective spots missions pick from (tools/make_biomes.py annotate)."]
    head += spot_lines(L, reach, blocked, [])
    with open(path, "w") as f:
        f.write("\n".join(head + ["---"] + rows) + "\n")
    print("annotated", path)


if __name__ == "__main__":
    import sys
    only = sys.argv[1:]
    for bid, b in BIOMES.items():
        for lid in b.get("layouts", "abc"):
            out = bid if lid == "a" else "%s_%s" % (bid, lid)
            if not only or out in only or bid in only:
                build(bid, b, lid, out)
    if not only or "frayed_meadow" in only:
        annotate("frayed_meadow")
    if not only or "personal" in only:
        import make_personal  # the hand-placed set pieces of the personal missions (issue #113)
        make_personal.build_all(build, BIOMES)
    if not only or "chapter2" in only:
        import make_chapter2  # Chapter 2's story maps (issue #28)
        make_chapter2.build_all(build, BIOMES)
    if not only or "chapter3" in only:
        import make_chapter3  # Chapter 3's story maps (issue #29)
        make_chapter3.build_all(build, BIOMES)
