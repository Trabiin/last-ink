#!/usr/bin/env python3
"""Chapter 4's story maps (issue #30): set pieces on the coast biome's maps from tools/make_biomes.py.

Like tools/make_chapter3.py: each map is a biome layout with the story's places put down by hand, and its @spot
lines are what the story missions' steps (data/missions.json, objective kind "script") point at.
    ch4_harbour   Trevail Harbour under the stopped wave: the slipway, the quay and the bell tower (The Wave at Trevail)
    ch4_mirror    Halfwave Bay's strand under the standing tideline, and the roofless chapel (The Knight in the Glass)
    ch4_light     the cliff path up to Polgarrow Light and its lamp room (The Keeper's Voice)
The boss arena (maps/coast_seabed.txt) is hand-made, like the Host's banquet.

The lighthouse is a tracked placeholder prop (data/placeholders.json prop:lighthouse); the rest are existing props.

Run through make_biomes.py (it calls build_all), or on its own:
    python3 tools/make_chapter4.py
"""

# Extra prop chars (lowercase, so they never clash with a biome's own) -> prop kind.
SET = {"j": "dock", "x": "crates", "w": "barrels", "q": "banner", "c": "chapel", "d": "house_d", "i": "house_e",
       "a": "roadlamp", "n": "ruin", "g": "grave", "h": "lighthouse", "p": "planks"}

MAPS = {
    "ch4_harbour": {
        "biome": "coast", "layout": "b", "name": "Trevail Harbour, under the Wave", "blank": 70,
        "mood": "grade=0.86,0.96,1.02 mist=1.1 motes=0.9,1.0,1.0",
        "sign": "TREVAIL HARBOUR|Harbourmaster: L. Pascoe.|Boats out: 21.",
        "marks": [("quay", (36, 32)), ("bell", (50, 22), 2)],
        "setpiece": [("c", (50, 18)), ("j", (38, 38)), ("j", (44, 38)), ("x", (32, 28)), ("w", (40, 28)), ("d", (28, 22)),
                     ("i", (60, 26)), ("q", (46, 24))],
    },
    "ch4_mirror": {
        "biome": "coast", "layout": "c", "name": "Halfwave Bay: the Strand", "blank": 72,
        "mood": "grade=0.9,0.98,1.04 mist=1.6 motes=1.0,1.0,0.95",
        "sign": "HALFWAVE BAY|Do not touch the sea.|It is resting.",
        "marks": [("strand", (34, 26)), ("chapel", (50, 38), 2)],
        "setpiece": [("c", (50, 34)), ("g", (44, 38)), ("g", (56, 38)), ("g", (46, 42)), ("n", (30, 32)), ("p", (40, 30)),
                     ("w", (26, 20))],
    },
    "ch4_light": {
        "biome": "coast", "layout": "a", "name": "Polgarrow Light", "blank": 69,
        "mood": "grade=0.82,0.9,1.02 mist=1.3 motes=0.9,0.95,1.0",
        "sign": "POLGARROW LIGHT|Keeper: J. Hocking.|Gannets nesting: keep to the path.",
        "marks": [("path", (32, 30)), ("tower", (48, 26), 2), ("lamp", (56, 22), 2)],
        "setpiece": [("h", (56, 18)), ("a", (40, 28)), ("a", (50, 30)), ("n", (44, 22)), ("x", (60, 24))],
    },
}


def build_all(build, biomes):
    for out, m in MAPS.items():
        b = biomes[m["biome"]]
        used = {c for c, _ in m["setpiece"]}
        extra = {
            "name": m["name"], "sign": m["sign"], "seed": 13,
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
