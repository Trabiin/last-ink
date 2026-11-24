# Glossary

The words Last Ink uses in a fixed way, how they are spelt and capitalised, and what they mean. Keep it up
to date when a chapter adds a term (issue #142); translators use it too (docs/LOCALIZATION.md). Voices and
dialect rules are in docs/VOICES.md, naming rules in docs/NAMING.md.

To check a chapter against this list, export the script with `tools/export_script.sh` (one Markdown file
per chapter in `build/script/`) and search it.

## House style

- **British spelling** everywhere the player reads: armour, colour, favour, honour, rumour, defence (but see
  *Defense* below), duellist, recognise, authorise, grey, millrace.
- Numbers in story text are words ("eleven years", "Thirty-one lines"); numbers in rules text are digits
  ("+2 Gilt a day", "15 Renown").
- A goal's hint starts with a capital letter, like its title.
- "forever", not "for ever". "Any more" (two words) for "no longer".
- Place names keep their article: **the Tithe Road**, **the Wickham Hills**, **the Gutterwoods**,
  **the Frayed Meadow** (but "Hollowmark", "Gallows Ferry", "Old Mill Crossing", "Saltreed Marsh").

## The world

| Term | Use | Notes |
|---|---|---|
| **the Blank** | capital B, always "the" | The white nothing eating the map. Also "the white" (lower case) in speech and narration. |
| **Fray** | capital F as a number ("45 Fray", "Fray +3"); "fray/frays/frayed" as a verb | 0 to 100; at 100 a province is erased. |
| **erased** / **Erased** | lower case for land ("the province is erased"); capital for the hero status ("an Erased hero", "can Erase you") | Erased land is reclaimed with a Reclaim mission. |
| **Erasure** | capital E | The Concord's legal penalty: striking a person or town out of the Ledger. "Erasure order", "Erasure writ", "Erasure notices". |
| **the Ledger** / **the Great Ledger** | capital L | The Concord's record of everything that exists. A lower-case "ledger" is any account book (Quill's, Odile's stolen one). |
| **struck out** / **written off** | lower case | Struck out = removed from the Ledger. Written off = Quill's bookkeeping term for the same. |
| **Ink** | capital I for the resource and the magic; lower case for ordinary ink in pens and wells | Five colours people can hold (Red, Blue, Gold, Green, Black) and White, which only the Blank uses. |
| **the Inklands** | always "the" | The whole map. |
| **Blot** | capital B | The thing at the heart of erased land that a Reclaim mission breaks. |
| **surge** | lower case | A Blank lunge at one province; a Defense mission stops it. |
| **Wardlamp** | one word, capital W | Built in a province you hold; slows its Fray. |
| **wardstone** | one word, lower case | What you hold in a Defense mission. |

## Resources and screens

| Term | Notes |
|---|---|
| **Gilt** | Money. Never "gold" or "coins" in rules text (speech may say coin). |
| **Supplies** | Food and kit, capital S. |
| **Insight** | Research currency, capital I. |
| **Renown** | Fame, capital R. Story gates use it. |
| **the Command Table** | The map table in the square; also the screen. |
| **Bonds**, **Expeditions**, **Diplomacy**, **Research**, **Buildings** | Screen names, capitalised. As ordinary words in speech they can be lower case ("a bond", "an expedition"). |
| **Defense** | A mission type name, kept as written (it is the in-game label). Open question: switch to British "Defence" across data and scripts. |
| **Patrol**, **Reclaim**, **Rescue**, **Raid**, **Salvage** | Mission type names, capitalised. |

## Factions

| Name | Short | Notes |
|---|---|---|
| **the Gilded Concord** | the Concord | Rules from the Gilded Spire. Offices met in Act 1: the Office of Audits (Morrow's tithe column, the writ), the Office of Corrections (the Auditor), the Office of Quiet (Fauvette's "volunteers"). |
| **the Mercenary Guild** | the Guild | Runs Gallows Ferry. |
| **the Gutterwood Coven** | the Coven | In the Gutterwoods (the place takes an -s, the Coven does not). |
| **Saint Ledger's Abbey** | the Abbey | Chapter 2. |
| **the Erasers** | | Verity's followers. Chapter 2. |

## People (Act 1)

Name tags in dialogue come from `data/recruits.json` (the nickname in quotes, else the short form), so keep
these the same everywhere.

| Id | Full name | Name tag / usual name | Notes |
|---|---|---|---|
| ash | Ash | Ash | The Unwritten. Silent. Gender never stated: write "they" only when unavoidable, and never "a man" or "a woman". |
| bran | Brannoc "Bran" Tolley | Bran | Fauvette and Crane call him Brannoc; Daro and Ottoline call him Tolley. |
| quill | Edwin "Quill" Pask | Quill | they/them. |
| tobble | Old Tobble | Old Tobble / Tobble | Ottoline's "Uncle Tobble". |
| pell | Pell Mossop | Pell | |
| gristle | Mother Gristle | Mother Gristle / Gristle | |
| ninefingers | Corporal Daro | Daro | "Ninefingers" is the nickname. they/them. |
| abeyance | Sister Hild | Sister Hild / Hild | Was Abeyance before the naming pass. |
| hesper | Hetty Coyne | Hetty | |
| dunmore | Dunmore Vellacott | Dunmore | |
| jessamy | Jessamy Leake | Jessamy | |
| biscuits | Mr. Biscuits | Mr. Biscuits | |
| merrow | The Merrow Three | Pim, Pet and Posy | |
| odile | Odile Penhallow | Odile | Her mother: Chief Assessor Marguerite Penhallow. |
| ottoline | Big Ottoline | Ottoline | |
| velvette | Fauvette | Fauvette | Stage name of Colombe Brissot. The id stays `velvette`. |

Others: Verity Hale (the archivist in the white), Governor Thale, Clerk Pettigrew, Tithe-Captain Morrow,
the Auditor, Ozias Crane, Hester Vane, Notary Fennick, Augustin Sallow.
