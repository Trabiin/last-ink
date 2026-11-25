# Last Ink: Design Document

> An action RPG in the spirit of 90s Secret of Mana and Final Fantasy, fused with empire management:
> you hold the last written town against a hungry Blank, recruit dozens of misfits to run it, and lead a
> party into the field on missions. Modern quality of life. Weird, dark, funny. Rated Mature.
>
> Title: **Last Ink**. Repo: `Trabiin/last-ink` (renamed from `blank-rpg`).

---

## 1. Pillars

1. **Two halves, one fight.** Running the empire and going on missions are an even split, and each feeds the
   other: missions reclaim land, find recruits and loot; the empire turns that into Ink, wards, gear and new missions.
2. **Real-time party combat that feels good.** Snappy movement, a weighty swing, readable enemy tells.
3. **No ring menus, ever.** Hotkeyed abilities plus clean list-based menus. Every action is two presses or fewer.
4. **A world that is visibly being eaten.** The Blank is on the territory map and on the mission maps. It moves on
   a clock, it moves faster when you neglect things, and it takes what you built.
5. **People are the resource.** About 50 recruits, each good at something. Who you put where matters more than
   any number in a menu, and about 20 of them are people you get to know properly.
6. **Dark, but with a grin.** Grim stakes, mercenaries who bicker, villains who are sometimes right.
7. **Respect the player's time.** Save anywhere, autosave, adjustable speed and difficulty, the clock never runs
   while you are in a fight, no random encounters. MVP about 4 hours; full game 15 to 20 hours.

## 2. Platform and tech

| Topic | Decision |
|---|---|
| Engine | Godot 4.3 (GDScript) |
| Main target | Web (HTML5), auto-built and published to GitHub Pages on every push to `main` |
| Testing device | Chromebook in Chrome; must run well on modest hardware |
| Resolution | 640x360 base, integer-ish scaling, pixel art filtering off |
| Input | Keyboard, gamepad, and touch (on-screen stick plus buttons, shown only on touch devices) |
| View | Top-down 3/4 perspective (Mana-like), Y-sorted |
| Repo | Public on GitHub under Trabiin |

Web builds use Godot's single-threaded export, so they run on GitHub Pages without special server headers.

## 3. Art plan (no hand-drawn art from the owner)

| Layer | Source |
|---|---|
| Tiles, props, enemies, base animations | CC0 pixel packs (Kenney, OpenGameArt CC0 only). Every pack logged in `CREDITS.md` with link and license |
| Heroes | Modular "paper doll" sprites: one shared animated body rig, swappable hair/outfit/weapon layers, **recolored in code** with palette swaps. Every hero animates the same way but looks distinct |
| Portraits | AI-generated stills for dialogue and menus, one consistent style prompt, cleaned up per hero |
| FX and UI | Drawn in code (slashes, damage numbers, the Blank's static, menus) |

**Status (art feasibility pass):** the meadow now uses ArMM1998's CC0 Zelda-like overworld tiles, graded darker
by a shader, and the Blank drains them to paper-white as it approaches. Heroes use Shade's CC0 *Puny Characters*:
`tools/import_art.py` diffs each class sheet against the bare body sheet to produce separate outfit layers, and a
palette-swap shader recolors the body and outfit per hero (skin, cloth, metal, accent...). Every hero shares the
same 8-direction walk, swing, hurt and knockdown animations. Nibblers are Puny's slime recolored to blank-white.
Ash = body + archer layer in indigo; Bran = body + warrior layer in bronze and rust.

## 4. Game structure: Command and Missions

The game alternates between two layers that share one save, one roster and one clock.

| | **Command** (empire) | **Missions** (action RPG) |
|---|---|---|
| Where | Hollowmark (a small walkable hub town) and the **territory map** | Hand-built mission maps in the provinces |
| Clock | Runs in real time (adjustable speed, pausable) | **Frozen.** No timers move while you are on a mission |
| You do | Build, assign recruits, research, send expeditions, negotiate, answer Blank surges, talk to people | Fight with a party of 3, reclaim land, rescue recruits, story chapters and bosses |
| Menus | List menus and panels from the Command Table, hotkeys for common actions | Pause menu, quick menu, hotkeyed abilities |

**The loop.** Check the territory map, see where the Blank is pushing, spend resources and staff to shore things
up, pick a mission, play it, come back with loot, land and maybe a new recruit, repeat. Story chapters are
missions too: they unlock on the map when you have met their conditions (renown, a building, a province held).

**Why the hub is walkable.** Hollowmark is where the roster lives. Recruits you have placed show up at their posts
(the forge, the infirmary, the tavern), so the town visibly fills up as you grow, and talking to people is how the
relationship side happens. Anything you can do on foot you can also do from the Command Table menus, so walking is
never required.

## 5. Empire management

### 5.1 The clock

- While in Command, the **day clock** runs in real time: 1 in-game day is about 4 real minutes at normal speed.
- Speed controls: **pause, 1x, 2x, 4x**, on hotkeys and on screen. Pausing is free and unlimited.
- Construction, research, expeditions, envoy trips and the Blank all advance on this clock.
- **On a mission the clock is frozen.** Leaving for a mission and coming back costs no time.
- Mission availability can still expire on the clock (a Blank surge you ignore for two days resolves without you).

### 5.2 The territory map

The Inklands are split into **provinces**, connected by roads: **24 provinces in five regions** (issue #53). The
Brack Marches (Act 1, nine provinces round Hollowmark) are open from the start; the other four regions lie under
fog, each showing its name, the chapter that opens it and a rumour of what is there, until its story chapter lifts
the fog (`Empire.open_region()`, or a story beat with `then: open_region:<id>`):

| Region | Chapter | Provinces | Notes |
|---|---|---|---|
| The Brack Marches | 1 (open) | Hollowmark, Frayed Meadow, Gutterwoods, Old Mill Crossing, Wickham Hills, Saltreed Marsh, Gallows Ferry, Tithe Road, Whitewater | Act 1, unchanged |
| Saint Ledger's Abbey | 2 | Saint Ledger's Abbey, Candleford, Bonefield Cloister, Scarth Pass | North, across the Candle Sound from the capital |
| The Velvet Causeway | 3 | The Velvet Causeway, Lantern Quay, Pendower Shallows, Vauclair Terraces | South-west, round the ink lake |
| The Unfinished Coast | 4 | Trevail Harbour, Halfwave Bay, Polgarrow Light | South-east, next to the Blank; region pressure +1 Fray a day ("the sea forgets itself") |
| The Gilded Spire | 5 | The Gilded Spire, Ledsham, Tollmarch, Goldwash Fields | West, the capital at the end of the Tithe Road |

The Margin (Chapter 6) is the Blank itself: the white wall down the map's east edge, not a set of provinces.

Under the fog nothing moves: no Fray, no missions, no claims, no surges or Verity's plans. Once open, a region
joins every system (the Blank's spread from the east, surges, plans, governors, claims). Holding more than nine
provinces costs 1 Gilt and 1 Supplies a day for each one past nine (garrisons and roads), which Act 1 can never
reach. Each province has a biome; each biome has a pool of mission maps (`data/provinces.json`), which the chapters
and #113 fill for the new regions.

The map is the painted Inklands with the provinces as translucent washes over it. It pans and zooms (mouse wheel,
drag, pinch, + and -, the right stick and LT, the buttons in its corner) and follows the selection; zoomed right
out over several open regions, region names take over from province names.

Each province shows:
- **Fray** (0 to 100): how far the Blank has eaten into it. At 100 it is **Erased**: it turns paper-white,
  stops producing, and anything built there is lost. Recruits stationed there flee back to Hollowmark, hurt.
- **Owner**: yours, unclaimed, a faction's, or erased.
- **Output**: what it gives per day when you hold it (Gilt, Supplies, sometimes Ink).
- **Governor** slot and one or two **site** slots (a mine, a lamp post, a shrine) that can be developed.
- Available **missions**, marked with an icon and, if timed, a countdown.

### 5.3 The Blank

The Blank advances on its own and gets worse when you give it openings:

- **Base spread:** every province bordering the Blank gains Fray each day.
- **Faster when:** a province has no governor, sits next to an erased province, has unrepaired damage from a
  surge, or when a story choice or Verity's plans aim it there. Each source is listed in the province panel, so the
  player can always see *why* it is moving.
- **Verity's plans:** every week or so Verity aims the Blank at one province for a few days (chalk lines on Concord
  land, surveyors on yours, erasure notices in Hollowmark). Each plan is a listed Fray source with its counter (a
  governor halves it, a Wardlamp cancels it) and a chalk ring on the map. Data: `data/blank.json`; story beats call
  `Empire.add_pressure()`.
- **Slower when:** a governor with good Grit is posted, a **Wardlamp** burns there, or research says so.
- **Surges:** every few days the Blank lunges at one province. It appears as a timed **Defense mission**. Win it to
  knock that province's Fray down; ignore it and the Fray jumps.
- **Reclaiming:** an erased province can be taken back with a **Reclaim mission** (fight to the Blot at its heart
  and break it) plus an Ink cost to rewrite the land.
- **Losing:** if Hollowmark itself is erased, the game is over (reload). Losing other provinces hurts but is
  recoverable, which keeps the pressure real without being a fail-state treadmill.

### 5.4 Resources

Three resources, kept deliberately few:

| Resource | From | Spent on |
|---|---|---|
| **Gilt** (money) | Province output, the Market, mission loot, trade deals | Construction, hiring, gear, bribes |
| **Supplies** | Province output, expeditions | Recruit upkeep (each recruit eats), construction, expeditions |
| **Ink** | The Inkworks, reclaimed provinces, rare mission finds | Rewriting reclaimed land, Wardlamps, research, top-tier gear |

Plus **Renown**, a meter that only goes up: it grows with missions, holdings and story, and unlocks recruits,
faction interest and story chapters.

### 5.5 Recruits and roles

About **50 recruits** in the full game (about 12 to 15 in the MVP). Everyone has four stats and one or two traits:

- **Might** (fighting, defense), **Craft** (building, forging, production), **Lore** (research, Ink, the
  Blank), **Charm** (diplomacy, trade, morale). Plus **Grit**, a hidden-ish modifier for holding a Blank-touched
  province.
- Traits change outcomes in readable ways: *Greedy* (+Gilt, -faction standing), *Night Owl*, *Ink-sick*,
  *Ex-Concord*, *Flirt*, *Coward*, and so on.

A recruit can hold **one role at a time**:

| Role | What it does |
|---|---|
| **Party** | Fights on missions. Only recruits with a combat kit can do this (about 12 in the full game, 4 in the MVP) |
| **Governor** | Runs a province: raises its output and slows its Fray, based on stats and traits |
| **Staff** | Works a building in Hollowmark (each building has 1 to 3 slots); stats drive the building's effect |
| **Expedition** | Goes on an off-screen squad mission (below) |
| **Researcher** | Works in the Scriptorium; Lore drives research speed |
| **Envoy** | Represents you with a faction; Charm drives results |

Recruits come from story missions, rescue missions, reclaimed provinces, the Guildhall (hire for Gilt),
buildings that attract certain people (open a cabaret and singers come), and faction deals.

**Governors in the MVP** (numbers in `scripts/empire.gd` and `data/provinces.json`): each province **wants** one
stat (Hollowmark Charm, Old Mill Craft, Wickham Lore, the Meadow and Saltreed Grit, and so on). A governor with 7+
in it is a **good fit** (+50% of the province's output, Fray 1 slower); 3 or less is a **poor fit** (-25%, Fray 1
faster). On top of that Grit slows Fray, Charm adds Gilt, Craft adds Supplies, and traits chip in (Stubborn,
Coward, Greedy, Ink-sick, Ex-Concord). A province you hold with **no governor** frays +3 a day and delivers 25%
less. **Claiming:** an unclaimed province next to your land can be claimed from the Command Table (G) for Gilt and
Supplies; someone has to go and run it, so every claim costs a recruit. Faction land waits for diplomacy, erased
land for Reclaim missions.

### 5.6 Buildings (Hollowmark)

Built and upgraded from the Command Table; each appears in the walkable town when finished.

| Building | Effect | MVP |
|---|---|---|
| **Command Table** | The territory map and all management menus | Yes (from the start) |
| **Barracks** | Party training (XP over time for benched fighters), more party options | Yes |
| **Infirmary** | Heals injured recruits faster; staff with Lore | Yes |
| **Inkworks** | Produces Ink; output scales with Craft staff and Ink provinces held | Yes |
| **Scriptorium** | Research | Yes |
| **Guildhall** | Hire recruits, launch expeditions | Yes |
| **Market** | Gilt income (level, trader Charm, provinces held), a rotating shop of supplies, materials and gear that changes every 3 days, buys materials; Charm cuts prices. Tobble's Stall stays the starter shop | Yes (#112) |
| **Forge** | Upgrades each hero's weapon through 6 tiers, makes armour, trinkets, field supplies and satchel upgrades from mission materials; Craft shortens every job | Yes (#112) |
| **Tavern / Cabaret** | Morale, relationship scenes, attracts certain recruits | Later (tavern is walkable from the start) |
| **Wardlamp** (built in a province) | Slows Fray there | Yes |

How it works in the MVP (numbers in `data/buildings.json`): every building has 3 levels, each costing Gilt,
Supplies and sometimes Ink, and taking 1 to 4 days on the clock. Hollowmark has **one building crew**, so only
one building is built or upgraded at a time; Wardlamps are put up by locals and can go up alongside. Each level
adds staff slots, and one stat drives each building: Command Table (Craft: quartermaster cuts upkeep; levels
give earlier surge warnings), Barracks (Might: party max HP on missions), Infirmary (Lore: faster healing),
Inkworks (Craft: Ink per day, needs a worker), Scriptorium (Lore: Insight banked for research, Bookish counts
double), Guildhall (Charm: contract Gilt; each level lets one more expedition squad be out at once; hiring arrives later). Wardlamps
have 2 levels (-1 and -2 Fray a day) and go out if their province is erased.

### 5.7 Expeditions

Send a squad of 2 to 4 recruits on a timed off-screen mission: scouting, salvage, escort, a supply run, a rescue.
Before sending, the panel shows the **success chance** and what drives it (stats, traits, pairings). Results come
back as a short written report, often funny, sometimes grim: loot, recruits, injuries, rarely a loss. Expeditions
are how the non-fighters see the world and how the player gets value from a big roster without playing every
mission by hand.

**Expeditions in the MVP** (jobs in `data/expeditions.json`, rules in `scripts/empire.gd`, screen E): the Guildhall
offers about 8 jobs tied to provinces (forage, salvage, escort, scouting, three rescues that bring in Mother
Gristle, Sister Hild and Corporal Daro, and a deadly Ink run at the erased edge). Each job wants one or two
stats; squad strength is the sum of those stats over the two strongest members plus half for each extra member, and every point above or below the job's target
moves the chance 4% from 50% (5% to 95%). Traits and pairings add or subtract (Coward on dangerous jobs, Night Owl
on scouting and rescues, Ink-sick near the Blank, Ex-Concord on Tithe Road, Bran and Daro together, Quill and
Tobble bickering). Rations cost Supplies per person. People on an expedition leave their job and town until they
are back. One squad out per Guildhall level. Success pays the job's reward (a fifth of the time half again);
failure pays a quarter and hurts people; on deadly jobs a failed squad can lose a light recruit for good (core
and field characters come back badly hurt instead). Every return writes a short report.

### 5.8 Research

A small tree in the Scriptorium with four branches: **Wardcraft** (Fray resistance, Wardlamps, reclaim costs),
**Logistics** (upkeep, expedition speed and odds), **Inkcraft** (abilities and Ink magic for the party), **Arms**
(gear tiers). About 12 nodes in the MVP, about 40 in the full game.

**As built (MVP, PR for #48):** 4 branches of 3 nodes, each a chain (data/research.json; screen on T). A node costs
Insight (the top tier also Ink and Scriptorium level 2), paid once when you first start it. Study then runs on the
Command clock: 2/3/4 days at 100% pace, and pace is 100% + 5% per point of researcher Lore (Bookish counts double)
+ 25% per Scriptorium level past 1. One node at a time; switching sets the old one aside with its progress kept.
No researcher at work = stalled. Effects: Wardcraft (Fray -1 in every held province; Wardlamps -1 more; surges
warned a day sooner and hit for 8), Logistics (upkeep -1 per 4 people; expeditions 25% shorter; +10% expedition
odds), Inkcraft (+1 Ink at the Inkworks; faster revives; -25% damage taken on missions), Arms (+2 damage; +10 max
HP; +3 damage and a faster attack gauge). Reclaim costs and Ink abilities join these branches once #51 and #7 exist.

### 5.9 Diplomacy

Factions each have a **standing** with you (hostile to allied). Envoys can open trade, ask for aid during a surge,
buy peace, or gather intel. Factions also react to what you do on missions.

| Faction | Wants | MVP |
|---|---|---|
| **The Gilded Concord** | You registered, taxed, or dissected | Yes (hostile) |
| **The Mercenary Guild** | Paid | Yes |
| **The Gutterwood Coven** | Left alone, and the Blank kept out of the woods | Yes |
| **Saint Ledger's Abbey** | Copies of everything | Later |
| **The Velvet Nobility** | Entertainment and leverage | Later |
| **The Erasers** (Verity's followers) | A clean page | Later |

**As built (MVP, PR for #49):** data/factions.json; screen on F. Standing runs -100 to +100 in five tiers: Hostile,
Wary (-39), Neutral (-9), Friendly (20), Allied (60). Start: Guild +5, Coven -15, Concord -55. One **envoy** per
faction (a recruit role; they live with the faction, away from Hollowmark) wins standing every day: 1 + Charm/3
(Flirt doubles Charm), +1 if the stat the faction respects is 7+ (Guild Might, Coven Lore, Concord Charm), -1 if 3 or
less; Greedy -1, Ex-Concord -2 with the Concord, Contracted +1 with the Guild, Ink-sick +1 with the Coven. The
Concord files against you (-1 a day, down to -80) unless someone is posted there. **Deals** (all need an envoy):
gift (any tier, coin for +8/+10 standing), intel (Neutral: Insight and +1 day of surge warning for 5 days), trade
pact (Friendly: daily Gilt/Supplies/Ink in the ledger, torn up if standing drops below 0), aid (Friendly, while a
surge gathers against your land: it lands at half, -15 standing), cede (Allied, Guild and Coven only: their
province becomes yours, -30 standing, then it needs a governor). **Friendly perks:** Guild +10% expedition odds,
Coven -1 Fray a day on your land next to the Gutterwoods, Concord stops auditing and +2 Gilt a day. **Trouble:** a
Hostile Concord fines you, seizes Supplies or reads Erasure writs (+6 Fray) every 4-6 days; Wary, it only fines,
every 7-9 days. **Reactions:** claiming land next to the Coven (-6) or Concord (-4), land next to the woods being
erased (Coven -10), a Wardlamp lit next to the woods (Coven +4), and expeditions: the Guild barge escort (+6, -3
on failure), finding the hedge-witch before the Coven does (-8), springing Daro from the Concord (-8). Story
missions will call the same hook (Empire.faction_react) once they exist.

**Faction asks (#131):** each faction you know of asks one favour at a time (data/factions.json `asks`,
scripts/faction_asks.gd). The first comes 2-4 days after the Command Table opens, then 3-5 days after each one
ends. It arrives as a notice that goes to Diplomacy (F), where it waits 3 days for an answer: accept, or refuse
(-2 to -4 standing; leaving it unanswered counts as refusing). Accepted, it has a deadline (5-10 days) and a
reward (standing plus resources, Forge materials, a boon or a recruit at the gate early); missing it costs more
standing and sometimes more (a Guild fine, Concord trouble at dawn, a Coven hex of +2 Fray a day that a Wardlamp
burns off). Asks depend on standing tier (some only while things are bad, like the Concord's back-tithe) and come
in seven kinds: request-only **expeditions** that appear on the Guildhall board while accepted, **raids** on a rival's
land, **salvage** runs, **holding Fray** under a line on your land by their home, **lighting a Wardlamp** there,
**handing over** resources from Diplomacy, and **promises** not to trade with a rival. MVP: Guild 4 (Saltreed barge,
raid the Concord, ferry dues, lend blades: brings Jessamy), Coven 5 (treeline Fray, lamp by the woods: brings Mr.
Biscuits, fallen letters, no Guild pact, salvage the hedge-books), Concord 5 (back-tithe, census, no Guild pact, audit a Guild cargo, keep the
road towns standing). The journal's Factions section lists the offer and the accepted ask with a countdown and
show-on-map; History keeps how each ended. New factions from #54 add their own asks in the same file.

### 5.10 Relationships

About **20 core characters** (all the combat heroes plus the most important staff) have relationships:

- A **bond rank** (0 to 5) that rises from missions together, conversations in Hollowmark, choices, gifts and
  having them in roles they like.
- Each rank unlocks a short scene, and higher ranks unlock a perk (a combat technique, a building bonus) and a
  **personal mission**.
- Some bonds can turn romantic (flirty, innuendo, never explicit), and some characters dislike each other:
  posting rivals together has effects, good or bad.
- Every core character gets an epilogue line that depends on their bond and fate.

**Built (`data/bonds.json`, Bonds screen on H):** ten bonds: Bran, Mother Gristle, Daro, Big Ottoline, Jessamy,
Odile and Fauvette (field) plus Quill, Tobble and Sister Hild (core staff). Ranks need 6/16/30/46/64 points. Points: +2 for the first chat of
the day in Hollowmark, +2 a day in a liked role, -1 a day in a disliked one, +2 for a successful expedition, +1 per
8 kills fighting beside Ash (max 4 per mission), and +0 to +3 from the one choice in each rank scene (Ash never
speaks; choices are gestures). Points never drop below the current rank and stop at the next rank until its scene
is seen: the person gets a heart over their head in town and "wants a word". Each person has five rank scenes
(replayable from the Bonds screen), perks at ranks 3 and 5 (mission HP/damage/revives/damage taken/gauge, healing,
expedition odds and speed, surge warning, daily Gilt/Supplies/Insight, Gilt per province held, study pace, cheaper
buildings, faction standing, Hollowmark Fray), and a **personal mission** on the Command Table at rank 4
(see 5.11); rank 5 needs it done. If the Blank erases the mission's province, rank 5 is out of reach until a Reclaim
mission brings the province back (Ojon, 2026-11-20: losing someone's home should cost something).
Scenes show the portraits (`assets/portraits/`) in a visual-novel layout; lines can ask for an expression, which
shows once #107 draws it. Each bonded hero also has a first chat in town and walking banter with other heroes
(`data/dialogue.json`).

The four 2026-11-20 heroes' arcs: **Ottoline** shut the Crimson Encore's door on six people to keep the Blank off
a hundred and six (personal mission: answer the knocking at that door, on Gallows Ferry). **Jessamy** paid a notary to strike
her out of the Ledger and has faded in daylight ever since (mission: make him write her back in, Tithe Road).
**Odile** found her own mother's countersignature on the order to collect Lowmere (mission: settle the account at Old
Mill). **Fauvette** killed eleven Concord-chosen "volunteers" on stage (mission: a last performance on her old
impresario's showboat in the Saltreed).

**Romance, rivalries and epilogues (#116, `data/relationships.json`, `data/epilogues.json`, `scripts/relationships.gd`,
`scripts/epilogues.gd`, `scripts/epilogue_view.gd`):**
- **Romance.** Fauvette, Jessamy, Odile, Daro and Big Ottoline can fall for Ash. After their rank 3 scene, once the bond
  reaches 38 points, they want one more word: an evening scene (listed as "3+" on the Bonds screen) where Ash either
  says yes (a romance) or stays a friend for good. Rank 4 waits for it. One romance at a time: saying yes to someone
  else is labelled "(ends it with X)" first, costs the ex 6 bond points (never below their rank), they say their
  piece next time Ash talks to them, and it can't be rekindled. While it lasts the partner's perk counts like a bond
  perk (faster revives, +5% expeditions, +3 Gilt a day, 5% less damage, +10 max HP), their daily chats change, and
  their rank 5 scene is a flirty variant. Never explicit: the camera leaves the room.
- **Friends and rivals.** Sixteen pairs (8 friends, 8 rivals) among the roster. Posted together (the party, the same
  building's staff, the same expedition) they change expedition odds (+/-5%), building output (+/-1), mission stats
  (rivals show off: more damage, but take more), and each of their bonds by +/-1 a day. Rivals who work together
  for 8-14 days make peace: a truce with its own, better effects, a notice and a journal entry. Pairs banter at the
  start of missions and in expedition reports. Shown up front on the staff picker, the Roster's role list, the
  expedition odds, the party picker and the Bonds screen.
- **Fates.** Per person: missions fought (and won), times badly hurt, lost in the white (day and job), personal
  mission tries and day done, and every choice Ash made in their scenes. The journal's People page lists them.
- **Epilogues.** One card per person at the ending: the first variant in `data/epilogues.json` whose conditions
  (romance, rank, personal mission, home province, missions, injuries, a scene choice, lost, a pair's state) hold.
  Every recruit has a list and a `default` covers anyone added later. The ending (#32) plays them with
  `EpilogueView.play(Epilogues.cards())`.

The other ~30 recruits are lighter: a trait, a couple of lines, a reason to recruit them, and a quip in
expedition reports.

### 5.11 Missions

| Type | What happens | Source |
|---|---|---|
| **Story** | Scripted chapter missions with dialogue and bosses | Unlock by story conditions |
| **Reclaim** | Push into an erased province, break the Blot | Any erased province |
| **Defense** | Hold a province against a Blank surge | Timed events |
| **Rescue / Recruit** | Find someone in a dangerous spot | Rumors, expeditions, factions |
| **Raid / Salvage** | Grab resources from a contested place | Map, factions |
| **Personal** | A core character's story | Bond rank |

**Built (issue #113, `scripts/mission_types.gd`, `data/mission_types.json`):** every province offers its types on
the Command Table, each briefing showing type, threat (1 to 5 with a name), rewards and expected enemies.

- **Raid** opens in a province a faction holds next to yours, for 3 days in every 5 (4-day cooldown after a run).
  Break at least 3 of 5 caches (Concord tithe-stores, Guild cargo, Coven stores) before the timer runs out. Guards
  stand watch; being seen or breaking boxes fills an alarm that, at full, calls reinforcements from the far edge.
  Standing with the owner drops a little if it stayed quiet and a lot if it went loud, and their rival likes you
  more. Friendly and Allied factions can't be raided. Cache loot tables are the hook for Forge materials (#112).
- **Salvage** opens in your provinces at 35+ Fray: grab at least 3 of 5 piles of goods before the Blank's edge creeps
  over them (faster at higher Fray). Piles near the edge are worth more.
- **Personal** (`scripts/personal_missions.gd`, `data/personal.json`): one hand-built mission per bonded character,
  offered at rank 4 in their home province, on a set-piece map from `tools/make_personal.py`. Field heroes are forced
  into the party (it is their fight); core staff (Quill, Tobble, Hild) come as an escort who can't fight and has
  to be kept alive (20 seconds to revive them if they drop). Each plays a script of steps (`scripts/mission_script.gd`:
  talk, go to, clear with an optional named elite, hold a spot or protect something, have someone work a spot,
  exit) with its own speakers, talks and portraits. Success opens the rank-5 scene and moves faction standing;
  failure can be retried. Blocked when the character is away, injured or tied up in another role.

**Meaning pass (Ojon 2026-11-25, "I don't feel anything about the choices"):**

- **Stakes on every brief.** A mission's `stakes` line (and a request's asker, what is at stake, what it costs if
  nobody goes, the days left and the rival it would leave) leads its briefing on the Command Table
  (`Missions.stake_lines`).
- **Requests (incidents)** (`scripts/incidents.gd`, `data/incidents.json`): someone with a name asks (a lamplighter,
  a schoolmistress, a shepherd, Gristle, Daro). The request sits on the territory map for a few days with a deadline
  tag; if nobody goes, what was at stake is lost for good (people, a province's Fray, supplies, a friend's bond).
  Some come in **rival pairs** that open on the same day: answering one lets the other lapse. The ask, the thanks and
  the consequence play as town beats. Six in Act 1, two of them pairs (the Gristle/Daro pair forces that hero into
  the party).
- **People** saved and lost are counted per group (`Incidents.people`) from lead steps and lapses, and story beats
  can ask about them (Story conditions `saved`, `lost`, `incident`, `chose`, `not_chose`, `not_joined`).
- **Set pieces with a choice.** The four Act 1 story missions (the tax office breakout, Gristle's tree, Daro's farm,
  Millbrook) run on premade maps from `tools/make_act1_maps.py` with a choice in the middle (people or money, the
  family or the evidence), branch steps (`"when"` on a step), a lead step (walk people to safety while the white or
  a press gang comes) and a beat back in town that remembers what you picked. Bonus pay or cost by choice
  (`"bonus"`). Gristle and Daro now join through their story missions (a campaign without the story keeps the
  old rescue expeditions through the join hook's `"free"`).
- **Premade layouts with enterable buildings** use the building kit (docs/MAP_KIT.md, `scripts/structures.gd`):
  walls, windows, doorways and roofs that fade while the hero is inside; allies and enemies path round walls
  (`scripts/paths.gd`).

Mission maps are text maps from `tools/make_biomes.py`: every biome has 3 layouts (a/b/c) with `@spot` lines for
the start, wardstone, Blot, rescue, caches and spawns. Each visit picks a layout, a subset of the spawns, shuffled
caches and a Blank edge moved a few tiles, so the same province plays differently each time.

## 6. Combat

**Real-time**, Mana-inspired, minus the ring.

- **Attack power gauge.** Each hero has a power gauge that refills after every swing (about 1.1 s). Swinging early
  still hits, but for proportionally less damage. A full gauge does full damage; a full gauge held for 1 s more
  becomes a **charged tech** (data/techs.json; allies fire theirs too, issue #108).
- **Abilities on hotkeys.** Each hero has up to 4 abilities mapped to keys 1-4 / gamepad shoulder + face buttons.
  Using one does not pause; it costs **Ink** (MP).
  **As built (#7):** data/abilities.json + scripts/abilities.gd. Each field hero has an Ink pool (10-14) that refills
  0.4/s and +1 per full-power hit that lands (Spring Tapping research: 25% faster). Two abilities each: Ash Rewrite
  (party heal + shield) and Strikethrough (dash), Bran Cleave (wide Red Ink arc) and Hold the Line (taunt + half
  damage), Gristle Poultice Toss and Scald, Daro Long Thrust and Pike Sweep. Keys 1-4, gamepad LB/RB/LT/RT, touch
  buttons around Attack. Allies fire them on simple rules (hurt ally, crowd, target in range, leader threatened).
- **Quick menu.** One button opens a list menu that slows time to 10% (not a full pause). Tabs: Items, Abilities,
  Party (swap leader, set AI behavior), Equip. Fully navigable by d-pad, mouse/touch, or hotkeys.
- **Party of 3.** You control one hero; two AI allies follow. Swap control instantly with one button.
- **Ally AI presets** (set per hero in the Party tab): *Aggressive*, *Balanced*, *Keep Distance*, *Support*. AI waits
  for a full power gauge before striking so allies hit meaningfully.
- **Visible enemies with tells.** Every enemy attack has a wind-up (flash or crouch) so dodging by movement is always possible.
- **Downed, not dead.** Heroes at 0 HP are downed and can be revived by items or by standing next to them for 3 s
  outside combat. If all three go down, you reload the latest autosave.

## 7. Progression

Party progression (per fighter), on top of the empire's own progression (buildings, research, provinces):

1. **Levels and gear.** XP raises HP, Ink and base stats. Gear: weapon, armor, one trinket per hero.
   MVP (issue #15, numbers in `data/gear.json`): every enemy gives XP to the whole party (a Blot gives more), a
   finished mission adds a bonus, and the Barracks drills benched fighters for XP each day. Each hero has their
   own weapon line (start weapon plus two upgrades, the best needing research); armor and trinkets fit anyone.
   Gear is bought at Tobble's Stall (K in town or on the Command Table, half price back when selling) or found
   on missions (rare drops, kept unless the party is wiped). Equip from the Gear screen (K, or Party gear in the
   pause menu mid-mission, where it applies at once). Consumables are the quick menu's satchel (#6).
2. **Weapon and Ink skill levels (Mana-style).** Using a weapon type or Ink color raises its skill level (cap 5),
   unlocking a charged tech per level for weapons, and stronger spell tiers for Inks.
3. **Per-hero skill trees.** Each hero has a small tree (about 10 nodes, two branches) bought with Skill Points from levels.
   Branches reflect personality (e.g. Bran: *Bodyguard* vs *Turncoat*).
   **As built (issue #25, `data/skill_trees.json`, `scripts/skill_tree.gd`, passives in `scripts/tree_perks.gd`):**
   every field hero has a root and two branches of five (11 nodes): Ash Author / Editor, Bran Bodyguard / Turncoat,
   Gristle Matron / Poisoner, Daro Corporal / Deserter, Ottoline Doorkeeper / Brawler, Jessamy Leake / Smuggler,
   Odile Assessor / Collector, Fauvette Duelist / Star. One Skill Point per level past 1 (19 at level 20); nodes cost
   1-3 and are bought in order; the last node of each branch is a capstone and a hero holds only one, so a
   max-level hero finishes one branch and most of the other. Step 4 needs bond rank Familiar, the capstone Trusted
   (Ash, who has no bond: 2 bonds at Familiar, then 3 at Trusted). Nodes add stats, change abilities (riders such as
   poison, leech, marks, taunts, Ink gifts, self-shields; wider, longer, quicker), add passives (bodyguard, evade,
   last stand, thorns, auras, kill rewards including Gilt into the loot, damage against the wounded / marked /
   stunned / unhurt, swing stuns, revive speed) and change who the ally AI goes for (wounded, marked, whatever is on
   the leader). Screen: Gear screen Tree tab (K) and the quick menu's Tree tab mid-fight (pauses); unlearning the
   whole tree costs 30 + 10 Gilt per point, at home only. The four later heroes get their trees in their chapters.

Weapon types: sword, axe, spear, rapier, crossbow, whip, knuckles, staff.
Ink colors (magic): **Red** (fire), **Blue** (frost), **Gold** (light, healing), **Green** (growth, poison),
**Black** (gravity, debuffs), **White** (only the Blank and its servants use it: erasure).

## 8. Quality of life

- **Save anywhere** (pause menu, three slots) plus **autosave** every minute when safe, on returning from a
  mission, and on quitting.
- **Clock speed** (pause, 1x, 2x, 4x) in Command; the clock never runs during missions.
- **Adjustable battle speed** (0.75x to 1.25x) and **difficulty** (Story, Normal, Hard), changeable at any time.
  Difficulty also scales the Blank's spread.
- **Objectives and alerts:** the current story goal is pinned; Blank surges, finished buildings and returning
  expeditions raise a notice with a "go there" button.
- **Journal** (I, rebindable; also in every menu and the mission pause menu; issue #114): **Quests** (the main
  story for the current chapter, personal stories, what each faction wants next, open and timed missions and
  Verity's plans, each with its next step and "show on map"), **People** (the roster, visitors, rumoured recruits
  with how to bring them in, and figures met who never join), **Codex** (places, factions, enemies with their
  weaknesses once beaten, the Blank, Ink colours; unlocked by meeting things, with live numbers) and **History**
  (a recap per chapter, every mission result and expedition report). Words in `data/journal.json`, so each chapter
  adds its entries without code; the tests fail if a region, faction, enemy or Ink colour has no codex entry.
- **Assign screens show consequences up front** (output, Fray slowdown, success chance) before you commit.
- **No random encounters.** Enemies are visible on the field and avoidable.
- Remappable controls, text speed, screen shake toggle, colorblind-safe telegraphs.

## 9. World

A **hub and territory map** instead of one connected overworld. Hollowmark is the hub. The rest of the world is
the territory map of provinces; you travel by picking a mission there. The Blank spreads from the east across that
map and into the mission maps themselves (its edge is visible in the field, as in the prototype). Erased provinces
can be reclaimed, so places you lost come back scarred.

**The setting: the Inklands.** A once-gaudy empire where reality is literally *written*. The ruling
**Gilded Concord** keeps the Great Ledger, and whatever the Ledger says is true. Debts are inked onto skin, history
is edited weekly, and inconvenient people are simply *struck out*. Everyone knows the system is rotten; most people
are too busy surviving to care. Then the Blank arrived: a white, silent nothing that eats whatever it touches, ink
and all.

### Regions

Each region is a group of provinces on the territory map, opened up roughly in story order.

| # | Region | Mood | Hook |
|---|---|---|---|
| 1 | **The Frayed Meadow** | Pastoral, wrong at the edges | Grass grows in half-sentences. Starting area and prototype map |
| 2 | **Hollowmark** (town) | Seedy market town | **The hub.** Mercenary guild, a tavern, the Concord's tax office until the Blank eats it |
| 3 | **The Gutterwoods** | Fungal, wet, whispering | Trees grow from discarded letters. Poisoners live here |
| 4 | **Saint Ledger's Abbey** | Gothic, candlelit | Monks who copy the Ledger by hand, forever, in blood |
| 5 | **The Velvet Causeway** | Decadent bridge-city on a lake of ink | Masquerades, duels, the Marquise's home turf |
| 6 | **The Unfinished Coast** | Half-erased shoreline | The sea stops mid-wave. Ships sail into white |
| 7 | **The Gilded Spire** | Capital, gold and rot | The Great Ledger itself. Concord's last stand |
| 8 | **The Margin** | Pure surreal void | Final dungeon inside the Blank |

## 10. Story

### Premise

Reality is being eaten by a hungry Blank spreading across the map. The Concord's answer is to write faster
("the Ledger says we are fine"). It does not work. Somebody has to actually hold the line, and the only person
free to do it is someone who, legally, does not exist.

### The protagonist: the Unwritten

Silent by design *and* by story. The protagonist was eaten by the Blank and, impossibly, **spat back out**, without
a name, a voice, or a Ledger entry. Officially they do not exist. Mechanically this means the Blank treats them
oddly: they can walk short distances into it, and the **Inkblade** they wake up holding can "re-write" small things
the Blank has taken. Other characters project wildly different personalities onto the silent hero, which is a
running joke. Default name: **Ash** (player can rename).

**Gestures, not words.** At choice points Ash *does* something instead of speaking: "[Shrug]", "[Hand Morrow the
empty strongbox]", "[Nail it back up, upside down]". Everyone present reads the gesture in their own voice. Each
gesture leans **mercy**, **hard-nosed** or **spite**; once one leads clearly it becomes Ash's lean, and the world
answers it: Bran's name for Ash ("smudge" until then; "saint", "boss" or "sparks"), what the townsfolk say as Ash
walks past, Verity's Act 1 letter, and the epilogues (including a card for Hollowmark itself). Some gestures also pay
off later on their own: sparing Tithe-Captain Morrow makes him a Concord informant in Chapters 2 and 3, and the other
two ways of dealing with him have their own Chapter 2 scenes. Gestures can also move bonds, faction standing and
resources. Data: `data/gestures.json`; code: `scripts/stance.gd`, `scripts/town_chatter.gd`.

### The villains: a duo

**1. Saint Verity Hale, "the Eraser"** (the sympathetic antagonist with a point)
Former Chief Archivist of the Great Ledger. She spent twenty years reading the *unedited* drafts: every massacre
the Concord wrote out of history, every family struck out for unpaid debt, every lie made true. She concluded the
world cannot be fixed by editing, because the editors are the disease. Her answer: **a clean page**. She opened the
way for the Blank and guides its hunger, aiming it at Concord strongholds first.

Her point lands: the Concord *is* monstrous, and the heroes will see it. She is polite, tired, funny in a dry way,
and genuinely mourns what she erases. She believes she will be the last thing eaten, and is at peace with it.

**2. The Vacancy** (the cosmic horror)
The Blank is the edge of something. The Vacancy is what exists in the space before anything was written: an
appetite that experiences existence as noise. It does not hate; it *corrects*. It speaks only in redacted text
(lines of black bars with the occasional terribly clear word). Verity thinks the Vacancy is a tool, a mercy with
no will of its own. She is wrong. It has been steering her the whole time, and it has no intention of stopping at
the Concord, or at the world. The Unwritten, spat back out, is the one thing it has ever *failed to digest*, and it
wants them back.

**Their dynamic:** Verity is the face the player argues with; the Vacancy is the shadow behind her that grows
more visible each act. The midgame twist is not that Verity is evil, but that she is losing control and refuses to
admit it.

### How the story fits the empire

The main story stays **linear**: chapters happen in a fixed order. What changes is that each chapter is a
**story mission** on the territory map, and between chapters the player runs Hollowmark, takes side missions and
fights the Blank at their own pace. A chapter unlocks when its conditions are met (for example: hold the
Gutterwoods, have an Infirmary, reach a renown level), so the empire side gates and paces the story without
branching it. Recruits named below are the story recruits; most of the ~50 come from the empire side.

The big structural addition is the end of Chapter 1: **Ash takes over Hollowmark**. The Concord's tax office is
eaten, the governor flees, and the town is leaderless. Nobody can legally run it, so the one person with no Ledger
entry ends up in charge, which the Concord considers a clerical nightmare and Bran considers a business opportunity.

### Outline (about 15 to 20 hours with the empire layer; the MVP covers the Prologue and Act 1)

**Prologue: Spat Out** (Frayed Meadow, ~10 min)
Ash crawls out of the Blank's edge. Nibblers (small hungry blank-creatures) attack. Brannoc Tolley, a mercenary
paid to "check out the static," finds Ash and decides an unregistered person is either worthless or priceless.
Tutorial: movement, attack, power gauge, swapping heroes. *(This is the current prototype.)*

**Chapter 1: No Such Person** (Hollowmark, ~30 min)
The Concord tax office cannot process someone with no Ledger entry, so Ash is arrested for "existing without
authorization." Bran breaks Ash out (for a fee, payable later). First glimpse of Verity, watching from the edge of
the Blank as it eats the tax office. The governor flees; Hollowmark is leaderless. **Ash takes the town.** The
Command Table, the territory map and the clock switch on here.

**Act 1 command phase** (~2.5 hours in the MVP)
Build up Hollowmark, take the provinces around it, answer surges, hire and place recruits. Story missions in this
phase: recruit **Mother Gristle** in the Gutterwoods (who heals the party and bills them for it), rescue
**Corporal Ninefingers** from a Concord press gang (moved up from Chapter 2), and deal with the Concord's answer to
an unregistered town. Act 1 ends with the boss **The Auditor**, a Concord enforcer who strikes people out with a
quill the size of a lance, sent to strike out Hollowmark itself. Verity sends a polite letter afterward. **MVP ends
here.**

**Chapter 2: The Copying Monks** (Saint Ledger's Abbey, ~30 min)
The monks are hand-copying the Ledger to "back up reality." It is not working; they are copying blank pages and
going mad. The Abbey can become an ally faction. Verity confronts the party here
for the first time and *does not fight*. She shows them an unedited page: the Abbey was built on a mass grave the
Concord wrote out. Boss: **The Abbot Who Copied Himself** (many copies, one real).

**Chapter 3: Masquerade** (Velvet Causeway, ~40 min)
The Concord's elite throw a masquerade while the city drowns in ink. Recruit **Hortense, the Velvet Marquise**
(duelist, flirt, obvious liar) and **Saffron Kiss** (stage name of Maud Pickering; cabaret singer whose voice makes things briefly real).
Optional recruit: **Nan Cripps & Tally**. Twist: Hortense is a Concord spy assigned to bring Ash in, because the Concord
wants to dissect the one person the Blank spat out. Player chooses dialogue tone, but the story stays linear;
Hortense stays (she has fallen for the party, or at least for their odds). Boss: **The Host**, a party guest who is
mostly mouth.

**Built (#29, on tracked stand-in art):** five story missions in four new Causeway provinces (Lantern Quay, the
Velvet Causeway, Pendower Shallows, the Vauclair Terraces), owned partly by the new **Velvet Nobility** faction
(patronage gilt when Friendly, wine-and-masks deals, four asks, fines and seizures as trouble). The Singer on the
Quay (Saffron joins), the Masquerade (needs the Terraces; Hortense joins, Verity watches from a balcony in a white
mask), the optional Shallows (Nan and Tally join), the Night Wharf (Hortense reads her Concord orders aloud to the
whole wharf and tears them up: the Office wanted Ash for study in exchange for her sister Bérénice's debts, and has
been feeding debtors to the Host), and the Host (needs Neutral with the Nobility). The Host fights at its banquet
table: a bite, a fan of shouted words, a breath that pulls heroes in and swallows its own guests to heal, a bell
for more guests; at half it unmasks and adds a gulp jump that leaves it stuck in the floor. The Vacancy's beat is
the two black bars under Verity's "that one was not mine" letter (ch3_end). New enemies: Masked Reveller, Bridge
Duellist, Ink Eel, Lamplighter. Three field heroes with full kits, bonds, romance (Hortense, Saffron), pair
banter, epilogues, techs, skill trees, weapons and personal missions. Hortense and Fauvette get their scene
(`ch3_two_rapiers`). Save step `20261126_chapter3` gives old saves the Nobility's Causeway. All stand-in art is
listed in `data/placeholders.json` and tracked in the Chapter 3 art swap issue.

**Chapter 4: The Sea Stops** (Unfinished Coast, ~30 min)
The Vacancy speaks for the first time, through a drowned lighthouse keeper, in redacted text. Recruit **Ilse of the
Mirror**, a knight who is actually a reflection that walked out of her mirror when the original was erased. Verity
realizes the Blank is eating places she did not aim it at. She does not tell anyone. Boss: **Low Water**.

**Built (#30, on tracked stand-in art):** four story missions on the three coast provinces (Trevail Harbour,
Halfwave Bay, Polgarrow Light), with Trevail owned by the new **Harbour Moot** faction (fishing families who vote
by show of hands; salt fish every day when Friendly, rope-and-catch deals, four asks, harbour dues and wreckers as
trouble). The Wave at Trevail (escort the harbourmaster to the bell and hold the tower while she rings eleven of
thirty-two boats home), the Knight in the Glass (needs Halfwave; Ilse steps out of the chapel's looking-glass and
joins), the Keeper's Light (needs a governor at Halfwave; the Vacancy speaks for the first time, in black bars,
through the keeper; Kerra joins; this mission starts the betrayal's foreshadowing, #186), and Low Water (needs
Neutral with the Moot). Verity's beat is "Elsewhere": chalk rings on her map she did not draw, a letter burned
unsent. Low Water fights on the dry sea bed: rolling swells down marked lanes, a fan of brine, a whirlpool that
drags heroes in, called waves; at half the tide turns and it sinks, the bay floods except for a few dry banks,
and it surfaces at a marked spot and lies beached (hits land 30% harder). The chapter ends with no letter, only
three black bars in the dust. New enemies: Stopped Wave (rears, crashes down a lane, lies as a puddle), Drowned
Netter (a tracking ring, then a net that slows), Half-Gannet (untouchable aloft, dives on a mark, sticks in the
sand), Salt Wight (crumbles into a heap on its first death and stands up again unless the heap is broken). Ilse is
a field hero with a full kit: Looking Glass (a parry, Blue) and Unwrite (White Ink, which only she can hold: a
line that takes the weak and any salt heap off the page, never a boss), five techs, a skill tree, six weapons, a
bond, romance, a rivalry with Hortense, a friendship with Jessamy, epilogues and a personal mission (the Hall of
Glass at Kernick Head). Light recruits Kerra Hocking (story) and Yann Le Goff (Friendly Moot). Story missions
gate on Renown from 62 to 74, continuing Chapter 3's. Save step `20261127_chapter4` gives old saves the Moot's
Trevail. All stand-in art is listed in `data/placeholders.json` and tracked in the Chapter 4 art swap issue.

**Chapter 5: The Gilded Spire** (~35 min)
The party storms the capital, alongside or against Verity depending on the scene (still linear). The Concord's
High Scribes try to write the Blank out of existence and instead get erased mid-sentence. Verity reaches the Great
Ledger and finally understands: the Vacancy was never her tool. It possesses her. Boss: **Verity, Unmade**, a
tragic fight where she resists the Vacancy between phases.

**Chapter 6: The Margin** (~25 min)
Ash leads the party into the Blank. Surreal final dungeon: places from earlier chapters, half-remembered, with
scenery written as words instead of pictures. Verity's surviving fragment helps from inside. Final boss: **The
Vacancy**, fought as a page that keeps erasing your HUD.

**Ending.** The last ink in the world goes into one final line. The Vacancy is driven back, not destroyed. The world is smaller, scarred, and *unwritten*: the Ledger
is gone, so nothing is true just because the Concord said so. Verity got her clean page, just not the way she
wanted it. Bran sends Ash an invoice.

### The betrayal (climax twist, decided 2026-11-21)

At the end of Chapter 5 one companion betrays Ash. Who it is depends on the player's empire and relationships.

**Motive.** The Vacancy keeps everything it has eaten. After Verity falls it makes one companion a fair offer:
hand over Ash, the one thing it failed to digest, and it writes their home back exactly as it was. The betrayer
is not evil. They are grieving, and the deal is real.

**Who: the leverage score.** Each candidate scores:
- home province erased right now: large plus (smaller if it fell once and was reclaimed);
- personal mission not done, or locked because the home is gone: plus;
- low bond rank, or an unresolved rivalry (no truce): plus;
- bond rank 5 or a current romance: large minus. A romance partner can still betray Ash, but only if their home
  is erased (Ojon, 2026-11-21): rare, and meant to hurt.

The top scorer betrays Ash if they clear a threshold. Candidates must be recruited and not lost in the white.
Neglect is punished, not affection: the player can see it coming and change it by reclaiming homes, finishing
personal missions and building bonds.

**Candidates (one per Marches home). First build ships Ottoline, Daro and Odile plus Bran (Ojon, 2026-11-21); Fauvette and Gristle follow:**

| Candidate | Home | The offer |
|---|---|---|
| Big Ottoline | Gallows Ferry | The six people she shut the Encore door on, back (her six coat-check tickets are the seed) |
| Daro | Tithe Road | The village they refused to strike, unstruck; or a Concord pardon if the Concord still stands |
| Odile | Old Mill | Her mother written back in, or her mother's skim written out |
| Fauvette | Saltreed | One last sale for a secret broker: Ash, to the highest bidder |
| Mother Gristle | Gutterwoods | The bill nobody paid, settled at last |

**Fallback: Bran.** If no one clears the threshold, Bran "sells Ash out", as he has promised since the Prologue.
It is a con on the Vacancy: his contract tattoo tightens and he does it anyway. This pays off into his invoice in
the ending.

**Decoy.** Hortense's Chapter 3 spy reveal makes her the obvious suspect. She never betrays Ash in the climax.

**Foreshadowing (Chapter 4 on).** The top candidate's banter gains redacted black-bar words; their "wants a word"
heart turns grey; Verity's letters mention them by name. One Verity plan in Chapter 4 aims the Blank at the top
candidate's home, giving the player a fair chance to defend it and lower the score.

**Payoff.** The betrayer opens the Margin and hands Ash over; Chapter 6 starts one hero short. Midway through the
Margin the betrayer is fought with their own kit (BossFight reusing the hero's abilities and tech) inside their
home written as words. Afterwards Ash chooses a gesture: take them back, or let them go. Fates record
`betrayed` / `redeemed` / `let_go`, and epilogue cards get matching variants.

**Scope and tests.** Per candidate: ~3 seed lines/scenes, the betrayal scene, the fight, two resolution scenes and
epilogue variants. A test checks that every save state picks exactly one betrayer (or Bran).

**Built (core, #186):** `scripts/betrayal.gd` + `data/betrayal.json` (weights and threshold, tunable there),
tests in `tests/test_betrayal.gd`. Scores: home erased +50 (fell and reclaimed +20), personal mission locked +20
(open +15), bond rank 0-1 +20 (rank 2 +10), a rival on the roster with no truce +15, an ended romance +10, rank 5
or current romance -35 (once); threshold 40, ties go to data order. If Bran is gone, the top candidate takes the
deal whatever their score. Chapters call `Betrayal.top()` (Ch4 foreshadowing), `Betrayal.lock()` (Ch5 scene),
`Betrayal.away(id)` and `Betrayal.resolve("redeemed"|"let_go")` (Ch6). Bran's con records the fate `faked`.

**Built (chapter pieces, #186):** everything the chapters need is in place, each switched on by one line of
chapter data, so #30 to #32 only have to call it:
- *Ch3:* Hortense is never a candidate (a test holds it), so her spy reveal stays the decoy.
- *Ch4:* a story mission's `"on_success": {"betrayal": "foreshadow"}` starts it. The top candidate's lines get
  black bars (banter, small talk, the log), their heart in town turns grey ("something on their mind") and talking
  to them plays three seed talks a few days apart; Verity's letter about them plays once in town; a Verity plan
  ("Verity's pages drift") leans on their home for six days, halved by a governor. It follows the campaign: fix
  their home and the mark can move or lift.
- *Ch5:* `"on_success": {"betrayal": "lock"}`. The betrayer leaves the party and every post (role `away`, not fed,
  not in town, the party picker says "gone with the Vacancy"), and back in Hollowmark the scene plays: one per
  candidate, a romance variant for a betraying partner, Bran's con ("Clause Nine"), and "Nobody Home" when
  nobody is left at all (Ash walks through the door alone; no fate is written). The Vacancy speaks only in
  black bars with a few plain words, staged as a hole in the page.
- *Ch6:* the betrayer's fight is a story mission on their home (offered even when it is erased): their own kit
  as boss moves with their tells (`scripts/turncoat.gd`: Ottoline's charge, slam and Through the Door; Daro's
  lunge, sweep and Skewer/Twin Prongs; Odile's Levy, Audit seals and Final Demand), a black bar over their eyes,
  in their home written as words (`@written` maps: ruled paper, every prop its own name). They go down on one
  knee, never die, and the outro ends on Ash's choice: take them back (`redeemed`, home and idle again) or let
  them go (`let_go`, gone into the white). Bran's con is paid off by "The Con: Bran's Thursday" (the Vacancy is
  in breach; hold off its collectors) and brings him home. Chapter 6 adds its own `after` to these missions.
- Talks, seeds, letters and choices: `data/betrayal.json` "talks". Tests: `tests/test_betrayal_chapters.gd`;
  screenshots: `tests/test_betrayal_shots.gd`.

## 11. Roster

Flavor targets: **morally grey mercenaries** and **glamorous/flirty** types, with the weird edge of the setting.
All characters share the paper-doll rig; differences come from layers, palettes, weapon and AI personality.

The roster has three tiers:

| Tier | Count | Who | Depth |
|---|---|---|---|
| **Field heroes** | ~12 (8 in MVP) | Can join the party on missions; also can take any other role | Core: bonds, personal missions, banter |
| **Core staff** | ~8 (3 to 4 in MVP) | Non-fighters who matter: the quartermaster, the head scribe, the tavern keeper... | Core: bonds, scenes, personal missions done by the party |
| **Recruits** | ~30 (6 to 8 in MVP) | Everyone else: specialists, oddballs, defectors | Light: trait, quips, one recruitment hook |

### Field heroes (story)

| Hero | Flavor | Weapon / Ink | Role | Where recruited | Hook |
|---|---|---|---|---|---|
| **Ash, the Unwritten** | Silent protagonist | Inkblade (sword), any Ink | All-rounder | Prologue | Spat out by the Blank; can briefly walk inside it |
| **Brannoc "Bran" Tolley** | Mercenary | Axe, Red Ink | Tank / bruiser | Prologue (Frayed Meadow) | His contract is tattooed on his arm and tightens if he breaks it. Will absolutely sell you out if outbid, and tells you so |
| **Mother Gristle** | Mercenary | Staff, Green + Gold Ink | Healer / poisoner | Gutterwoods | Charges per heal (gold counter in the UI as a joke). Her poisons and her medicines are the same bottles |
| **Corporal "Ninefingers" Daro** | Mercenary (deserter) | Crossbow, Black Ink | Ranged DPS | Act 1 (rescue mission) | Deserted the Concord army after being ordered to strike out a village. Sharpest tongue in the party |
| **Hortense, the Velvet Marquise** | Glamorous / flirty, spy | Rapier, Blue Ink | Fast duelist | Velvet Causeway | Flirts with everyone, including enemies, mid-fight. Secretly sent to capture Ash |
| **Saffron Kiss** | Glamorous / flirty | Whip, Gold Ink | Support / buffer | Velvet Causeway | Cabaret singer whose voice makes things exist for a few seconds. Buffs are literally songs |
| **Nan Cripps & Tally** | Mercenary con artists | Knuckles, Black Ink | Trickster / debuffer | Velvet Causeway (optional) | A grifter and her talking shadow, who signs the contracts she does not want to honor |
| **Ilse of the Mirror** | Glamorous, unsettling | Spear, Blue + White Ink | Lancer / counter | Unfinished Coast | A reflection whose original was erased. Vain, gorgeous, and the only hero besides Ash who can touch White Ink |

**Added 2026-11-20 (Ojon: more women in the playable party).** Four Hollowmark field heroes fill the four open slots,
so the 12 are complete. They join through the empire layer rather than the story chapters:

| Hero | Flavor | Weapon | Role | How they join | Kit (data/heroes.json, abilities.json, techs.json) |
|---|---|---|---|---|---|
| **Big Ottoline** | Cabaret bouncer, Tobble's niece | Brass knuckles | Bruiser / crowd control | Tobble bond rank 2 | Most HP, takes 35% knockback. Chucking Out (charge that hurls and stuns), Last Orders (slam: stun all around 2 s). Tech: Through the Door |
| **Jessamy Leake** | Smuggler, flirt | Hook-knives | Skirmisher / ranged | Guild standing Friendly | Fastest, quickest gauge, fragile. Knife Fan (3 thrown knives), Lamps Out (vanish 3 s, next hit x2). Tech: Cut and Run |
| **Odile Penhallow** | Ex-Concord tax collector | Iron-bound ledger | Controller / sustain | 3 Renown | Biggest Ink pool. Levy (drain around her, heals the party), Audit (+50% damage taken, 6 s). Tech: Final Demand (lands at range, Audits survivors) |
| **Fauvette** | Cabaret duelist, secret-broker (separate from Hortense) | Rapier | Precision duelist / counter | 5 Renown | Riposte (parry window: cancel the next hit and counter with a stun), Fleche (long lunge). Tech: Coup de Grace (double damage below 35% HP) |

Field roster after this: Gristle, Ottoline, Jessamy, Odile, Fauvette (women), Ash, Bran (men), Daro (non-binary).
Still to come: the core staff and the recruit pool. Prototype implements **Ash** (player) and **Bran** (AI ally).

### Core staff (first ideas, MVP picks marked)

| Character | Post | Hook |
|---|---|---|
| **Edwin "Quill" Pask** (MVP) | Quartermaster at the Command Table | A former Concord clerk who kept Hollowmark's books and now cooks them for you. Knows where every coin is buried |
| **Sister Hild** (MVP) | Head of the Scriptorium | Ran away from the Abbey with one stolen page that rewrites itself every night |
| **Old Tobble** (MVP) | Tavern keeper | Has been "about to retire" for thirty years. Hears everything; sells most of it |
| **Cass & Kit Pruett** | Inkworks | Twin chemists who disagree about everything except that the ink is alive |

### Recruit pool (examples of the light tier)

A gravedigger who digs too fast, a Concord tax collector with a conscience, a cartographer who maps places before
they exist, a cabaret bouncer, a choir of three orphans who share one voice, a debt-tattooed blacksmith, a smuggler
who only moves cargo at night, a dog that might be a person. Each brings a trait and a stat spread, a few lines,
and a recruitment hook (a rescue, a bribe, a building, a faction, a choice).

### Recruit pool as built (issue #27)

Light recruits so far: 12 from Act 1 to Chapter 3 before 2026-11-25, plus nine more on stand-in art
(data/placeholders.json): Chapter 2 Sister Mildred (illuminator), Joan Tull (barge pilot, rescue), Rafe Thwaite
(whitewasher), Sib Varley (relic-seller, they/them); Chapter 3 Ida Lumley (pawnbroker), Clément de Cressy (dancing
master), Josette Roux (copyist, rescue), Firmin Gosse (the Host's under-cook), Rémy Morel (duel second, they/them).
Two regional traits came with them: **Vowed** (Abbey and Erasers envoys +2, Escort jobs +5%) and **Salon-bred**
(Nobility envoys +2, Guild -1, Salvage -5%). A recruit from a later chapter is not rumoured until their region is
on the map (`Empire.lead_region`), and Hollowmark has posts by the well and the plaza bench, five people a post.

### Banter

Short, skippable party banter triggers while walking (two or three lines, top of screen, no pause), and in
Hollowmark people at their posts comment on what is happening in the empire. This carries most of the humor
without slowing the story.

## 12. Tone and rating

Weird/surreal dark fantasy with sharp humor. **Mature**: strong violence, death, cruelty of institutions, drugs and
alcohol, innuendo and flirting. **No explicit sexual content.** Gore is stylized (ink, not blood, for most enemies).

## 13. Controls (current)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick / d-pad | Left on-screen stick |
| Attack | J / Space / Z | A (bottom face) | Attack button |
| Swap hero | Tab / Q | Y (top face) | Swap button |
| Pause menu | Esc / P | Start | Pause button (top right) |
| Journal | I (rebindable) | through the menus; LB / RB switch tabs | Journal button on the Command Table, or the menu |

## 14. Milestones

1. **Prototype (done):** one area, movement, attack with power gauge, one enemy type, one AI ally, hero swap, web build.
2. **Foundations (mostly done):** CC0 art and paper dolls, hand-built maps, title/pause/game over, save and autosave.
3. **Command core:** territory map and provinces, the clock, resources, the Blank's Fray and surges, Hollowmark hub
   with the Command Table, buildings, recruit roles and assignment.
4. **Mission core:** launching missions from the map and returning, mission types (story, reclaim, defense,
   rescue), the quick menu, abilities, party picking from the roster, XP and gear.
5. **Act 1 content (MVP, ~4 hours):** Prologue, Chapter 1 and the Act 1 command phase, about 8 provinces, 12 to 15
   recruits, expeditions, research, two factions plus the Concord, relationships for the MVP core cast, The Auditor.
6. **Full game (15 to 20 hours):** about 24 provinces, about 50 recruits, Chapters 2 to 6, all factions, full
   research tree, portraits, music, balancing, accessibility.
