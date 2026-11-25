# Glossary

The words Last Ink uses in a fixed way, how they are spelt and capitalised, and what they mean. Keep it up
to date when a chapter adds a term (issue #142); translators use it too (docs/LOCALIZATION.md). Voices and
dialect rules are in docs/VOICES.md, naming rules in docs/NAMING.md.

To check a chapter against this list, export the script with `tools/export_script.sh` (one Markdown file
per chapter in `build/script/`) and search it.

## House style

- **British spelling** everywhere the player reads: armour, colour, favour, honour, rumour, defence, duellist, recognise, authorise, grey, millrace.
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
| **surge** | lower case | A Blank lunge at one province; a Defence mission stops it. |
| **Wardlamp** | one word, capital W | Built in a province you hold; slows its Fray. |
| **wardstone** | one word, lower case | What you hold in a Defence mission. |

## Resources and screens

| Term | Notes |
|---|---|
| **Gilt** | Money. Never "gold" or "coins" in rules text (speech may say coin). |
| **Supplies** | Food and kit, capital S. |
| **Insight** | Research currency, capital I. |
| **Renown** | Fame, capital R. Story gates use it. |
| **the Command Table** | The map table in the square; also the screen. |
| **Bonds**, **Expeditions**, **Diplomacy**, **Research**, **Buildings** | Screen names, capitalised. As ordinary words in speech they can be lower case ("a bond", "an expedition"). |
| **Defence** | The mission type (Ojon, 2026-11-24: British spelling). The id stays `defense` in code and saves. |
| **Patrol**, **Reclaim**, **Rescue**, **Raid**, **Salvage** | Mission type names, capitalised. |

## Factions

| Name | Short | Notes |
|---|---|---|
| **the Gilded Concord** | the Concord | Rules from the Gilded Spire. Offices met in Act 1: the Office of Audits (Morrow's tithe column, the writ), the Office of Corrections (the Auditor), the Office of Quiet (Fauvette's "volunteers"). |
| **the Mercenary Guild** | the Guild | Runs Gallows Ferry. |
| **the Gutterwood Coven** | the Coven | In the Gutterwoods (the place takes an -s, the Coven does not). |
| **Saint Ledger's Abbey** | the Abbey | Chapter 2. |
| **the Erasers** | | Verity's followers. Chapter 2. |
| **the Velvet Nobility** | the Nobility | The old houses of the Velvet Causeway. Chapter 3. The Duc de Lantenay speaks for them. |

The Abbey's faction card says **the Abbey of Saint Ledger**; places and speech say **Saint Ledger's** or **the Abbey**. Both are right.

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
| ninefingers | Corporal Daro | Daro | "Ninefingers" is the nickname. they/them. Twelve years in the Concord army; deserted recently (the start of the game) rather than strike out Hob's Wick, and lost the finger for it. The village was told Daro died a hero; the Tithe Road still has the wanted posters. |
| abeyance | Sister Hild | Sister Hild / Hild | Was Abeyance before the naming pass. |
| hesper | Hetty Coyne | Hetty | |
| dunmore | Dunmore Vellacott | Dunmore | |
| jessamy | Jessamy Leake | Jessamy | |
| biscuits | Mr. Biscuits | Mr. Biscuits | |
| merrow | The Merrow Three | Pim, Pet and Posy | |
| odile | Odile Penhallow | Odile | Her mother: Chief Assessor Marguerite Penhallow. |
| ottoline | Big Ottoline | Ottoline | |
| velvette | Fauvette | Fauvette | Stage name of Colombe Brissot. The id stays `velvette`. |

Planned, not in the game yet: Cass and Kit Pruett, twin chemists for the Inkworks (issue #27). Until they join, write "the inkmakers".

Others: Verity Hale (the archivist in the white), Governor Thale, Clerk Pettigrew, Tithe-Captain Morrow,
the Auditor, Ozias Crane, Hester Vane, Notary Fennick, Augustin Sallow.

## Chapter 2 and 3 terms

| Term | Notes |
|---|---|
| **keeper** | Lower case when people call Ash it ("Mind the draught, keeper"). The "Keeper's candle" on the quay is a name, so capital K. |
| **Reader**, **First Reader** | Eraser ranks, capitalised. Askew is the First Reader; a reading is lower case. |
| **the copying hall**, **the cloister walk**, **the Founders' Door** | Lower case for the rooms; the Founders' Door is a name. |
| **the Bonefield**, **the Bonefield Cloister**, **the Bonefield Rising** | The hill, the cloister on it, and the revolt three hundred years ago. |
| **eleven thousand four hundred and six** | Osyth's count, always in words. "The eleven thousand" in speech is fine. |
| **the masquerade** | Lower case, "the masquerade, which continues". A year old when Chapter 3 starts. |
| **the Host** | Capital H: the Chapter 3 boss. Lower case "host" for anyone throwing a party. |
| **word-fishers**, **word-nets** | Hyphenated. They net words out of the ink lake at Pendower Shallows. |
| **the ink lake** | Lower case. The Causeway stands on it. |
| **the Crimson Encore** / **the Encore** | Fauvette's old cabaret on Gallows Ferry, where Ottoline kept the door. |
| **the Gilt Lantern** | Saffron's old cabaret, "till it fell in the lake". |

## People (Chapter 2)

| Id | Full name | Name tag / usual name | Notes |
|---|---|---|---|
| osyth | Sister Osyth | Sister Osyth | Crypt-keeper, forty years. Counts out loud. |
| cuthbert | Brother Cuthbert | Brother Cuthbert | Deaf bell-ringer, Scarth Pass. |
| nell | Nell Tapper | Nell | Candleford chandler and accidental mayor. |
| alcuin | Brother Alcuin | Brother Alcuin | Returned Eraser novice; he/him. |
| odo | Brother Odo | Brother Odo | Messenger. |
| ebba | Prioress Ebba | Prioress Ebba | Runs the Abbey; calls Ash "keeper" or "passer-by". |
| wulfstan | Abbot Wulfstan | Abbot Wulfstan | Chapter 2 boss. Abbot for thirty years. |
| askew | Askew | First Reader Askew | she/her. |

## People (Chapter 3)

| Id | Full name | Name tag / usual name | Notes |
|---|---|---|---|
| hortense | Hortense de Saulx | Hortense | The Velvet Marquise. Sister Bérénice is seventeen and was held six years. |
| saffron | Saffron Kiss | Saffron | Stage name of Maud Pickering, about twenty. Sang her mother's house at nine, eleven years ago. Mother: Annie Pickering ("Mam"). Brother: Dickon. |
| nan | Nan Cripps | Nan | Signed her conscience to Old Pratt at fifteen, eighteen years ago. |
| tally | Tally | Tally | Nan's shadow. "He" to Nan; "it" to Pratt. Never contracts. |
| anselme | Anselme Brugière | Anselme | Vintner on the Vauclair Terraces. |
| margot | Margot Vasseur | Margot | Mask-maker. |
| gaspard | Gaspard Pellerin | Gaspard | Word-fisher. |
| lantenay | the Duc de Lantenay | Duc de Lantenay | Seventy, white-wigged. |
| gaudin | Purser Gaudin | Purser Gaudin | Office of Corrections; Hortense's handler. |
| proctor | Proctor Dufresne | Proctor Dufresne | Head of the Office's school on the Terraces. |
| pratt | Old Pratt | Old Pratt | Moneylender of Lantern Quay. 512 contracts, forty per cent a month. |
