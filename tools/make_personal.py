#!/usr/bin/env python3
"""Set-piece maps for the personal missions (issue #113, data/personal.json).

Each one is a biome map from tools/make_biomes.py (same ground, props and generator) with the character's
own places put down by hand: Bran's broker's counting-house on the ferry landing, the Coven tree, Hob's Wick,
Quill's strongbox, the ruin of the Last Drop, Hild's chapel, the door on Lantern Row, Fennick's toll house,
Odile's inn, the Gilded Heron. Their @spot lines are what the mission's steps point at.

Run through make_biomes.py (it calls build_all), or on its own:
    python3 tools/make_personal.py
"""

# Extra prop chars (lowercase, so they never clash with a biome's own) -> prop kind.
SET = {"h": "house_c", "i": "house_e", "j": "house_a", "n": "house_b", "p": "house_g", "q": "banner",
       "l": "lamppost", "g": "grave", "u": "totem", "a": "fortree", "v": "tavern", "s": "seized",
       "m": "mill", "w": "noticeboard", "d": "house_d", "y": "house_f", "z": "house_h", "x": "crates", "c": "barrels",
       "~": "dock"}

MAPS = {
    "personal_bran": {
        "biome": "gallows", "layout": "a", "name": "Gallows Ferry: the Landing",
        "sign": "CRANE & NEPHEWS|Contracts bought, sold|and enforced.",
        "marks": [("landing", (32, 31)), ("yard", (44, 31)), ("house", (52, 30), 2)],
        "setpiece": [("h", (52, 28)), ("l", (48, 29)), ("l", (56, 29)), ("x", (57, 31)), ("c", (47, 32))],
    },
    "personal_gristle": {
        "biome": "gutterwoods", "layout": "b", "name": "The Gutterwoods: Coven Ground",
        "sign": "COVEN GROUND|Trespassers will be|written to.",
        "marks": [("treeline", (30, 32)), ("tree", (44, 24), 2)],
        "setpiece": [("a", (44, 20)), ("u", (41, 23)), ("u", (47, 23)), ("u", (41, 18)), ("u", (47, 18)),
                     ("i", (36, 21)), ("u", (27, 33)), ("u", (33, 33))],
    },
    "personal_ninefingers": {
        "biome": "tithe_road", "layout": "c", "name": "The Tithe Road: Hob's Wick",
        "sign": "HOB'S WICK  2 MI|By order of the Concord|this village does not exist.",
        "marks": [("poster1", (20, 13), 2), ("poster2", (32, 16), 2), ("poster3", (44, 19), 2),
                  ("tollpost", (54, 22)), ("village", (46, 40)), ("chapel", (44, 49), 2)],
        "setpiece": [("w", (19, 10)), ("w", (31, 13)), ("w", (43, 16)), ("V", (52, 25)), ("V", (57, 25)),
                     ("j", (40, 42)), ("n", (56, 52)), ("m", (34, 50)), ("p", (40, 53)), ("g", (43, 46)), ("g", (46, 46))],
    },
    "personal_quill": {
        "biome": "oldmill", "layout": "a", "name": "Old Mill Crossing: the Strongbox",
        "sign": "CONCORD STRONGBOX|Records of the Hollowmark Office.|Do not correct.",
        "marks": [("mill", (44, 28)), ("strongbox", (59, 22), 2)],
        "setpiece": [("s", (62, 21)), ("x", (56, 20)), ("c", (57, 24))],
    },
    "personal_tobble": {
        "biome": "meadow", "layout": "b", "name": "The Frayed Meadow: the Last Drop", "blank": 67,
        "sign": "THE LAST DROP  ->|Best ale on the Tithe Road.|(Last orders long ago.)",
        "marks": [("ridge", (30, 38)), ("yard", (50, 41)), ("sign", (57, 40), 2)],
        "setpiece": [("v", (55, 34)), ("b", (53, 39)), ("b", (61, 38))],
    },
    "personal_abeyance": {
        "biome": "lampwick", "layout": "c", "name": "Wickham Hills: the Chapel Nobody Remembers",
        "sign": "LAMPWICK HILLS|There is no chapel here.|Please stop asking.",
        "marks": [("mark1", (30, 15), 2), ("mark2", (50, 30), 2), ("mark3", (58, 16), 2), ("chapel", (62, 10), 2)],
        "setpiece": [("z", (63, 7)), ("g", (59, 7)), ("g", (66, 7))],
    },
    "personal_ottoline": {
        "biome": "gallows", "layout": "b", "name": "Gallows Ferry: Lantern Row", "blank": 69,
        "sign": "LANTERN ROW|Home of the Crimson Encore.|(The Encore regrets.)",
        "marks": [("row", (50, 41)), ("door", (60, 42), 2)],
        "setpiece": [("y", (52, 37)), ("d", (60, 37)), ("l", (50, 39)), ("l", (56, 39)), ("l", (63, 40))],
    },
    "personal_jessamy": {
        "biome": "tithe_road", "layout": "b", "name": "The Tithe Road by Night",
        "mood": "grade=0.62,0.68,0.92 mist=1.4 motes=0.6,0.65,0.9",
        "sign": "TOLL POST 9|Notary on duty.|Names struck while you wait.",
        "marks": [("lane", (30, 36)), ("lane2", (36, 32)), ("window", (41, 25), 2)],
        "setpiece": [("j", (40, 23)), ("A", (37, 26)), ("A", (45, 25))],
    },
    "personal_odile": {
        "biome": "oldmill", "layout": "c", "name": "Old Mill Crossing: the Inn",
        "sign": "THE HONEST MEASURE|Rooms. Ale. Arbitration.",
        "marks": [("fields", (30, 16)), ("inn", (40, 40), 2)],
        "setpiece": [("v", (38, 34)), ("E", (35, 41)), ("E", (45, 41))],
    },
    "personal_velvette": {
        "biome": "saltreed", "layout": "a", "name": "Saltreed Marsh: the Gilded Heron",
        "sign": "THE GILDED HERON|Tonight: a closing act|you will never forget.",
        "marks": [("gangway", (44, 30)), ("deck", (52, 31)), ("stage", (58, 31), 2), ("cabin", (59, 22), 2)],
        "setpiece": [("~", (54, 34)), ("~", (58, 34)), ("~", (62, 34)), ("q", (53, 28)), ("q", (62, 28)),
                     ("l", (55, 28)), ("l", (60, 28)), ("n", (61, 20))],
    },
    # Chapter 3 (issue #29): the Causeway heroes
    "personal_hortense": {
        "biome": "oldmill", "layout": "b", "name": "Vauclair Terraces: the School",
        "mood": "grade=0.82,0.78,0.98 mist=1.2 motes=0.9,0.85,1.0",
        "sign": "OFFICE OF CORRECTIONS|School for the Daughters of Debtors.|Visitors by appointment.",
        "marks": [("vines", (34, 30)), ("school", (46, 22), 2), ("dormitory", (52, 14), 2)],
        "setpiece": [("p", (50, 12)), ("q", (45, 18)), ("q", (52, 18)), ("l", (42, 22)), ("l", (55, 20))],
    },
    "personal_saffron": {
        "biome": "lakeshore", "layout": "c", "name": "Pendower Shallows: the Sung House",
        "mood": "grade=0.86,0.88,1.0 mist=1.9 motes=1.0,0.95,0.75",
        "sign": "PENDOWER SHALLOWS|Word-nets: no fishing|after dark.",
        "marks": [("moorings", (30, 20)), ("flats", (44, 34)), ("house", (52, 40), 2)],
        "setpiece": [("j", (52, 37)), ("~", (26, 23)), ("~", (32, 24)), ("x", (29, 18)), ("l", (48, 41))],
    },
    "personal_nan": {
        "biome": "causeway", "layout": "a", "name": "Lantern Quay: the Smugglers' Wharf",
        "mood": "grade=0.62,0.64,0.9 mist=1.3 motes=0.95,0.75,0.5",
        "sign": "J. PRATT & CO.|Loans. Bonds. Collections.|Interest compounded daily.",
        "marks": [("wharf", (40, 31)), ("counting_house", (54, 28), 2), ("strongbox", (58, 20), 2)],
        "setpiece": [("z", (56, 18)), ("~", (40, 35)), ("~", (46, 35)), ("x", (44, 28)), ("c", (37, 28)), ("l", (48, 34)), ("l", (60, 26))],
    },
}


def build_all(build, biomes):
    for out, m in MAPS.items():
        b = biomes[m["biome"]]
        props = {k: v for k, v in SET.items()}
        used = {c for c, _ in m["setpiece"]}
        extra = {
            "name": m["name"], "sign": m["sign"], "seed": 7,
            "props": {k: v for k, v in props.items() if k in used},
            "setpiece": m["setpiece"], "marks": m["marks"],
        }
        for k in ("blank", "mood"):
            if k in m:
                extra[k] = m[k]
        print(out + ":")
        build(m["biome"], b, m["layout"], out, extra)


if __name__ == "__main__":
    import make_biomes
    build_all(make_biomes.build, make_biomes.BIOMES)
