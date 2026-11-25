# Economy sim (issue #35)

`tools/balance_sim.gd` ([BALANCE.md](BALANCE.md)) says *what* happened in a long run: story pace, levels,
land, Fray. The economy sim says *where the money went*: every Gilt, Supply, Ink, Insight and Renown, by
source, chapter by chapter, so a resource that runs away or runs dry shows up with its cause next to it.

```sh
godot --headless --audio-driver Dummy --path . -s tools/economy_sim.gd -- 150 steady,casual,rush 3 /tmp/economy
```

Arguments: days per run, policies, seeds per policy, output folder. It writes `economy.md` and prints it.
150 days for three policies and three seeds take about 30 seconds.

## How it counts

`tools/economy_meter.gd` is the balance bot (`tools/balance_bot.gd`) with a meter on it: it plays exactly the
same (it overrides each decision step only to call the bot's own with `super()` and note the change in every
resource), so the two tools always agree. Each day's change is split into:

- the bot's steps: Missions, Buildings (and hurrying), Research, Forge, Claims, Hiring, Feasts, Market sales,
  Wardlamps, Expedition costs, Diplomacy, Bonds, Story;
- `Dawn: <line>`: every line of the daily ledger the screens show (Provinces and Governors are grouped,
  the rest keep their names, e.g. `Dawn: Upkeep`, `Dawn: Inkworks`, `Dawn: Ink lessons`), plus the
  Scriptorium's Insight;
- `Dawn: other`: whatever the clock moved beyond the ledger (expeditions coming home, faction trouble,
  bond perks, Erasers).

The books balance: the sum of every source equals the change in the bank (`tests/test_economy.gd` checks it).
Chapters are read from the chapter openers seen (`ch2_bells`, `ch3_invitation`, ...); "After the last
chapter" starts when the last written chapter's ending plays.

## Report

- **Flags.** Upkeep for level 4 and 5 buildings unpaid on more than 5 days (they work as level 3); Gilt, Ink or
  Insight at or near empty on 40% of the days after day 20; a bank past its band (Gilt 1,500, Supplies 600,
  Ink 120, Insight 150) and still climbing over the last 20 days. A pile says when the written story last
  moved and the day the empire ran out of studies or building levels to buy.
- **Runs.** Per run: the day each chapter opened, the day the story last moved, the first day of the streak
  (still running at the end) with nothing left to study or build, unpaid upkeep days, end banks.
- **Per policy and chapter**: net a day for each resource, and its sources and sinks a day, biggest first.

## Findings, 2026-11-25 (on top of #256)

150 days, steady / casual / rush, 3 seeds each. The written story (Act 1 to Chapter 3) ends around day 45
for steady and rush, day 85 to 95 for casual.

**Inside the written story: no flags.** Nothing ran short for upkeep in any run, nothing sat empty, nothing
piled up. Gilt stays the tight resource (Buildings and Claims take what Missions and land bring in;
in Chapter 3 the Forge takes over at about 50 a day). Supplies grow +12 a day in Act 1, +4 in Chapter 2 and
level off in Chapter 3 as feasts and upkeep catch up. Insight is spent as fast as it comes in. Ink grows
+6 a day in Chapter 2 with little to buy until Ink lessons start; lessons then take 9 to 13 a day.

**After the story, with no new chapter to open** (what Chapters 4 to 6 have to fill, issue #258):

| Resource | What happens | When |
|---|---|---|
| Insight | Every open study is done; +15 to +20 a day with nothing to buy, 500 to 1,000 banked by day 150 | from day 110 to 130 |
| Ink | Benched heroes reach colour level 3, so lessons stop; the Inkworks' +13 a day piles up (rush: 500 to 750 by day 150) | from about day 120 |
| Gilt | Builders keep it in check until every level 5 is up (one crew: about day 150); a casual player whose map stays small finishes earlier and banks 1,500 | from day 118 (casual) |
| Supplies | Fine: about -3 a day once every level 5 pays upkeep, feasts and the Market absorb the rest | |

Chapters 4 to 6 will open the Coast and Spire research branches (6 nodes, about 300 Insight), which buys
two weeks at most. Re-run this sim when each chapter lands and tune its sinks until the flags clear.
