# Animation review rules

Ojon's rules for judging sprite animations, written down on 2026-11-23 so that Claude can review them the
same way. They grow as new cases come up. Reviews are kept in the Art Review page, one verdict per
direction. `tools/anim_check.py` checks the measurable rules; everything else is judged by eye on a contact
sheet, both zoomed in and at game size.

## How to look
1. **Watch the whole animation first.** Does it look natural for *this* character? A human walks differently
   from a dog or a Nibbler. It doesn't need to be perfect, but it has to be believable both zoomed in and at game size.
2. **Then go through the frames for details.**
3. **Tolerance:** a one-pixel slip or a short flash that doesn't show at game size is OK, unless it is
   in the eyes, the mouth or a held item. Eyes are often just 2-4 pixels, so one drifting pixel there can make
   the whole eye vanish.

## Rules
| # | Rule | Checked by |
|---|---|---|
| 1 | **Walks walk.** The legs visibly move in every direction, about as much as in the best direction. | `legs-still` + eye |
| 2 | **Feet don't cross** over or through each other unnaturally (watch the diagonals). | eye |
| 3 | **Idles stay put.** The feet stay planted; an idle that steps is a walk. | `idle-walks` + eye |
| 4 | **The whole body breathes.** An idle where only the head or one hand moves and the arms stay frozen looks wrong. Nothing should stay completely still while the rest moves. | `frozen` + eye |
| 5 | **Small features stay.** Eyes, mouth and marks keep their pixels and colours from frame to frame. They may move with the face, but they must not blink out or change colour. | `detail-pops` + eye |
| 6 | **No new patches.** Nothing appears in the head that the character doesn't have, such as a face or a colour patch on the back of the head. | `new-colour` + eye |
| 7 | **The outline stays black.** If the idle has a black outline all round, it stays black in motion. It doesn't turn into the cloak colour, for example. | `outline` + eye |
| 8 | **Items stay consistent.** A held item stays in the hand in every frame (Gristle let go of her staff walking south-east), keeps its length and colours, and looks the same in every direction (Bran's axe was a different colour and grew long facing north-east). | eye |
| 9 | **Directions match each other.** The same colours, proportions and details appear in every direction. | eye |
| 10 | **Small repeated details keep their count.** Hair ornaments, buttons and bottles don't go 1, 2, 3 between frames (Gristle's idle facing north-east). | `detail-pops` + eye |

## More things that can go wrong (agreed with Ojon 2026-11-23)
Collected from the Act 1 audit, the two calibration rounds and common pixel-animation faults.

**Body and motion**
| # | Rule | Checked by |
|---|---|---|
| 11 | **Proportions hold.** The head, body and limbs keep their size from frame to frame (no head that pulses or a body that shrinks halfway, like the Scarecrow's north walk). | measurable (planned) + eye |
| 12 | **Feet stay on the ground.** In walks and idles, the feet line doesn't drift or bob unless the motion calls for it (a jump); the character doesn't slide against the ground. | `ai_audit.py` feet + eye |
| 13 | **No extra or missing parts.** No third hand, extra finger, doubled weapon or vanished arm on any frame. | eye |
| 14 | **The loop closes.** The last frame flows into the first without a jump (idles and walks). | measurable (planned) |
| 15 | **Secondary motion follows.** Cloaks, hair and hanging items lag slightly behind the body instead of staying rigid, but they don't flap at random. | eye |
| 16 | **Facing stays put.** The character doesn't turn towards the camera mid-animation (the Act 1 idle-north problem). | `new-colour` + eye |

**Items and details**
| # | Rule | Checked by |
|---|---|---|
| 17 | **Same hand.** A held item stays in the same hand across frames and directions; it doesn't swap hands. | eye |
| 18 | **No clipping.** Items don't pass through the body or the head (a staff through the face). | eye |
| 19 | **Marks stay on their side.** Scars, tattoos, a clouded eye and a pauldron stay on the same side of the body in every direction. | eye, per character sheet |
| 20 | **Mirrored directions.** The game draws west, south-west and north-west by mirroring the east side, so anything one-sided (an axe hand, a scar, a pauldron) flips sides there. Decide per character whether that's acceptable. | eye, per character sheet |

**Pixels**
| # | Rule | Checked by |
|---|---|---|
| 21 | **Clean pixels.** No soft or half-transparent edge pixels and no stray specks around the character. | `ai_audit.py` |
| 22 | **No shimmer.** Flat areas (cloth, skin) don't boil with pixels that change every frame while the shape stays still. | `detail-pops` + eye |
| 23 | **Inside the frame.** Nothing is cut off at the canvas edge (weapon tips in attacks). | measurable (planned) |

**Per animation type**
| # | Rule | Checked by |
|---|---|---|
| 24 | **Attacks read.** A clear wind-up, a hit frame and a recovery; the weapon is visible on the hit frame. The game draws its own swing trail, so the sprite shouldn't have a swoosh. | eye |
| 25 | **Hurt and KO read.** Hurt is a short, clear recoil that goes back to the idle pose. KO ends lying still on the last frame. | eye |
| 26 | **Victory and cast poses** stay in character and keep the item in the hand. | eye |

## Character sheets
Before reviewing a character's animations, write down what makes that character, from the rotation frames
and the portrait: features, small counted details, items, sides. Then check every animation against the
sheet. Sheets are in `docs/ANIMATION_FEATURES.md`.

## Claude's habits
- Every checker flag gets a zoom on that exact frame before it can be called OK. In round 2 the checker had
  already flagged both of the directions Claude missed.
- The checker is a pointer, not a verdict: it can be overruled in either direction (Gristle's walk facing
  north-east was flagged `legs-still` but is fine).

## How Ojon fixes them
By hand, pixel by pixel: in PixelLab's Pixelorama editor, an animation's frames can be played and edited one
at a time. Claude does the fixes that can be made by moving or copying existing pixels (`tools/fix_frames.py`).
Anything that needs drawing goes to Ojon (marked "By hand") or to a paid re-animation.

## Calibration log
- 2026-11-23, Bran idle and walk. Before the rules, Claude's eye pass matched 5 of Ojon's 10 direction verdicts.
  It missed motion problems (idle SE was a walk, idle N had frozen arms, walk S and N weren't walking, walk NE
  feet crossed), the mouth colour in idle E and the axe colour in NE. With these rules the checker matches 8
  of 10. It still misses the idle E mouth and the walk NE feet (those are left to the eye check), and it
  wrongly flags idle S.
- 2026-11-23, Mother Gristle idle and walk (blind, with the rules and the checker): 7 of 10 matched. Misses:
  the hair ornament count in idle NE and the staff dropped in walk SE (the checker flagged both, but Claude
  dismissed the flags). Too strict on short green flashes in walk E. Ojon: a slow shuffle where the legs
  barely show counts as not walking.
