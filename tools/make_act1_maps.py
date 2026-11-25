#!/usr/bin/env python3
"""The Act 1 set-piece maps: hand-laid premade maps built with the building kit (docs/MAP_KIT.md).

    python3 tools/make_act1_maps.py        # writes maps/ch1_tax_office.txt, act1_gristle.txt, act1_daro.txt, act1_millbrook.txt

Each map is laid out in code (rooms, walls, paths, props, @spot lines) so a layout can be moved around without
hand-editing a 70-column text grid. Rules the layouts follow (MAP_KIT.md section 5): a place before a
battlefield, routes not fields, something hidden, the Blank changes the map, built around the choice.
Edit this script, not the generated files.
"""
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Map:
    def __init__(self, w, h, fill="."):
        self.w, self.h = w, h
        self.g = [[fill] * w for _ in range(h)]
        self.spots = {}
        self.head = []

    def get(self, x, y):
        return self.g[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def path(self, pts, c=":", width=2):
        """A path through the points, `width` tiles wide (each leg goes along x first, then y)."""
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            x, y = ax, ay
            while True:
                for dy in range(width):
                    for dx in range(width):
                        self._soft(x + dx, y + dy, c)
                if (x, y) == (bx, by):
                    break
                if x != bx:
                    x += 1 if bx > x else -1
                else:
                    y += 1 if by > y else -1

    def _soft(self, x, y, c):
        if self.get(x, y) in (".", "f", "t", "T", "r"):
            self.put(x, y, c)

    def building(self, x0, y0, x1, y1, doors_s=(), doors_n=(), doors_w=(), doors_e=(), windows=(), face=2):
        """A walled, roofed building whose floor is x0..x1, y0..y1. Walls go round it: north cap and inside
        face above, side caps, south cap and `face` rows of outside face below. Doors are x (north/south)
        or y (west/east) positions; windows are x positions on the top row of the outside face."""
        self.rect(x0 - 1, y0 - 2, x1 + 1, y0 - 2, "#")
        self.rect(x0, y0 - 1, x1, y0 - 1, "=")
        self.rect(x0 - 1, y0 - 1, x0 - 1, y1 + 1, "#")
        self.rect(x1 + 1, y0 - 1, x1 + 1, y1 + 1, "#")
        self.rect(x0, y0, x1, y1, "_")
        self.rect(x0 - 1, y1 + 1, x1 + 1, y1 + 1, "#")
        self.rect(x0 - 1, y1 + 2, x1 + 1, y1 + 1 + face, "=")
        for x in windows:
            self.put(x, y1 + 2, "!")
        for x in doors_s:
            for y in range(y1 + 1, y1 + 2 + face):
                self.put(x, y, "+")
        for x in doors_n:
            self.put(x, y0 - 2, "+")
            self.put(x, y0 - 1, "+")
        for y in doors_w:
            self.put(x0 - 1, y, "+")
        for y in doors_e:
            self.put(x1 + 1, y, "+")

    def wall_v(self, x, y0, y1, doors=()):
        """An inside wall running north-south (seen from above: its top)."""
        for y in range(y0, y1 + 1):
            self.put(x, y, "+" if y in doors else "#")

    def wall_h(self, x0, x1, y, doors=()):
        """An inside wall running east-west: its top, and its face under it."""
        for x in range(x0, x1 + 1):
            self.put(x, y, "+" if x in doors else "#")
            self.put(x, y + 1, "+" if x in doors else "=")

    def fence(self, x0, y0, x1, y1, gates=()):
        """A walled yard with no roof (palisade, pen): a ring of wall top with a face on its south side."""
        self.rect(x0, y0, x1, y0, "#")
        self.rect(x0, y0, x0, y1, "#")
        self.rect(x1, y0, x1, y1, "#")
        self.rect(x0, y1, x1, y1, "#")
        self.rect(x0, y1 + 1, x1, y1 + 1, "=")
        for (x, y) in gates:
            self.put(x, y, "+")
            if y == y1:
                self.put(x, y1 + 1, "+")

    def scatter(self, chars, n, rng, box=None, avoid=2):
        x0, y0, x1, y1 = box or (1, 1, self.w - 2, self.h - 2)
        placed = 0
        tries = 0
        while placed < n and tries < n * 40:
            tries += 1
            x, y = rng.randint(x0, x1), rng.randint(y0, y1)
            if all(self.get(x + dx, y + dy) in (".", "f") for dx in range(-avoid, avoid + 1) for dy in range(-avoid, avoid + 1)):
                self.put(x, y, rng.choice(chars))
                placed += 1

    def edge_trees(self, rng, thick=2, chars="tT", gaps=()):
        for y in range(self.h):
            for x in range(self.w):
                if x < thick or y < thick or x >= self.w - thick or y >= self.h - thick:
                    if any(abs(x - gx) + abs(y - gy) <= 2 for gx, gy in gaps):
                        continue
                    if self.get(x, y) == "." and rng.random() < 0.7:
                        self.put(x, y, "t" if rng.random() < 0.75 else ".")

    def spot(self, name, x, y):
        self.spots.setdefault(name, []).append((x, y))

    def write(self, name, title, comment):
        out = ["# Last Ink map: %s (%d x %d tiles of 16px). %s" % (title, self.w, self.h, comment),
               "# Generated by tools/make_act1_maps.py: edit that script, not this file. Legend: frayed_meadow.txt,",
               "# building kit chars (# = ! _ +) in scripts/structures.gd."]
        out += self.head
        for k, pts in self.spots.items():
            out.append("@spot %s %s" % (k, " ".join("%d,%d" % p for p in pts)))
        out.append("---")
        # The party starts on the "start" spot ("@" in the rows, Area.party_start).
        sx, sy = self.spots["start"][0]
        for y in range(max(sy - 2, 0), min(sy + 3, self.h)):  # nothing scattered on top of the party
            for x in range(max(sx - 2, 0), min(sx + 3, self.w)):
                if self.g[y][x].isalpha():
                    self.g[y][x] = "."
        self.g[sy][sx] = "@"
        out += ["".join(r) for r in self.g]
        with open(os.path.join(ROOT, "maps", name + ".txt"), "w") as f:
            f.write("\n".join(out) + "\n")
        print("wrote maps/%s.txt" % name)


# ---------------------------------------------------------------- Chapter 1: the tax office at night

def tax_office():
    rng = random.Random(11)
    m = Map(64, 40)
    m.head = ["@name Hollowmark: Tax Office Square", "@blank 59", "@ground town", "@kit stone",
              "@propH house_c", "@propG house_e", "@propK house_g", "@propF fountain", "@propX crates",
              "@propU barrels", "@propV taxbanner", "@propN bench", "@propL lamppost", "@propW well",
              "@dirt XUNLV",
              "@sign1 HOLLOWMARK LOCKUP|for persons not yet processed",
              "@sign2 TAX OFFICE|(please queue)   (please)"]
    # The lockup: three cells off a corridor, front door on the east into the yard.
    m.building(4, 6, 15, 12, doors_e=(11,), windows=())
    m.wall_h(4, 15, 8, doors=(6, 10, 14))
    m.wall_v(8, 6, 7)
    m.wall_v(12, 6, 7)
    m.put(20, 15, "1")
    # The tax office: filing room and pen to the north, tax hall and records room to the south.
    m.building(30, 5, 52, 20, doors_s=(37,), doors_w=(16,), windows=(33, 41, 49))
    m.wall_h(30, 44, 10, doors=(37,))
    m.wall_v(45, 5, 20, doors=(16,))
    m.wall_h(46, 52, 10, doors=(49,))
    for x, y in ((31, 13), (31, 18), (43, 13), (43, 18)):
        m.put(x, y, "V")
    m.put(48, 18, "X")
    m.put(32, 6, "U")
    m.put(40, 6, "X")
    # The yard between them, the square south, the gate out west.
    m.path([(17, 11), (24, 11), (24, 16), (29, 16)])
    m.path([(37, 24), (37, 30), (6, 30), (6, 37)], width=3)
    m.path([(24, 16), (24, 30)])
    m.rect(26, 26, 48, 34, ":")
    m.put(36, 29, "F")
    m.put(29, 27, "N")
    m.put(45, 27, "N")
    m.put(22, 12, "X")
    m.put(25, 13, "U")
    m.put(26, 31, "L")
    m.put(47, 31, "L")
    m.put(14, 26, "H")
    m.put(52, 37, "G")
    m.put(16, 38, "K")
    m.put(56, 28, "W")
    m.put(29, 24, "2")
    m.edge_trees(rng, gaps=((6, 38),))
    m.spot("start", 6, 7)
    m.spot("lockup_door", 18, 11)
    m.spot("yard", 22, 15)
    m.spot("hall", 37, 15)
    m.spot("records", 49, 15)
    m.spot("pen", 49, 7)
    m.spot("strongbox", 51, 18)
    m.spot("square", 36, 26)
    m.spot("gate", 6, 37)
    m.write("ch1_tax_office", "Hollowmark at night, the tax office and its lockup",
            "Chapter 1 breakout. The Blank eats in from the east as you go.")


# ---------------------------------------------------------------- Act 1: the witch in the hollow tree

def gristle():
    rng = random.Random(23)
    m = Map(70, 46)
    m.head = ["@name The Gutterwoods: the Hollow Tree", "@blank 66", "@ground forest", "@kit palisade",
              "@mood grade=0.86,0.95,0.88 mist=1.5 motes=0.75,0.95,0.6",
              "@propF fortree", "@propY yew", "@propU fungus", "@propO roots", "@propL log", "@propN fern",
              "@propQ totem", "@propC cart", "@propX crates", "@propB barricade",
              "@sign1 CURES. PAY FIRST.|(no credit)   (no refunds)   (no)"]
    # The forest: thick everywhere, two ways up to the tree.
    for _ in range(200):
        x, y = rng.randint(1, 68), rng.randint(1, 44)
        if m.get(x, y) == ".":
            m.put(x, y, rng.choice("FFFtNNUO"))
    m.path([(6, 40), (6, 32), (22, 32), (22, 22), (33, 22), (33, 15)], width=3)  # the woodcutters' track
    m.path([(22, 32), (40, 32), (40, 24), (46, 24), (46, 16), (37, 16)], width=2)  # the long way, by the stream
    # The hollow tree's clearing.
    m.rect(28, 9, 42, 18, ":")
    m.put(35, 9, "Y")  # the tree itself
    m.put(31, 11, "1")
    m.put(39, 12, "Q")
    m.put(30, 16, "L")
    # The hunters' camp up the ridge: a stockade with a lodge in it.
    m.fence(48, 3, 66, 14, gates=((52, 14),))
    m.building(54, 6, 62, 9, doors_s=(58,), windows=(56, 60), face=1)
    m.rect(49, 11, 65, 13, ":")
    m.put(50, 5, "X")
    m.put(64, 12, "C")
    m.path([(44, 16), (52, 16), (52, 15)], width=2)
    m.put(46, 20, "B")
    m.spot("start", 6, 40)
    m.spot("tree", 35, 13)
    m.spot("camp", 52, 17)
    m.spot("lodge", 58, 13)
    m.spot("purse", 58, 7)
    m.write("act1_gristle", "The Gutterwoods: the Hollow Tree", "Act 1 story mission: Mother Gristle.")


# ---------------------------------------------------------------- Act 1: the deserter's farm

def daro():
    rng = random.Random(37)
    m = Map(72, 44)
    m.head = ["@name The Tithe Road: Hobb's Farm", "@blank 70", "@ground road", "@kit timber",
              "@kitat 56,25 palisade",
              "@propH house_a", "@propK house_f", "@propC cart", "@propX crates", "@propU barrels",
              "@propE fence", "@propM milestone", "@propB barricade", "@propV taxbanner", "@propR tree",
              "@dirt XUBC",
              "@sign1 HOBB FARM|eggs   (were)   eggs",
              "@sign2 TITHE ROAD|Hollowmark 6   Concord Spire 112"]
    m.path([(1, 27), (70, 27)], width=3)  # the road, straight as a ruler
    # Hobb's farmhouse: kitchen and parlour, front door to the yard, back door to the lane.
    m.building(14, 9, 27, 15, doors_s=(18,), doors_n=(25,), windows=(15, 22, 26))
    m.wall_v(21, 9, 15, doors=(12,))
    m.put(16, 10, "U")
    m.put(26, 14, "X")
    m.path([(18, 19), (18, 27)], width=2)
    m.path([(25, 6), (25, 4), (4, 4), (4, 2)], width=2)  # the back lane, north and west through the hedges
    for x in range(8, 13):
        m.put(x, 20, "E")
    for x in range(30, 40, 3):
        m.put(x, 20, "E")
    m.rect(30, 9, 44, 18, "f")  # the turnip field
    m.put(9, 14, "H")
    m.put(12, 25, "M")
    m.put(7, 24, "1")
    # The press gang's camp on the road east: a stockade with their wagon and a tent.
    m.fence(50, 18, 66, 36, gates=((50, 27), (50, 28), (50, 29)))
    m.building(55, 31, 61, 32, doors_n=(58,), face=1)
    m.rect(51, 19, 65, 28, ":")
    m.put(58, 21, "C")
    m.put(53, 20, "X")
    m.put(63, 20, "U")
    m.put(52, 25, "V")
    m.put(45, 25, "B")
    m.put(45, 31, "B")
    m.put(40, 30, "2")
    m.scatter("RtT", 26, rng, (1, 30, 48, 42))
    m.scatter("RtT", 16, rng, (30, 1, 70, 8))
    m.edge_trees(rng, gaps=((4, 1), (1, 28)))
    m.spot("start", 6, 28)
    m.spot("farm", 18, 19)
    m.spot("inside", 17, 12)
    m.spot("lane", 4, 2)
    m.spot("wagon", 58, 23)
    m.spot("gate", 48, 28)
    m.write("act1_daro", "The Tithe Road: Hobb's Farm", "Act 1 story mission: Corporal Daro.")


# ---------------------------------------------------------------- Act 1: the Concord answers at Millbrook

def millbrook():
    rng = random.Random(41)
    m = Map(76, 48)
    m.head = ["@name Old Mill Crossing: Millbrook", "@blank 74", "@ground marsh", "@kit timber",
              "@propH house_b", "@propG house_d", "@propK house_h", "@propC cart", "@propX crates",
              "@propU barrels", "@propE fence", "@propN noticeboard", "@propV taxbanner", "@propW well",
              "@propR reeds", "@propM marshstump", "@propI mill",
              "@dirt XUCNVW",
              "@sign1 MILLBROOK|est. before the Ledger   (do not tell them)",
              "@sign2 OLD MILL CROSSING  ->|toll: one (1) honest answer"]
    m.path([(4, 40), (4, 26), (72, 26)], width=3)  # the road through, east over the crossing
    m.path([(36, 26), (36, 18), (18, 18)], width=2)  # up to the mill
    m.rect(28, 20, 44, 25, ":")  # the green
    # The mill: grain floor and the stones room, its door on the green side.
    m.building(11, 8, 24, 14, doors_s=(18,), doors_e=(11,), windows=(13, 22))
    m.wall_v(19, 8, 14, doors=(10,))
    m.put(14, 10, "U")
    m.put(23, 13, "X")
    m.put(8, 12, "I")
    # The pen on the green: hurdles, no roof.
    m.fence(30, 29, 40, 35, gates=((35, 29),))
    m.rect(31, 30, 39, 34, ":")
    m.put(34, 22, "N")
    m.put(38, 22, "V")
    m.put(30, 23, "W")
    # Cottages (scenery) and the wagon by the crossing.
    m.put(52, 18, "H")
    m.put(60, 40, "G")
    m.put(48, 42, "K")
    m.put(64, 24, "C")
    m.put(62, 22, "X")
    m.put(67, 29, "U")
    m.put(70, 25, "2")
    m.put(8, 38, "1")
    for x in range(44, 56, 3):
        m.put(x, 32, "E")
    m.scatter("RMt", 40, rng, (46, 2, 72, 16))
    m.scatter("RMtT", 30, rng, (1, 30, 28, 46))
    m.scatter("RMt", 20, rng, (44, 34, 72, 46))
    m.edge_trees(rng, gaps=((4, 44), (74, 27)))
    m.spot("start", 4, 41)
    m.spot("green", 36, 22)
    m.spot("pen", 35, 32)
    m.spot("mill", 17, 11)
    m.spot("mill_door", 18, 18)
    m.spot("wagon", 63, 27)
    m.spot("bridge", 70, 27)
    m.write("act1_millbrook", "Old Mill Crossing: Millbrook", "Act 1 story mission: the Concord answers.")


if __name__ == "__main__":
    tax_office()
    gristle()
    daro()
    millbrook()
