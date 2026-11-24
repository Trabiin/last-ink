#!/usr/bin/env python3
"""Chapter 3's story maps (issue #29): set pieces on the Causeway region's biome maps from tools/make_biomes.py.

Like tools/make_chapter2.py: each map is a biome layout with the story's places put down by hand, and its @spot
lines are what the story missions' steps (data/missions.json, objective kind "script") point at.
    ch3_quay        Lantern Quay bitten in two, where Saffron sings a bridge (The Singer on the Quay)
    ch3_masquerade  the Velvet Causeway's bridges, great hall and balcony (The Masquerade)
    ch3_shallows    Pendower Shallows' word-nets and mud flats (Shadow and Debt)
    ch3_wharf       the smugglers' wharf after midnight and the Concord barge (The Night Wharf)
The boss arena (maps/causeway_banquet.txt) is hand-made, like the Abbot's cloister.

Run through make_biomes.py (it calls build_all), or on its own:
    python3 tools/make_chapter3.py
"""

# Extra prop chars (lowercase, so they never clash with a biome's own) -> prop kind.
SET = {"j": "dock", "x": "crates", "w": "barrels", "q": "banner", "l": "lamppost", "t": "townhall", "m": "mask_stall",
       "d": "house_d", "i": "house_e"}

MAPS = {
    "ch3_quay": {
        "biome": "causeway", "layout": "b", "name": "Lantern Quay: the Broken Wharf", "blank": 70,
        "sign": "LANTERN QUAY|Barges unloaded. Questions not.|Lamps lit at dusk, mostly.",
        "marks": [("quay", (36, 30)), ("bridge", (48, 40), 2), ("far", (58, 42))],
        "setpiece": [("j", (44, 44)), ("j", (52, 44)), ("x", (40, 34)), ("w", (34, 26)), ("l", (46, 36)), ("l", (50, 36))],
    },
    "ch3_masquerade": {
        "biome": "causeway", "layout": "c", "name": "The Velvet Causeway: the Masquerade", "blank": 77,
        "mood": "grade=0.92,0.84,1.0 mist=0.8 motes=1.0,0.85,0.6",
        "sign": "THE MASQUERADE|Which continues.|Masks to be worn at all times.",
        "marks": [("bridges", (30, 18)), ("hall", (50, 30), 2), ("balcony", (56, 22), 2)],
        "setpiece": [("t", (50, 24)), ("q", (44, 26)), ("q", (56, 27)), ("l", (40, 30)), ("l", (60, 30)), ("m", (36, 22)), ("m", (46, 36))],
    },
    "ch3_shallows": {
        "biome": "lakeshore", "layout": "b", "name": "Pendower Shallows: the Word-Nets", "blank": 70,
        "mood": "grade=0.9,0.92,1.0 mist=1.8 motes=1.0,0.95,0.8",
        "sign": "PENDOWER SHALLOWS|Words netted, gutted, sold.|By the pound only.",
        "marks": [("nets", (34, 30)), ("flats", (50, 36))],
        "setpiece": [("j", (36, 34)), ("j", (42, 35)), ("x", (31, 27)), ("w", (38, 27)), ("q", (46, 32))],
    },
    "ch3_wharf": {
        "biome": "causeway", "layout": "a", "name": "Lantern Quay after Midnight", "blank": 74,
        "mood": "grade=0.6,0.62,0.88 mist=1.5 motes=0.9,0.7,0.45",
        "sign": "SMUGGLERS' WHARF|No lamps after midnight.|By order.",
        "marks": [("warehouses", (36, 30)), ("barge", (54, 32), 2), ("crates", (48, 28), 2)],
        "setpiece": [("j", (52, 36)), ("j", (57, 36)), ("j", (62, 36)), ("x", (46, 26)), ("x", (49, 26)), ("w", (44, 30)), ("d", (34, 24)), ("i", (40, 24))],
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
