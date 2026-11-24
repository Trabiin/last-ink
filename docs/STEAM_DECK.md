# Steam Deck and controllers

Issue #149 aims for **Deck Verified**. This page covers what the game does on its own; the Steam
parts (Deck button glyphs through Steam Input, the on-screen keyboard, the default controller layout
in Steamworks) belong with the Steamworks integration (#150), and the last check needs a real Deck.

## Valve's checklist, where we stand

| Valve asks for | Status |
|---|---|
| Every screen usable with a gamepad, no mouse or keyboard | Done. `tests/test_deck.gd` drives the title, the town, the Command Table (map, every screen, the menu, Options), a mission (pause, quick menu tabs, a conversation) with real joypad buttons. |
| Text input with the Steam on-screen keyboard | Steam part (#150). The only text boxes are the bug report and the playtest survey; a pad can leave both with B. Steam's own keyboard (Steam + X) works in them already. |
| Deck button glyphs on a Deck | Steam part (#150). Elsewhere Xbox, PlayStation and Nintendo names follow the pad (`Prompts`). |
| 1280x800, 16:10 without stretching | Done. The game lays out on 640x400 there (two screen pixels per game pixel): more world above and below, every screen fills the height, the Command map grows to the bottom. |
| Smallest text at least 9 px at 1280x800 | Done on a Deck. Jersey's capitals are 9 screen pixels tall from size 8 at 2x, so on a Deck nothing is drawn smaller (`Access.min_size`). The readable font already passes at its smallest size. |
| No launcher, boots straight in | Already so. |
| Suspend and resume safe | Done. Losing focus pauses and mutes (Options > Display > In the background); the Command clock takes at most a quarter-second step per frame, so the frame after waking can't hand the Blank hours of land (`Empire.MAX_TICK`). |
| Steady 60 fps, or a locked 40/30 | Options in place: a Deck starts capped at 60, the Frame cap row has 30, 40 and 60. Measuring needs a Deck. |
| Gamepad rumble with a toggle | Done. Options > Rumble: Off, Light, Full (`scripts/rumble.gd`). |
| Runs on Linux or Proton | The Linux build (#145); Proton untested until we have a Deck. |
| Default controller layout in Steamworks | Steam part (#150). |
| Tested on a Deck | Waiting on hardware: ask Ojon. |

## What a Deck changes

`DisplaySettings.on_deck()` is true when Steam sets `SteamDeck=1`, or on a Linux machine whose
screen is exactly 1280x800. `LASTINK_DECK=1` (or `0`) forces it on a PC for testing.

- **First start** (no display options saved): Borderless fullscreen, 1280x800, 60 fps cap.
- **Text:** never smaller than size 8 in the pixel font.

Everything else is the same game. 16:10 window sizes (1280x800, 1920x1200, 2560x1600) are on the
Window size row for every desktop player.

## Rumble

Only the hero you control rumbles the pad, and only while you play on a gamepad.

| When | Feel |
|---|---|
| Your swing or ability lands | a light tap, stronger for a charged swing |
| Your tech fires | a medium kick; a big one when a blast hits hard |
| Your hero is hurt | stronger the more HP it took |
| Your hero goes down | a long full kick |
| A boss slams the ground, the biggest blasts | a quake (the mission's shake of 4.5 and up) |

Light halves it. Screen shake is a separate option, so either can be off without the other.

## Testing at Deck size on a PC

```sh
# Screenshots of every main screen at 1280x800 with the Deck text floor
SHOT_SIZE=1280x800 LASTINK_DECK=1 ACCESS_SHOTS=/tmp/deck xvfb-run -a -s "-screen 0 1600x1000x24" \
  godot --audio-driver Dummy --path . -s tests/run.gd -- access_shots
# Play it like a Deck: a 1280x800 window, Deck defaults
LASTINK_DECK=1 godot --path . --resolution 1280x800
```

A DualSense or Xbox pad on a PC exercises the same input and rumble code a Deck does.
