# Steam

Issue #150. What the Steam version adds, how it is built, and what is left for when the Steamworks app
exists. The store page itself is issue #151; the demo is #147; Steam Deck is #149.

## The rule: every build works without Steam

Only the Steam build has GodotSteam in it. The web build, the itch.io downloads and the plain desktop
builds never do, and nothing in the game needs it.

- `scripts/steam_link.gd` (autoload `SteamLink`) is the only script that talks to GodotSteam. It looks up
  the `Steam` engine singleton at run time and calls it by name, so the project compiles and runs with
  or without the extension. (The autoload can't be called `Steam`: that is GodotSteam's own name.)
- Steam starts only when GodotSteam is loaded, it isn't the web build, there's no `--no-steam` on the
  command line, and there is an app id: `app_id` in `data/steam.json`, or the `SteamAppId` the Steam
  client sets when it launches the game. With `app_id` still 0, a build with GodotSteam behaves exactly
  like one without it.
- If Steam doesn't start (client not running, account doesn't own the game) the log gets one
  `Steam: Steam didn't start: ...` line and the game carries on. We don't call `restartAppIfNecessary`,
  so the game never forces a relaunch through Steam.
- `addons/godotsteam/` is git-ignored. `tools/fetch_godotsteam.sh` puts it there; CI does that in
  `.github/workflows/steam.yml`.

## Achievements

The list is `data/achievements.json` (40 achievements in five groups: Story, People, Empire, Fights, Odd
jobs). The `id` is the Steam API name: **never rename or remove one once it is live on Steam.**
`steam/achievements.md` is the same list laid out for typing into Steamworks.

Unlocks belong to the player, not to a save: `user://achievements.cfg` holds the unlocked ids (with the
time) and the lifetime counters. Every build has achievements: without Steam the game shows its own
"Achievement unlocked" card (`scripts/achievement_banner.gd`) and the title screen has an
**Achievements** page (`scripts/achievements_view.gd`). With Steam, each unlock is set and stored on
Steam at once and Steam shows its own pop-up. When Steam starts, the two lists merge both ways (ours go
up, Steam's come down), so a new PC or the Deck catches up.

How each one unlocks (`scripts/achievements.gd`):

| Field | Meaning |
|---|---|
| `when` | a story condition (`Journal.meets`: `cleared`, `joined`, `seen`, `held`...), looked at once a second while playing |
| `check` + `min` | a named check in `Achievements._check()` (bond ranks, provinces held, buildings, research...) |
| `event` | reported by the game: mission results report `reclaimed`, `surge_broken`, `boss_flawless`, `boss_hard`, `wiped` |
| `counter` + `min` | a lifetime count across all saves (`kills`, `retreats`, `expeditions_won`); Steam shows "12 / 25" at each quarter |
| `later` | designed, waiting for a chapter that isn't in the game yet; shows as locked, never unlocks |
| `hidden` | name and description stay secret until unlocked (Steam's Hidden flag too) |

Only a real story campaign counts (`Story.active()`): the test shortcuts' ready-made towns never unlock
anything. "On Hard" achievements need the difficulty never lowered: per mission for bosses, and per save
(`Empire.feats.lowest_difficulty`, saved with the game) for the ending. Saves from before this can't
prove that, so they count as Normal.

Adding an achievement: add the entry, run `godot --headless --path . -s tools/steam_files.gd` to refresh
`steam/achievements.md`, enter it in Steamworks, and make an icon. When a chapter lands, give its `later`
entries a `when` (usually `{"cleared": ["<boss mission id>"]}`) and drop `later`; `tests/test_steam.gd`
checks every referenced mission and recruit exists.

## Rich Presence

Friends see what you're doing: "Act 1: at the Command Table", "Chapter 2: Candleford", "Chapter 2:
fighting The Abbot Who Copied Himself", "In the menus". `SteamLink.current_activity()` works it out from
the scene, the chapter (`Journal.current_chapter()`) and the mission, every 5 seconds, and only sends
changes. Steam needs the text uploaded: `steam/rich_presence_english.vdf`, generated from
`data/steam.json` `presence` by `tools/steam_files.gd`. Every chapter in `data/journal.json` needs an
entry there (tested). The game also sets the plain `status` key, for Steam's "view game info" box.

## Overlay

Opening the Steam overlay pauses the game the way losing focus does (a fight opens its pause menu and
leaves it up; elsewhere the tree pauses and unpauses when the overlay closes), whatever the "in the
background" option says. The game uses the Compatibility renderer, which the overlay supports.

## Steam Cloud

No code needed: use **Steam Auto-Cloud** in Steamworks (Application > Steam Cloud). The game's save
folder is fixed by `application/config/use_custom_user_dir` ("Last Ink"):

| OS | Root (Steamworks name) | Subdirectory |
|---|---|---|
| Windows | `WinAppDataRoaming` | `Last Ink` |
| macOS | `MacAppSupport` | `Last Ink` |
| Linux / Deck | `LinuxXdgDataHome` | `Last Ink` |

Patterns to sync: `save_*.json` (saves; leave out `*.broken-*` and `*.bak*` copies), `settings.cfg`
(options and key bindings) and `achievements.cfg`. Leave out `logs/` and the feedback outbox. Byte quota
and file count: 50 MB and 100 files is far more than needed. Conflict handling is Steam's (it asks which
copy to keep); test it on two machines before launch.

## Achievement icons

Steam wants two 256 x 256 JPGs per achievement: the unlocked icon and a locked (grey) one. Plan:
`steam/icons/<API name>.jpg` and `<API name>_locked.jpg`, made in the game's ink style. This is the paid
part of #150 (PixelLab, roughly $3-8 for 40 icons; the locked ones are made from the unlocked ones in
code). Not made yet: it waits until the list is final, so it is a follow-up issue.

## Building

`.github/workflows/steam.yml`, on every pull request and push to main:

1. downloads Godot and the Linux export template,
2. runs `tools/fetch_godotsteam.sh`: the newest GodotSteam GDExtension release that loads in Godot 4.3
   (`tools/godotsteam_pick.py` reads each release's `compatibility_minimum`), and prints its tag and
   checksum,
3. exports the Linux build, then runs `tools/smoke_build.sh` with the `steam` and `scenes` tests inside
   the exported binary (`LASTINK_EXPECT_GODOTSTEAM=1` makes the Steam tests insist the extension loaded),
4. boots it once with `SteamAppId=480` and no Steam client, to prove a failed start is quiet,
5. keeps the build as a workflow artifact.

### Updating GodotSteam

Set `GODOTSTEAM_TAG` and `GODOTSTEAM_SHA256` in `.github/workflows/steam.yml` to the values the last run
printed ("GodotSteam: ... from release ..." and "GodotSteam: sha256 ..."). Empty means "newest that
fits", which is fine until release candidates; pin it before the first upload so every Steam build uses
the same library.

Locally: `tools/fetch_godotsteam.sh`, then open or export the project as usual. Testing against a real
Steam client: run the game with the Steam client open and `SteamAppId=480` (Valve's test app,
Spacewar) until our app id exists.

## Still to do (needs the Steamworks app)

Ojon first: pay the $100 Steam Direct fee and create the app (issue #151). Then:

- [ ] Put the app id (and the demo's) in `data/steam.json`.
- [ ] Enter the achievements from `steam/achievements.md` under Stats & Achievements, then publish.
- [ ] Achievement icons (paid, small; see above).
- [ ] Upload `steam/rich_presence_english.vdf` (Community > Rich Presence).
- [ ] Turn on Auto-Cloud with the paths above; test conflict handling on two machines.
- [ ] SteamPipe: depots for Windows, macOS and Linux, `default` and `beta` branches, the demo app; a CI
      job on tags that builds the three Steam builds (Windows on a Windows runner, like the desktop
      workflow) and uploads with `steamcmd`. Ojon stores the build account's login as GitHub secrets
      (a dedicated Steam account with only build rights, and its Steam Guard set up for CI).
- [ ] Check the overlay over a real build on Windows, macOS, Linux and the Deck.
