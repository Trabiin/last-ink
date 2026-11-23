#!/usr/bin/env python3
"""Chapter 2's story maps (issue #28): set pieces on the Abbey region's biome maps from tools/make_biomes.py.

Like tools/make_personal.py: each map is a biome layout with the story's places put down by hand, and its @spot
lines are what the story missions' steps (data/missions.json, objective kind "script") point at.
    ch2_candleford  Candleford's wax jetty, where the Erasers are burning the barges (The Wax Barges)
    ch2_hall        Saint Ledger's: the cloister walk and the copying hall's lecterns (The Copying Hall)
    ch2_crypt       the Bonefield Cloister: the Erasers' camp, the charnel chapel, the crypt stair, the
                    Founders' Door and the bone chamber where Verity waits (The Crypts)
The boss arena (maps/abbey_cloister.txt) is hand-made, like the Auditor's tollgate.

Run through make_biomes.py (it calls build_all), or on its own:
    python3 tools/make_chapter2.py
"""

# Extra prop chars (lowercase, so they never clash with a biome's own) -> prop kind.
SET = {"h": "chapel", "c": "candles", "g": "grave", "u": "ruin", "x": "crates", "w": "barrels", "j": "dock",
       "q": "banner", "y": "yew", "s": "seized"}

MAPS = {
    "ch2_candleford": {
        "biome": "lakeshore", "layout": "a", "name": "Candleford: the Wax Jetty", "blank": 74,
        "sign": "CANDLEFORD|Candles, tapers, rushlights.|Abbey orders paid at Michaelmas.",
        "marks": [("town", (30, 31)), ("jetty", (44, 31)), ("barge", (52, 33), 2), ("north", (58, 12))],
        "setpiece": [("j", (52, 36)), ("j", (57, 35)), ("x", (48, 29)), ("w", (56, 29)), ("x", (46, 35)),
                     ("c", (40, 28)), ("c", (40, 34)), ("s", (60, 30))],
    },
    "ch2_hall": {
        "biome": "abbey", "layout": "b", "name": "Saint Ledger's Abbey: the Cloister Walk", "blank": 74,
        "mood": "grade=0.84,0.84,0.98 mist=1.0 motes=1.0,0.88,0.6",
        "sign": "SAINT LEDGER'S|The house keeps silence.|The house keeps copying.",
        "marks": [("gate", (24, 42)), ("walk", (36, 30)), ("hall", (46, 22)),
                  ("lectern_w", (42, 16), 2), ("lectern_n", (50, 15), 2), ("lectern_e", (54, 22), 2)],
        "setpiece": [("h", (46, 13)), ("c", (40, 16)), ("c", (52, 14)), ("c", (56, 21)), ("q", (32, 28)), ("q", (40, 28)),
                     ("g", (30, 34)), ("g", (34, 34)), ("y", (26, 26))],
    },
    "ch2_crypt": {
        "biome": "abbey", "layout": "c", "name": "The Bonefield Cloister", "blank": 77,
        "mood": "grade=0.78,0.8,0.92 mist=1.8 motes=0.85,0.85,0.8",
        "sign": "THE BONEFIELD|The Ledger records|that this hill was always empty.",
        "marks": [("camp", (30, 18)), ("chapel", (46, 24)), ("stair", (46, 32)), ("ossuary", (48, 42)),
                  ("door", (56, 47), 2), ("chamber", (64, 50), 2)],
        "setpiece": [("h", (46, 20)), ("s", (28, 15)), ("s", (33, 15)), ("x", (26, 21)), ("q", (31, 22)),
                     ("u", (52, 40)), ("u", (44, 44)), ("g", (54, 44)), ("g", (59, 44)), ("u", (60, 52)), ("u", (67, 52)),
                     ("c", (62, 47)), ("c", (66, 47))],
    },
}


def build_all(build, biomes):
    for out, m in MAPS.items():
        b = biomes[m["biome"]]
        used = {c for c, _ in m["setpiece"]}
        extra = {
            "name": m["name"], "sign": m["sign"], "seed": 11,
            "props": {k: v for k, v in SET.items() if k in used},
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
