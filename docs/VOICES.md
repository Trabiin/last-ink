# Voices

How the people of Last Ink talk, and the prose habits that make writing read as machine-made. Issue #167.

**Why:** writing is the second most-named AI complaint in Steam reviews (research in the project files,
`last-ink/research/ai-reception.md`). We say openly that AI helped make the game (docs/AI_USE.md), but a line
that *sounds* generated costs us the player's trust in everything around it. [NAMING.md](NAMING.md) does this job
for names; this file does it for prose.

**How to use it:**
- Before writing or editing a character's lines, read their sheet (section 5). Cover the speaker name and read
  the line back: if it could be anyone's, rewrite it.
- `tests/test_voice.gd` enforces the hard bans (section 2.1), punctuation (section 3) and a budget for each
  softer tell (section 2.2) on every push.
- The script rewrite (#167 step two) and every new chapter (#28 to #32) are written to these sheets. The final
  read-aloud check is part of #142.

Speaker ids are the ones in the data files. Some ids predate the naming pass (#158) and were kept so saves and
portraits keep working: `velvette` is Fauvette, `abeyance` is Sister Hild, `ninefingers` is Daro, `hesper` is
Hetty Coyne, `marrow` is Notary Fennick.

---

## 1. House style (everyone)

The tone is in [DESIGN.md](DESIGN.md) section 12: weird, dark, sharp humour, Mature. In practice:

1. **Specific beats grand.** "Eleven days of turnips and a debt to a goat", not "our supplies dwindle". A number,
   a named object, a place on the map. If a line could be printed on a poster, it's too grand.
2. **Subtext beats stated feeling.** People here don't say "I'm scared" or "I feel guilty". They wipe a clean
   bottle for a long time, change the subject, make a joke that doesn't land, send an invoice. The narrator shows
   the hands; the character keeps the feeling.
3. **The world is paperwork.** Debt, ledgers, forms, tithes and receipts are how people think, the way sailors
   think in weather. Use it for jokes and for grief. Don't use it to be clever every line: one paperwork joke per
   exchange is plenty.
4. **Jokes come from character, not from the writer.** Bran is funny because he's mercenary about everything,
   Daro because they're furious, Quill because he's precise. If everyone is quippy in the same way, the cast
   turns into one voice with several hats. Let some lines be plain.
5. **Endings don't wrap up.** Don't end a scene on a moral, a lesson, or a line that explains what just happened.
   End on an action, an object, or a joke that dodges the feeling.
6. **Short lines.** Dialogue box lines are one to three sentences (the bond test already checks they fit the
   box). Most sentences are under 15 words. Long sentences belong to characters who talk long (Quill reading a
   document, Fauvette performing, Verity's letters).
7. **Ash is silent.** Nobody quotes Ash. Other people react to a choice, a look, a shrug; each of them reads the
   silence differently, and that's a running joke (DESIGN.md section 11). Ash's choice labels are short and
   physical where possible: "[Shrug]", "Hold out your hand", not speeches.
8. **Mature means honest, not edgy.** Violence, cruelty, drink, flirting and death are on the table. Swearing is
   allowed but rare and specific to the speaker (see sheets). No explicit sexual content.

---

## 2. AI tells

### 2.1 Banned (the test fails)

These phrases are the fingerprints of model-written prose. They never appear in player text: data values, and
string literals in scripts. A deliberate use (a character mocking purple prose, say) goes on the allowlist in
`tests/test_voice.gd` with a reason.

> a testament to · tapestry · whispers of · palpable · delve · in the heart of · the weight of · a dance of ·
> little did (they) know · shiver down (her) spine · a breath (she) didn't know (she) was holding ·
> a symphony / cacophony / kaleidoscope of · myriad · ebb and flow · beacon of (hope) · indelible ·
> unwavering · (her) resolve hardened · steeled (himself) · ethereal · gossamer · liminal · palimpsest ·
> nestled · bustling · vibrant · intricate · ever-changing / ever-shifting / ever-present · sentinel ·
> echoes of · the fabric of (reality) · barely above a whisper · hung in the air · the air thick with ·
> deafening silence · the silence stretched · can't help but · let out a breath · only time will tell ·
> in a world where · serves as a reminder · a reminder that · at the end of the day · and that's okay ·
> maybe that's enough · it's not about X, it's about Y · not just X, but Y · more than just ·
> (eyes) glinting / sparkling with · something shifted · a long moment

An ink-and-paper world makes some of these extra tempting ("indelible", "palimpsest", "echoes of erased names").
That's exactly why they're banned: they're the first thing a model reaches for here.

### 2.2 Watched (the test fails over budget)

These aren't wrong once. They're tells when they repeat, or when every character does them. `tests/test_voice.gd`
counts them across the whole script and fails when a tell goes over its budget (the Limit column);
`VOICE_REPORT=1` lists each hit. Lines spoken by a tell's owner don't count. A few deliberate uses (Ottoline's
"Coat. Ticket. Out." refrain, a written-out knock) sit on `WATCH_ALLOW` in the test with a reason.

**Over budget?** Rewrite the new line, or an older one you like less. Don't raise the limit: the budgets are the
point. #167 step two (2026-11-24) cut the script from 52 watched tells (2026-11-21) to 11.

| Tell | What it looks like | Rule | Limit |
|---|---|---|---|
| **"People think X"** | "People think medicine and poison are opposites." | A lecture opener. At most one in the whole script | 1 |
| **The correction** | "Not empty. Clean." · "It isn't cowardice. It's manners." | Strong once a chapter. As a habit it's the "it's not X, it's Y" tell in short form | 6 |
| **The either/or verdict** | "That's either very smart or very stupid." · "Must be nice. Or terrifying." | Bran's alone (section 5) | 0 others |
| **The "Or X." afterthought** | "Or sell it. Or forget whose I was." | Owned by Jessamy ("handsome. Or pretty.") and Bran (escalating options). Others drop it | 2 others |
| **Fragment triplets** | "Streets. Families. Whole towns." | One per scene at most. Owned by nobody | 4 |
| **Stated feelings** | "I'm not crying." · "I feel so guilty." | Rewrite as action or deflection (house rule 2) | 0 |
| **Moral tags** | "Now you know." · "That's the whole art." · "That isn't nothing." | A neat button on the end of a confession. Cut it or swap for an action | 0 |
| **Soft-fantasy words** | journey, realm, embark, unravel, whisper(ing), truly, deeply | Not banned, but each needs a reason. Tobble's "whispering's my trade" is his (owner); the Saltreed reeds that whisper are the place's one | 3 |
| **Somebody else's word** | Anyone but Gristle saying "dearie" | Each sheet lists words a character owns. Others don't use them | 0 |

### 2.3 Caught by reading (no test can)

- **Three-adjective runs.** "Cold, quiet, and endless." Pick the one that matters.
- **Everyone's a wit.** If three lines in a row are all punchlines, make one of them plain.
- **Symmetry.** Two-part sentences that mirror each other ("They took my name. I took their ledger.") are a model
  habit. Fine once per scene, never in back-to-back lines.
- **Explaining the joke.** Let it land and move on. No "That's a joke, by the way."
- **Therapy-speak.** "Closure", "process", "boundaries", "valid", "healing", "trauma", "toxic", "space for".
  Nobody in a paperwork empire talks like a self-help book.
- **Characters announcing a theme.** "Truth isn't what's written. Truth is what refuses to stay crossed out." is
  Sister Hild's one big line and it's earned; a second character saying something that quotable in the same act
  is too many.
- **Narration that tells you how to feel.** "It was a sad sight." Show the empty chairs instead.

---

## 3. Punctuation (the test fails)

One style across the whole script, chosen to read cleanly in a small pixel font:

- **No em dashes or en dashes** (—, –) and no ` -- ` or spaced ` - ` used as a dash in data text. A pause is a
  full stop or a comma. An interruption is `...` at the cut.
- **Straight quotes only:** `"` and `'`. No curly quotes. Quoted text inside a line uses double quotes, or single
  quotes when a whole line is read aloud from a document (Verity's letter, Concord notices).
- **Three full stops for an ellipsis** (`...`), never the single `…` character. Use sparingly: a trailing-off is
  a choice, not a rhythm.
- **Stage directions** in narration lines are plain present tense ("He polishes a mug that was clean when he
  started."), never inside a character's line.
- Shouting is rare and in capitals (the Auditor's "FINAL NOTICE", the Merrow Three). No exclamation marks in
  narration.

---

## 4. Accent and dialect

**Why (Ojon, 2026-11-22):** everyone used to speak the same perfect, correct English. Where someone grew up, and
how high they stand, should come through in how they talk, so a reader can tell a dock kid from a Chief
Assessor's daughter without a portrait. Every character gets their own speech, not just their own jokes.

### 4.1 Rules for writing dialect
1. **Grammar and words before spelling.** "It were cold" and "I'll not" carry a dialect better than
   apostrophes everywhere. Respell a word only when it's one of that character's markers below.
2. **Light touch: one or two markers per line,** not every word. The line has to read at speed in a small
   pixel font, and a wall of `'ere 'e 'ad` reads as a joke about the speaker.
3. **Dialect shows place and rank, never brains.** The smartest people in the cast include a dock kid who
   can't read and a hedge-witch. Nobody's accent is the punchline.
4. **Keep it consistent.** Each character's markers are listed in their sheet; use those, always, and don't
   borrow another character's. A marker in someone else's mouth is as wrong as their catchphrase.
5. **Stress changes it.** Upper-class speakers get more formal when hurt; working speakers get broader when
   angry or drunk. Fauvette's real voice slips through only when she stops performing.
6. **Spoken lines only.** Narration, menus, tooltips, the journal and help stay plain English. Letters and
   notices are written as their author would write, not speak (an educated letter has no dialect at all).
7. **Translators** get the glossary in 4.3. Dialect is translated by register (rough, posh, rural), not word
   for word (docs/LOCALIZATION.md).

### 4.2 Who speaks how

The world borrows its regions from British and French sources (docs/NAMING.md 2.1), so the speech does too.

| Background | Who | Speech |
|---|---|---|
| **Gallows Ferry docks** (river, working) | Bran, Ozias Crane (who hides it) | Dropped h's on a few words ('im, 'er, 'ere), "ain't", "me" for "my", "nothing" as "nothin'", "them" for "those", double negatives. Short |
| **The North, plain folk** (Hollowmark tavern trade) | Tobble (broad, old), Ottoline (younger, flatter) | "Aye", "nowt", "owt", "summat", "were" for "was", "our" before family names ("our Tobble"), "us" for "me", "love". Tobble also has "thee/tha" when sentimental |
| **Gutterwoods, Welsh border** (rural, witches) | Gristle, Hester Vane, Pell | Turned-round sentences ("Lovely work, that is."), tag questions ("isn't it", "is it now"), "I'll not", "there's" for wonder ("There's a face on you"). Pell is the slow farm end of it: "reckon", "ar", "proper" |
| **Tithe Road back roads** (smugglers, thieves' cant) | Jessamy | Keeps her h's, drops g's ("somethin'", "nothin'"), thieves' cant: "cully" (friend), "lark", "peach" (to inform), "flash" (showy), "on the cross" (crooked), "the pennies" (toll men) |
| **Concord army barracks** (enlisted) | Daro | Drops the subject ("Saw it. Didn't like it."), army slang ("bloody", "kit", "stand down", "civvies"), "sir" and "ma'am" as insults, numbers for everything |
| **Concord gentry and high office** | Odile, Marguerite Penhallow, Verity, Governor Thale | No contractions on duty, "one" for "you", "rather", "I should think", "quite", Latinate words. Odile and her mother are the clipped school; Verity the warm, bookish end; Thale the pompous end |
| **Concord clerks and officials** (lower office) | Quill, Clerk Pettigrew, Notary Fennick, the Auditor, wardens, Tithe-Captain Morrow | Officialese: "per", "herewith", "duly", "as it were", "in respect of", passive voice ("it has been noted"). Quill plays with it; the others mean it |
| **Saint Ledger's Abbey** | Sister Hild | Gentle, old-fashioned church English: "I think it a promise", "God keep you", "Deo gratias" and other half-remembered Latin tags, "the Abbot used to say". No contractions when she quotes scripture, plenty when she rambles |
| **The Velvet Causeway** (French-speaking bridge-city) | Fauvette, Augustin Sallow, Hortense later | Fauvette performs a grand stage English with French words dropped in ("chérie", "voilà", "enfin", "mon petit"), French word order ("It is not nothing, this."). Underneath she is Colombe Brissot from the Causeway quays: when sincere, the French goes and a plain, blunt quayside voice comes out. Sallow overdoes the same French, badly |
| **The Unfinished Coast** (Cornish fishing shore) | The Merrow Three | "Proper", "dreckly" (some time, never), "where's that to?", "my bird" as an endearment, "they'm" for "they are" |
| **The Margin** | The Vacancy | No dialect. Redacted bars and a few plain words |

### 4.3 Glossary for translators and new writers

| Word | Who uses it | Means |
|---|---|---|
| nowt / owt / summat | Tobble, Ottoline | nothing / anything / something |
| our (before a name) | Tobble, Ottoline | my (family member): "our Tobble" |
| cully | Jessamy | friend, mate (also a mark in a con) |
| peach | Jessamy | to inform on someone |
| on the cross | Jessamy | crooked, illegal |
| the pennies | Jessamy | toll men on the Tithe Road |
| civvies | Daro | civilians |
| dreckly | Merrow Three | "directly": some time, maybe never |
| my bird | Merrow Three | dear, love |
| chérie, voilà, enfin, mon petit | Fauvette | darling (to a woman), there it is, well/at last, my little one |
| per, herewith, duly | Quill, clerks | Concord officialese: as, enclosed, properly |

---

## 5. Voice sheets

Each sheet: how they talk, their tics (words and moves they own), what they never say, and sample lines. Lines
marked *(in game)* show the voice as first written, before the dialect pass (2026-11-22); lines marked *With
dialect* show how the character sounds now, and the script has been rewritten to match. Unmarked lines are new
examples written to this sheet.

### Narrator
- **Talks:** present tense, plain, dry. Short sentences. Hands, objects, weather, the Blank's behaviour. One odd
  detail per scene does more than three adjectives.
- **Tics:** treats the Blank like a sulking animal ("sulking that it let you go"). Deadpan understatement.
- **Speech:** No dialect. Plain, neutral English (rule 4.1.6).
- **Never:** tells the player how a character feels; uses "whisper" for wind; ends on a moral.
- *(in game)* "He polishes a mug that was clean when he started."
- *(in game)* "The tollgate is too quiet. Someone has swept the road. Someone has swept the birds off it, too."
- *(in game)* "It is a neat white hole now, with a few desks at the edge, still being filed."

### Brannoc "Bran" Tolley (`bran`)
- **Who:** sellsword, contract tattooed on his arm. Gallows Ferry dock kid. Can't read, can count.
- **Talks:** short, blunt, transactional. Talks about feelings only as costs. Lists options in escalating order.
- **Speech:** Gallows Ferry docks. Drops the h on a handful of words ('im, 'er, 'ere), "ain't", "me" for "my", "nothin'", "them" for "those". Gets broader when angry.
- **Owns:** "clause" (numbered clauses of his contract), "invoice", "hazard pay", "on the bill", calling Ash
  "smudge". The escalating "Or X. Or Y." list. The either/or verdict ("That's either very smart or very
  stupid").
- **Never:** says thank you straight; admits he likes anyone without calling it disgusting; uses long words.
  Swears like a docker, but rarely on screen.
- *(in game)* "It tightens if I break it. Like a fist. Ask me how I know."
- *(in game)* "So the contract's with nobody now. Which means I'm here because I want to be. Disgusting."
- *(in game)* "Don't look at me. I can't read. I can count, though, and that sign's going the wrong way."
- "Clause six. If the client dies, I keep the deposit. Don't make me use clause six."
- With dialect: "Clause four: I guard the client. Clause nine: someone pays more, I tell the client first. Then I'm off."
- With dialect: "It tightens if I break it. Like a fist. Ask me 'ow I know."
- With dialect: "So the contract's with nobody now. Means I'm 'ere 'cause I want to be. Disgustin'."

### Mother Gristle (`gristle`)
- **Who:** hedge-witch healer thrown out of the Coven; her medicines and poisons are the same bottles.
- **Talks:** sweet-voiced and poisonous. Bedside manner of a loan shark. Medium sentences with a sting at the end.
- **Speech:** Gutterwoods, Welsh border. Turns sentences round ("Lovely hands, those are."), tag questions ("isn't it", "is it now"), "I'll not". Never drops letters.
- **Owns:** "dearie", "bill", "itemised", "interest", "on your account", "same bottle, different spoon". Lists of
  prices.
- **Never:** "invoice" or "clause" (Bran's); apologises; says she's lonely. Her tenderness comes out as a lower
  price.
- *(in game)* "One's for fever. One's for husbands. Same bottle. Different spoon."
- *(in game)* "Hester cried. I billed her for the tissue. We're even now. It's horrible. I've never been even with
  anyone."
- "Lie down, dearie. No, the other way. That's the end that bleeds."
- Rewrite note: drop "People think medicine and poison are opposites"; she'd never explain herself that patiently.
- With dialect: "One's for fever. One's for husbands. Same bottle, isn't it. Different spoon."
- With dialect: "Brave, that was. The husband one, you've had. Sit down an hour, dearie."
- With dialect: "Billed her for the tissue, I did. We're even now. Horrible, it is."

### Corporal "Ninefingers" Daro (`ninefingers`, they/them)
- **Who:** Concord deserter who tore up an Erasure order and lost a finger as a "fine". Sharpest tongue in the
  party.
- **Talks:** clipped, sarcastic, military. Insults as affection. Fast comebacks; if a line runs long, they cut
  themselves off.
- **Speech:** Concord army barracks. Drops the subject ("Saw it. Didn't like it."), army slang ("bloody", "kit", "civvies", "stand down"), "sir" as an insult. Numbers and form codes for everything.
- **Owns:** Concord form numbers ("Form C-114"), "dismissed", "on record", counting ("Nine. Always nine."),
  saluting things that don't deserve it.
- **Never:** "darling", "dearie", "handsome"; anything that sounds like a speech. Never asks for pity, and refuses
  it ("Pity's a form too. I don't sign those.").
- *(in game)* "I lost it to a paper cut. Form C-114, Requisition of Requisition Forms. It went septic."
- *(in game)* "First time I've been dead. It's roomier than I expected."
- *(in game)* "They gave me a bigger chin. I'm flattered and offended."
- "Your plan has a hole in it. The hole is you. Fine, let's go."
- With dialect: "Lost it to a paper cut. Form C-114. Went septic. Don't laugh, it's on file."
- With dialect: "Twelve years in. Didn't train us to fight. Trained us to stand still while some sir read at us."
- With dialect: "First time dead. Roomier than expected. Recommend it to civvies."

### Big Ottoline (`ottoline`)
- **Who:** the Crimson Encore's bouncer, Tobble's niece. Shut a door on six people to save a hundred and six.
- **Talks:** few words, door-keeper grammar: commands, checks, verdicts. Warm underneath, and embarrassed about it.
- **Speech:** Northern, like her uncle, but younger and flatter: "were" for "was", "nowt", "our" before family ("our Tobble"), "us" for "me" ("give us a minute"). Not Tobble's "thee/tha".
- **Owns:** lists (who's in, who's out), "house rules" (shared with Fauvette, as two people from the same club;
  hers are about doors, Fauvette's about secrets), chalk, counting people in and out, the waltz.
- **Never:** long confessions without a joke to get out; flirting; fancy words. Doesn't say "darling".
- *(in game)* "Stop. Name?"
- *(in game)* "Thirty years Uncle Tobble's kept a list of who drinks here. I keep the list of who doesn't. It's
  shorter. It's got more teeth in it."
- *(in game)* "You can't subtract people."
- "Coat. Ticket. Out. In that order."
- With dialect: "Stop. Name?"
- With dialect: "Thirty year our Tobble's kept a list of who drinks here. I keep the list of who doesn't. It's shorter. More teeth in it."
- With dialect: "It were the door. Just the door, stood in the white, nowt round it."

### Jessamy Leake (`jessamy`)
- **Who:** night-only smuggler who paid to be struck out of the Ledger and is fading in daylight.
- **Talks:** flirty, quick, conspiratorial. Runs on, then undercuts herself. Uses "you know" and "mind" as
  softeners.
- **Speech:** Tithe Road smuggler. Keeps her h's, drops her g's ("somethin'", "nothin'"), and talks thieves' cant: "cully", "lark", "peach", "flash", "on the cross", "the pennies" for toll men.
- **Owns:** "handsome. Or pretty." (she can't tell what Ash is and enjoys not knowing), crates and boxes nobody
  opens, petty by-law crimes ("rooftop loitering, two counts"), the dark and the sun.
- **Never:** "darling" (Fauvette's); asks what's in a box; states a feeling without immediately stealing
  something to feel normal again.
- *(in game)* "One hummed hymns all the way to Gallows Ferry, very quietly, in a man's voice."
- *(in game)* "When he asked for my occupation, I told him to put 'yes'."
- *(in game)* "I'm sunburnt. It's horrible. I love it. Everything is so loud and yellow."
- Rewrite note: "People think not asking is cowardice. It isn't. It's manners." stacks two watched tells. Keep the
  idea, cut the lecture: "Not asking is good manners. Everyone gets one box nobody looks in."
- With dialect: "Oh, hello, handsome. Or pretty. It's dark, I'm generous, and you're a bit of a blur, cully. Come up."
- With dialect: "Six years runnin' crates down the Tithe Road and never once opened one. Not openin' is good manners."
- With dialect: "Nobody peaches on me twice. Fennick learned that one the expensive way."

### Odile Penhallow (`odile`)
- **Who:** ex-Concord tax collector who walked out with the ledger. Chief Assessor's daughter.
- **Talks:** formal, exact, slightly prim. Full sentences, no contractions when she's on duty. Turns everything
  into an entry, a column, a valuation. Dry jokes delivered like minutes of a meeting.
- **Speech:** Concord gentry, Chief Assessor's daughter. No contractions on duty, "one" for "you", "rather", "I should think", Latinate words. Contractions only slip in when she's moved, and she notices.
- **Owns:** "declare", "enter it", "column", "assets / liabilities", "on the record", "fair", red ink then black
  ink.
- **Never:** "bill" (Gristle's) or "books" (Quill's); rounds anything; swears. Doesn't hug first.
- *(in game)* "Noted. 'Nerve, considerable, undeclared until now.' I'll value it later. It's going to ruin my
  totals."
- *(in game)* "A tithe is a tenth, and a tenth is a tenth whether you're a duke or a donkey."
- *(in game)* "Quill rounds up. I would like that on the record."
- Rewrite note: "People think tax collectors hate people..." is the third "People think"; open on the sums
  instead: "Tax collectors don't hate people. We love sums. People simply get in the way."
- With dialect: "Sit down. This will not hurt. Much. I am opening an account for you."
- With dialect: "One does not round. One records. Quill rounds, and I should like that on the record."
- With dialect: "Thank you. I am not... It is the red ink. It gets in one's eyes."

### Fauvette (`velvette`)
- **Who:** cabaret duelist and secret-broker (stage name of Colombe Brissot). Killed eleven "volunteers" on stage.
  Separate person from Hortense.
- **Talks:** theatrical, long elegant sentences, then a short cruel one. Always performing, so the rare plain line
  hits hard.
- **Speech:** The Velvet Causeway. On stage (which is always): grand English with French dropped in ("chérie", "voilà", "enfin", "mon petit") and French word order ("A secret, it is only dangerous while one person owns it."). Underneath, Colombe Brissot from the Causeway quays: when she is sincere, the French and the flourishes drop away and a short, blunt voice comes out. That shift is her most important line in any scene.
- **Owns:** "darling", the French words in 4.3, "house rules: a secret for a secret", stage words (closing act, curtain, house, bow), "my
  book".
- **Never:** "handsome. Or pretty." (Jessamy's); grovels; explains her own feelings at length. When she's sincere
  she gets shorter.
- *(in game)* "Don't touch the sword, darling. It's the only one in the room who isn't flirting with you."
- *(in game)* "Eleven. I knew by the third. I kept going, because the other choice was to be the next volunteer."
- *(in game)* "When the Blank took Lantern Row I was almost grateful. Isn't that ugly? I've never said it out
  loud."
- "Applause is a debt, darling. I always collect."
- With dialect: "Don't touch the sword, chérie. It is the only one in the room who isn't flirting with you."
- With dialect: "Voilà, the closing act. A real duel, live blades, a volunteer from the house. Enfin, a man confesses much with a rapier at his throat."
- With dialect: (sincere) "Eleven. I knew by the third. Kept going. Other choice was being the twelfth."

### Edwin "Quill" Pask (`quill`)
- **Who:** quartermaster at the Command Table; kept Hollowmark's books for the Concord, now cooks them for you.
- **Talks:** precise, a little fussy, self-deprecating. The longest sentences in the cast when he's explaining
  money; very short when it's personal. Reads documents aloud in "the voice they deserve".
- **Speech:** Concord clerk, lower office, Hollowmark born. Officialese he can't switch off ("per", "herewith", "duly", "as it were", "in respect of"), used half as a joke. Correct grammar, but a clerk's correct, not a gentleman's.
- **Owns:** "the beautiful books / the true books", "file", "receipt", "written off / carried forward", turnips,
  the goose.
- **Never:** fights ("I don't fight. I want to be very clear about that."); "declare" (Odile's); says his guilt
  out loud except as a list of names.
- *(in game)* "A quartermaster keeps two sets of books. One for the Concord, which is beautiful. One for us, which
  is true."
- *(in game)* "Name: none. Debts: none. Taxable property: one cloak, scorched."
- *(in game)* "I once lost an argument with a goose. Stay close to me."
- "I've moved forty Gilt from 'roads' to 'not dying'. The roads will understand."
- With dialect: "A quartermaster keeps two sets of books, per regulations. One for the Concord, which is beautiful. One for us, which is true."
- With dialect: "Name: none. Debts: none. Taxable property: one cloak, scorched, herewith noted."
- With dialect: "I have duly moved forty Gilt from roads to not dying. The roads will understand, as it were."

### Sister Hild (`abeyance`)
- **Who:** runaway Abbey scribe with a page that rewrites itself every night; hears the erased.
- **Talks:** gentle, rambling, oddly matter-of-fact about the uncanny. Apologises for being too much. Starts a
  thought, gets distracted by the page, comes back.
- **Speech:** Saint Ledger's Abbey. Gentle, old-fashioned church English ("I think it a promise", "God keep you"), half-remembered Latin tags ("Deo gratias", "fiat"), "the Abbot used to say". Formal when quoting, rambling and contracted otherwise.
- **Owns:** "the page" (treated as a person with manners), "the voices" (polite, ask for directions), margins,
  serifs, "Oh."
- **Never:** sounds frightened of the uncanny; uses Abbey jargon without mocking it; delivers a second big
  quotable line in the same act (she has one).
- *(in game)* "They're very polite. They say please. They say excuse me. They ask what year it is."
- *(in game)* "It also said you'd be taller, so it isn't always right."
- *(in game)* "It usually just complains about my spelling."
- "The page has been very rude about your handwriting. I said you don't have any. It wasn't listening."
- With dialect: "The page rewrote itself again. Deo gratias, I copied it before breakfast."
- With dialect: "I don't know if it's a warning or a promise. I think it a promise. The Abbot would say that is pride."
- With dialect: "They're very polite, the voices. They say please. They ask what year it is. God keep them, they're lost."

### Old Tobble (`tobble`)
- **Who:** tavern keeper about to retire for thirty years. Trades in secrets.
- **Talks:** chatty, warm, a bit rambling, northern-ish ("Aye", "lad", "love", "mind"). Tells stories that go
  sideways. Calls everyone younger than him by a pet name.
- **Speech:** Broad Northern, old-fashioned: "aye", "nowt", "owt", "summat", "were" for "was", "lad", "lass", "love", "reckon". Goes to "thee" and "tha" when he's moved.
- **Owns:** "aye", "love", "retiring next week", knees, "first drink's free", secrets as currency, the Last Drop.
- **Never:** sounds sharp or cruel (that's Ottoline and Daro); says a secret for free unless it's the one that
  hurts.
- *(in game)* "Retiring next week. Got a cottage picked out. Frayed Meadow, by the brook. Roses."
- *(in game)* "I told him. Next morning the cellar was clean. Not empty. Clean. White as new paper." (keep: this is
  the one correction that earns its place)
- *(in game)* "Got her! Run! Well, you run. I'll do something near it."
- Rewrite note: "Now you know" closes two of his confessions; keep one.
- With dialect: "First drink's free. House rule. Second costs thee a secret."
- With dialect: "I told him. Next morning the cellar were clean. Not empty. Clean. White as new paper."
- With dialect: "Got her! Run! Well, tha run. I'll do summat near it."

### Hortense, the Velvet Marquise (`hortense`)
- **Who:** Causeway aristocrat and the Concord's Office of Corrections' best informant, until she brings you her sister's
  debt instead of your name. Her spying is the Chapter 3 twist and it is a decoy: she is never the betrayer (#186).
  Separate person from Fauvette; they share a scene (`ch3_two_rapiers`) and dislike each other on sight.
- **Talks:** light, quick, amused. Flirts with everyone, enemies included, and it is a little too well rehearsed.
  When it matters she drops the charm and gives you the plain fact in one sentence.
- **Speech:** Causeway aristocracy: perfect court English, French used correctly and rarely ("Mesdames", "enfin"
  at most once a scene). No contractions when she is being the Marquise; contractions slip in with Bérénice.
- **Owns:** "sweet" as an endearment, invitations, forks, "stepped out for air", the codes she and Bérénice share.
- **Never:** "darling" (Fauvette's); stage words (Fauvette's); begs; says she is sorry in so many words. She shows it
  by paying.
- *(in game)* "I have stepped out for air with half the Concord's nobility. I always came back in with the story
  and they came back in poorer."
- *(in game)* "Do not look so pleased. I need somewhere that is not here, and you need someone who knows which fork
  the Nobility stab each other with."
- *(in game)* "Bérénice. I remember every code we ever had. The tapping one. The one with the fan. The one Papa
  never broke."

### Saffron Kiss (`saffron`)
- **Who:** cabaret singer from Lantern Quay (registered name Maud Pickering). Her songs turn into small, real
  places while she sings them and fade when she stops. One song has had no last verse for eleven years.
- **Talks:** warm, teasing, a performer between sets. Talks in half-lyrics she has not finished; rhymes by accident
  and pretends she meant it. Goes quiet and very plain about her mother.
- **Speech:** Lantern Quay, working waterfront: "love" for everyone, "Mam", dropped g's now and then ("singin'"),
  "proper" in Saffron's mouth means "finished". No French; the quay is not the Causeway.
- **Owns:** "love", "the last verse", "a good song one day", lyrics, gin.
- **Never:** "darling" (Fauvette's); "sweet" (Hortense's); explains what a song means.
- *(in game)* "No hard feelings, love. Well. Some. They'll make a good song one day."
- *(in game)* "I'm writing a song about tonight. I'm going to finish it. You see if I don't."
- *(in game)* "The house is gone now. It went when the song went, like songs do."

### Nan Cripps and Tally (`nan`, `tally`)
- **Who:** a cheerful grifter who sold her conscience at fifteen to old Pratt the moneylender. It came back as
  Tally, her talking shadow, who cannot lie and keeps telling people the truth about her. They fight as a pair.
- **Talks:** Nan: fast, chatty, flattering, every story a little bigger than the last. Tally: flat, literal,
  brief, and always right; speaks only when the truth is being bent. They are a double act and Tally gets the last
  line.
- **Speech:** Nan is Hollowmark-born (over the cobbler's) and puts on whatever accent the mark wants; at rest she
  has Bran's docks speech, softer: "'em", "ain't", "proper". Tally speaks correct, plain English with no accent at
  all, like a ledger reading itself.
- **Owns:** Nan: "mark", "clause", "the trade", "terms". Tally: corrections of fact, "I do not have hands", "the
  collateral" (meaning itself).
- **Never:** Nan admits a lie unless Tally makes her. Tally lies, jokes on purpose, or uses Bran's either/or verdict.
  Tally's line is one fact, not a judgement.
- *(in game)* Nan: "People ask how I got into the trade. I tell 'em I was born in a Frayed Meadow hedge and raised
  by a travelling bishop. It's half true." Tally: "None of it is true. She was born in Hollowmark, over the
  cobbler's. Her mother taught arithmetic."
- *(in game)* Tally: "It shook my hand. I do not have hands."
- *(in game)* Tally: "'The debt falls due at the new moon. The collateral will be recovered.' The collateral is me."

### Light recruits
Short lines (quips, hooks, a line or two in town). One clear angle each; never a mini-speech.

| Who | Talks like | Owns | Never |
|---|---|---|---|
| **Pell Mossop** (`pell`), gravedigger | soft, cheerful, unsettling; apologises for measuring you. Gutterwoods farm speech: "reckon", "ar", "proper" ("Proper lovely shape, you are.") | sizes, holes, "ready" | explains how he knows |
| **Hetty Coyne** (`hesper`), cartographer | brisk, offended by blank space, talks about places in future tense. Educated town speech, surveyor's jargon ("bearing", "chain", "datum") | "There's a road here on Thursday." | describes a place she hasn't drawn |
| **Dunmore Vellacott** (`dunmore`), debt-tattooed cobbler | polite, ground-down, counts debts in body parts. Hollowmark working man, deferential: "miss", "sir", "if it please" | elbows, forearms, "paid off" | complains |
| **Mr. Biscuits** (`biscuits`) | one bark or growl, then a narrated bracket explaining his dignity | the bracket | words |
| **The Merrow Three** (`merrow`) | one voice between three girls, in capitals when they sing; finish each other's lines. Unfinished Coast Cornish: "proper", "dreckly", "my bird", "where's that to?" | the hot-coal voice | speak at the same time in normal text |

### Saint Verity Hale (`verity`), antagonist
- **Talks:** polite, tired, dry, genuinely kind. Long, well-built sentences, like a good archivist's letter.
  Apologises for things she'll still do. Never raises her voice.
- **Speech:** Concord high office, the bookish end: long, elegant, educated sentences, no slang, gentle formality ("I should think", "rather"). Her letters read exactly as she speaks.
- **Owns:** "drafts", "the clean page", "fondly", gentle corrections of other people's words.
- **Never:** gloats, threatens, monologues about power, or calls the Blank a weapon (to her it "helps").
- *(in game)* "Oh. So you're the one it gave back. How rude of it. It never gives anything back."
- *(in game)* "Please stop pushing the white back. It is only trying to help. Fondly, and with regret for what
  comes next: V. Hale."
- With dialect: "Oh. So you are the one it gave back. How rude of it. It never gives anything back, you know."

### The Auditor (`auditor`), Act 1 boss
- **Talks:** procedural. No contractions, no humour he's aware of. Paperwork as violence. Breaks down into broken
  sentences when the procedures fail.
- **Speech:** Concord officialese at its coldest: passive voice, "duly", "herewith", "it has been noted". No contractions, ever.
- **Owns:** "irregular", "discrepancy", "notice", capitals for FINAL NOTICE.
- *(in game)* "Hold still. This will not hurt. Nothing that never happened can hurt."
- *(in game)* "There is no form for it. There is no form for YOU."
- With dialect: "It has been noted that you are not on the Ledger. Your town will duly join you."

### The Vacancy (`vacancy`)
Speaks only in redacted text: black bars, with the occasional terribly clear word (DESIGN.md section 11). It never
explains, threatens, or says "I". Its clear words are small and domestic ("door", "supper", "mother"), never
cosmic. No "I am the void" lines, ever.
- **How to write it:** wrap every word that is struck in `[[double brackets]]`; the game draws them as ink bars
  (scripts/dialogue.gd draw_text). Write real words under the bars (they set the bar's length, and a translator
  sees them), and leave one to three plain words per line. It is staged as a hole in the page, no portrait.
- First written for the betrayal (#186): "[[Six]] coats. [[Six]] [[tickets]]. [[Supper]] [[on]] [[the]] [[table]]. home."
  and, to Bran, a single plain "yes." before he has finished naming his price.

### One-scene people
Each gets one note of colour. Concord officials are the funniest when they're completely sincere.

| Who | Note |
|---|---|
| Clerk Pettigrew (`clerk`) | Kafka at a counter: polite, logical, terrifying, pure officialese. "There is, in fact, nothing at all where you are standing." |
| Concord Warden (`warden`), Tithe-Captain Morrow (`captain`) | Officials reading out charges like a menu. |
| Governor Thale (`governor`) | Pompous gentry ("I say", "one shall"); bluster and paperwork threats; runs away mid-sentence. |
| Ozias Crane (`crane`) | Silk-voiced contract broker; talks about people as stock that "appreciates". Gallows Ferry docks under a bought gentleman's polish: an h drops when he panics. |
| Hester Vane (`hester`) | Coven elder; grave, guilty, formal; hides behind "the tree decides". Gristle's Border speech, but stately ("Thought of it every day, I have."). |
| Notary Fennick (`marrow`) | Panicky, procedural, terrified of being audited himself. Officialese that falls apart under stress. |
| Marguerite Penhallow (`penhallow`) | Odile, thirty years harder. High-office English, no contractions. Shortest sentences in the game. "Audit. Me." |
| Augustin Sallow (`sallow`) | Impresario patter, applause cues, "darling" (borrowed from his star), Causeway French laid on thick and slightly wrong. Blames "the commissions". |

### Chapter 2 people (Saint Ledger's and the Erasers)
Abbey people share Hild's church English (4.2), each at a different pitch. The Erasers speak like Verity's
readers: educated, sincere, unhurried.

| Who | Note |
|---|---|
| Brother Odo (`odo`) | The Abbey's walking messenger. Plain, patient, quietly funny about disaster ("sent me back with a receipt"). No Latin; he is a lay brother. |
| Prioress Ebba (`ebba`) | Dry, exact, very tired. No contractions in authority, short orders, then one plain human line. Calls Ash "keeper" or "passer-by". |
| Abbot Wulfstan (`wulfstan`) | Liturgical and certain. "Fidelity", "the Rule", "the Office". Royal "we" when he copies himself. Never raises his voice until the Second Copy. |
| First Reader Askew (`askew`) | Warm, unhurried, sincere. Reads a name before every fire and means it. Calls people "sweet". Never sneers. |
| Sister Osyth (`osyth`) | Crypt-keeper. Counts out loud ("Eleven thousand four hundred and five"). Blunt, contracted, no Latin. Cares about the count more than about you, and says so. |
| Nell Tapper (`nell`) | Candleford chandler. Brisk town speech, short sentences, money and draughts. Lists her jobs and the wages she isn't paid. |
| Brother Cuthbert (`cuthbert`) | Deaf bell-ringer: capitals when he mishears ("WHAT? Oh. A job."). Big, gentle, literal. |
| Brother Alcuin (`alcuin`) | Returned Eraser novice. Earnest, guilty, bookish; quotes the drafts and then argues with them. |
| Sister Mildred (`mildred`) | Illuminator. Brisk, dry, practical; talks about her margin animals like unruly livestock that need dealing with. A little church Latin only when it's in a manuscript ("Deus"). |
| Joan Tull (`joan`) | Candleford barge pilot. Flat, short statements; measures everything in poles and hands. Thanks you once, briefly, and moves on. |
| Rafe Thwaite (`rafe`) | Whitewasher. Slow Midlands working speech ("'em", "she'd a look on her"); prices every job in walls and shillings. Sorry for the forty walls, never says so: he scrapes them. |
| Sib Varley (`sib`, they/them) | Relic-seller. A pedlar's patter, smooth and cheerful, a price in every other line. Owns "friend". Never admits a relic is fake. |

### Chapter 3 people (the Velvet Causeway)
Causeway nobles share Hortense's court English (4.2); quay people share Saffron's. The Host has no dialect.

| Who | Note |
|---|---|
| Duc de Lantenay (`lantenay`) | Master of ceremonies at the Host's table. Exquisite manners laid over total cowardice; announces horrors as courses ("those of you who are not the course"). |
| Purser Gaudin (`gaudin`) | Hortense's handler at the Office of Corrections. Polite, dry, transactional: everyone is an account, Hortense is "Marquise", a betrayal is "paid in full". |
| The Host (`host`) | Chapter 3 boss. The Causeway's party that never ended, grown a mouth. ALL CAPITALS, short shouted sentences, food and guests and the table. Never a joke on purpose. |
| Bérénice de Saulx (`berenice`) | Hortense's sister, seventeen, sold as a copyist. Sharp, quick, unimpressed; spells messages in first letters. |
| Proctor Dufresne (`proctor`) | Head of the copyists' school. Precise, cold, a bursar's English; talks about pupils as fees. |
| Annie Pickering, "Mam" (`mam`) | Saffron's mother. North-of-the-quay plain speech, short and dry, waiting eleven years for a last verse. Brings up Saffron's father in every scene. |
| Old Pratt (`pratt`) | Moneylender. Soft-spoken, exact about percentages, calls Nan "my dear". Contracts read like prayers. |
| Ida Lumley (`ida`) | Lantern Quay pawnbroker. Quay plain speech ("thirty year", "folk"), dry, discreet; knows everyone's secrets by what they pawn and tells none of them. No "love" (Saffron's). |
| Clément de Cressy (`clement`) | Ruined viscount, dancing master. Court English without contractions, vain and cheerfully cowardly; makes his losses into anecdotes. No "sweet" (Hortense's). |
| Josette Roux (`josette`) | Runaway copyist. Quick, flat, unimpressed, like Bérénice; short sentences about hands, signatures and forms. |
| Firmin Gosse (`firmin`) | The Host's under-cook. Gruff kitchen talk; won't discuss the main course, will discuss sauces at length. Every joke about food has a floor under it. |
| Rémy Morel (`remy`, they/them) | Duel second. Light, flirty, businesslike; quotes rates for first blood and for the death. Talks about their four paper deaths like bad jobs. |

### Not built yet
Seeds for chapters #28 to #32; flesh these out into full sheets when the character is written.

- **Ilse of the Mirror:** a reflection that walked out when her original was erased. Vain, precise, slightly
  backwards: describes things left-to-right reversed, compliments herself in the third person, never says "I
  remember".
- **Cass & Kit Pruett:** twin chemists who disagree about everything; never finish each other's sentences, they
  contradict them.
