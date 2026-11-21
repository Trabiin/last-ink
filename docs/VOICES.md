# Voices

How the people of Last Ink talk, and the prose habits that make writing read as machine-made. Issue #167.

**Why:** writing is the second most-named AI complaint in Steam reviews (research in the project files,
`last-ink/research/ai-reception.md`). We say openly that AI helped make the game (docs/AI_USE.md), but a line
that *sounds* generated costs us the player's trust in everything around it. [NAMING.md](NAMING.md) does this job
for names; this file does it for prose.

**How to use it:**
- Before writing or editing a character's lines, read their sheet (section 4). Cover the speaker name and read
  the line back: if it could be anyone's, rewrite it.
- `tests/test_voice.gd` enforces the hard bans (section 2.1) and punctuation (section 3) on every push, and
  prints a count of the softer tells (section 2.2) so we can watch them go down.
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
> (eyes) glinting / sparkling with · something shifted

An ink-and-paper world makes some of these extra tempting ("indelible", "palimpsest", "echoes of erased names").
That's exactly why they're banned: they're the first thing a model reaches for here.

### 2.2 Watched (counted, not failed yet)

These aren't wrong once. They're tells when they repeat, or when every character does them. `tests/test_voice.gd`
counts them on every run (`VOICE_REPORT=1` lists each hit). Step two of #167 rewrites the excess and turns the
count into a limit.

| Tell | What it looks like | Rule |
|---|---|---|
| **"People think X"** | "People think medicine and poison are opposites." | A lecture opener. Three characters use it now (Gristle, Jessamy, Odile). Keep at most one in the whole script |
| **The correction** | "Not empty. Clean." · "It isn't cowardice. It's manners." | Strong once a chapter. As a habit it's the "it's not X, it's Y" tell in short form |
| **The either/or verdict** | "That's either very smart or very stupid." · "Must be nice. Or terrifying." | Bran and Jessamy share it now. Give it to one (section 4) |
| **The "Or X." afterthought** | "Or sell it. Or forget whose I was." | Owned by Jessamy ("handsome. Or pretty.") and Bran (escalating options). Others drop it |
| **Fragment triplets** | "Streets. Families. Whole towns." | One per scene at most. Owned by nobody |
| **Stated feelings** | "I'm not crying." · "I feel so guilty." | Rewrite as action or deflection (house rule 2) |
| **Moral tags** | "Now you know." · "That's the whole art." · "That isn't nothing." | A neat button on the end of a confession. Cut it or swap for an action |
| **Soft-fantasy words** | journey, realm, embark, unravel, whisper(ing), truly, deeply | Not banned, but each needs a reason. Tobble's "whispering's my trade" is fine; a narrator who whispers every scene isn't |
| **Somebody else's word** | Anyone but Gristle saying "dearie" | Each sheet lists words a character owns. Others don't use them |

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

## 4. Voice sheets

Each sheet: how they talk, their tics (words and moves they own), what they never say, and sample lines. Lines
marked *(in game)* are from the current script and show the voice at its best; unmarked lines are new examples
written to this sheet.

### Narrator
- **Talks:** present tense, plain, dry. Short sentences. Hands, objects, weather, the Blank's behaviour. One odd
  detail per scene does more than three adjectives.
- **Tics:** treats the Blank like a sulking animal ("sulking that it let you go"). Deadpan understatement.
- **Never:** tells the player how a character feels; uses "whisper" for wind; ends on a moral.
- *(in game)* "He polishes a mug that was clean when he started."
- *(in game)* "The tollgate is too quiet. Someone has swept the road. Someone has swept the birds off it, too."
- *(in game)* "It is a neat white hole now, with a few desks at the edge, still being filed."

### Brannoc "Bran" Tolley (`bran`)
- **Who:** sellsword, contract tattooed on his arm. Gallows Ferry dock kid. Can't read, can count.
- **Talks:** short, blunt, transactional. Talks about feelings only as costs. Lists options in escalating order.
- **Owns:** "clause" (numbered clauses of his contract), "invoice", "hazard pay", "on the bill", calling Ash
  "smudge". The escalating "Or X. Or Y." list. The either/or verdict ("That's either very smart or very
  stupid").
- **Never:** says thank you straight; admits he likes anyone without calling it disgusting; uses long words.
  Swears like a docker, but rarely on screen.
- *(in game)* "It tightens if I break it. Like a fist. Ask me how I know."
- *(in game)* "So the contract's with nobody now. Which means I'm here because I want to be. Disgusting."
- *(in game)* "Don't look at me. I can't read. I can count, though, and that sign's going the wrong way."
- "Clause six. If the client dies, I keep the deposit. Don't make me use clause six."

### Mother Gristle (`gristle`)
- **Who:** hedge-witch healer thrown out of the Coven; her medicines and poisons are the same bottles.
- **Talks:** sweet-voiced and poisonous. Bedside manner of a loan shark. Medium sentences with a sting at the end.
- **Owns:** "dearie", "bill", "itemised", "interest", "on your account", "same bottle, different spoon". Lists of
  prices.
- **Never:** "invoice" or "clause" (Bran's); apologises; says she's lonely. Her tenderness comes out as a lower
  price.
- *(in game)* "One's for fever. One's for husbands. Same bottle. Different spoon."
- *(in game)* "Hester cried. I billed her for the tissue. We're even now. It's horrible. I've never been even with
  anyone."
- "Lie down, dearie. No, the other way. That's the end that bleeds."
- Rewrite note: drop "People think medicine and poison are opposites"; she'd never explain herself that patiently.

### Corporal "Ninefingers" Daro (`ninefingers`, they/them)
- **Who:** Concord deserter who tore up an Erasure order and lost a finger as a "fine". Sharpest tongue in the
  party.
- **Talks:** clipped, sarcastic, military. Insults as affection. Fast comebacks; if a line runs long, they cut
  themselves off.
- **Owns:** Concord form numbers ("Form C-114"), "dismissed", "on record", counting ("Nine. Always nine."),
  saluting things that don't deserve it.
- **Never:** "darling", "dearie", "handsome"; anything that sounds like a speech. Never asks for pity, and refuses
  it ("Pity's a form too. I don't sign those.").
- *(in game)* "I lost it to a paper cut. Form C-114, Requisition of Requisition Forms. It went septic."
- *(in game)* "First time I've been dead. It's roomier than I expected."
- *(in game)* "They gave me a bigger chin. I'm flattered and offended."
- "Your plan has a hole in it. The hole is you. Fine, let's go."

### Big Ottoline (`ottoline`)
- **Who:** the Crimson Encore's bouncer, Tobble's niece. Shut a door on six people to save a hundred and six.
- **Talks:** few words, door-keeper grammar: commands, checks, verdicts. Warm underneath, and embarrassed about it.
- **Owns:** lists (who's in, who's out), "house rules" (shared with Fauvette, as two people from the same club;
  hers are about doors, Fauvette's about secrets), chalk, counting people in and out, the waltz.
- **Never:** long confessions without a joke to get out; flirting; fancy words. Doesn't say "darling".
- *(in game)* "Stop. Name?"
- *(in game)* "Thirty years Uncle Tobble's kept a list of who drinks here. I keep the list of who doesn't. It's
  shorter. It's got more teeth in it."
- *(in game)* "You can't subtract people."
- "Coat. Ticket. Out. In that order."

### Jessamy Leake (`jessamy`)
- **Who:** night-only smuggler who paid to be struck out of the Ledger and is fading in daylight.
- **Talks:** flirty, quick, conspiratorial. Runs on, then undercuts herself. Uses "you know" and "mind" as
  softeners.
- **Owns:** "handsome. Or pretty." (she can't tell what Ash is and enjoys not knowing), crates and boxes nobody
  opens, petty by-law crimes ("rooftop loitering, two counts"), the dark and the sun.
- **Never:** "darling" (Fauvette's); asks what's in a box; states a feeling without immediately stealing
  something to feel normal again.
- *(in game)* "One hummed hymns all the way to Gallows Ferry, very quietly, in a man's voice."
- *(in game)* "When he asked for my occupation, I told him to put 'yes'."
- *(in game)* "I'm sunburnt. It's horrible. I love it. Everything is so loud and yellow."
- Rewrite note: "People think not asking is cowardice. It isn't. It's manners." stacks two watched tells. Keep the
  idea, cut the lecture: "Not asking is good manners. Everyone gets one box nobody looks in."

### Odile Penhallow (`odile`)
- **Who:** ex-Concord tax collector who walked out with the ledger. Chief Assessor's daughter.
- **Talks:** formal, exact, slightly prim. Full sentences, no contractions when she's on duty. Turns everything
  into an entry, a column, a valuation. Dry jokes delivered like minutes of a meeting.
- **Owns:** "declare", "enter it", "column", "assets / liabilities", "on the record", "fair", red ink then black
  ink.
- **Never:** "bill" (Gristle's) or "books" (Quill's); rounds anything; swears. Doesn't hug first.
- *(in game)* "Noted. 'Nerve, considerable, undeclared until now.' I'll value it later. It's going to ruin my
  totals."
- *(in game)* "A tithe is a tenth, and a tenth is a tenth whether you're a duke or a donkey."
- *(in game)* "Quill rounds up. I would like that on the record."
- Rewrite note: "People think tax collectors hate people..." is the third "People think"; open on the sums
  instead: "Tax collectors don't hate people. We love sums. People simply get in the way."

### Fauvette (`velvette`)
- **Who:** cabaret duelist and secret-broker (stage name of Colombe Brissot). Killed eleven "volunteers" on stage.
  Separate person from Hortense.
- **Talks:** theatrical, long elegant sentences, then a short cruel one. Always performing, so the rare plain line
  hits hard.
- **Owns:** "darling", "house rules: a secret for a secret", stage words (closing act, curtain, house, bow), "my
  book".
- **Never:** "handsome. Or pretty." (Jessamy's); grovels; explains her own feelings at length. When she's sincere
  she gets shorter.
- *(in game)* "Don't touch the sword, darling. It's the only one in the room who isn't flirting with you."
- *(in game)* "Eleven. I knew by the third. I kept going, because the other choice was to be the next volunteer."
- *(in game)* "When the Blank took Lantern Row I was almost grateful. Isn't that ugly? I've never said it out
  loud."
- "Applause is a debt, darling. I always collect."

### Edwin "Quill" Pask (`quill`)
- **Who:** quartermaster at the Command Table; kept Hollowmark's books for the Concord, now cooks them for you.
- **Talks:** precise, a little fussy, self-deprecating. The longest sentences in the cast when he's explaining
  money; very short when it's personal. Reads documents aloud in "the voice they deserve".
- **Owns:** "the beautiful books / the true books", "file", "receipt", "written off / carried forward", turnips,
  the goose.
- **Never:** fights ("I don't fight. I want to be very clear about that."); "declare" (Odile's); says his guilt
  out loud except as a list of names.
- *(in game)* "A quartermaster keeps two sets of books. One for the Concord, which is beautiful. One for us, which
  is true."
- *(in game)* "Name: none. Debts: none. Taxable property: one cloak, scorched."
- *(in game)* "I once lost an argument with a goose. Stay close to me."
- "I've moved forty Gilt from 'roads' to 'not dying'. The roads will understand."

### Sister Hild (`abeyance`)
- **Who:** runaway Abbey scribe with a page that rewrites itself every night; hears the erased.
- **Talks:** gentle, rambling, oddly matter-of-fact about the uncanny. Apologises for being too much. Starts a
  thought, gets distracted by the page, comes back.
- **Owns:** "the page" (treated as a person with manners), "the voices" (polite, ask for directions), margins,
  serifs, "Oh."
- **Never:** sounds frightened of the uncanny; uses Abbey jargon without mocking it; delivers a second big
  quotable line in the same act (she has one).
- *(in game)* "They're very polite. They say please. They say excuse me. They ask what year it is."
- *(in game)* "It also said you'd be taller, so it isn't always right."
- *(in game)* "It usually just complains about my spelling."
- "The page has been very rude about your handwriting. I said you don't have any. It wasn't listening."

### Old Tobble (`tobble`)
- **Who:** tavern keeper about to retire for thirty years. Trades in secrets.
- **Talks:** chatty, warm, a bit rambling, northern-ish ("Aye", "lad", "love", "mind"). Tells stories that go
  sideways. Calls everyone younger than him by a pet name.
- **Owns:** "aye", "love", "retiring next week", knees, "first drink's free", secrets as currency, the Last Drop.
- **Never:** sounds sharp or cruel (that's Ottoline and Daro); says a secret for free unless it's the one that
  hurts.
- *(in game)* "Retiring next week. Got a cottage picked out. Frayed Meadow, by the brook. Roses."
- *(in game)* "I told him. Next morning the cellar was clean. Not empty. Clean. White as new paper." (keep: this is
  the one correction that earns its place)
- *(in game)* "Got her! Run! Well, you run. I'll do something near it."
- Rewrite note: "Now you know" closes two of his confessions; keep one.

### Light recruits
Short lines (quips, hooks, a line or two in town). One clear angle each; never a mini-speech.

| Who | Talks like | Owns | Never |
|---|---|---|---|
| **Pell Mossop** (`pell`), gravedigger | soft, cheerful, unsettling; apologises for measuring you | sizes, holes, "ready" | explains how he knows |
| **Hetty Coyne** (`hesper`), cartographer | brisk, offended by blank space, talks about places in future tense | "There's a road here on Thursday." | describes a place she hasn't drawn |
| **Dunmore Vellacott** (`dunmore`), debt-tattooed cobbler | polite, ground-down, counts debts in body parts, says "miss" | elbows, forearms, "paid off" | complains |
| **Mr. Biscuits** (`biscuits`) | one bark or growl, then a narrated bracket explaining his dignity | the bracket | words |
| **The Merrow Three** (`merrow`) | one voice between three girls, in capitals when they sing; finish each other's lines | the hot-coal voice | speak at the same time in normal text |

### Saint Verity Hale (`verity`), antagonist
- **Talks:** polite, tired, dry, genuinely kind. Long, well-built sentences, like a good archivist's letter.
  Apologises for things she'll still do. Never raises her voice.
- **Owns:** "drafts", "the clean page", "fondly", gentle corrections of other people's words.
- **Never:** gloats, threatens, monologues about power, or calls the Blank a weapon (to her it "helps").
- *(in game)* "Oh. So you're the one it gave back. How rude of it. It never gives anything back."
- *(in game)* "Please stop pushing the white back. It is only trying to help. Fondly, and with regret for what
  comes next: V. Hale."

### The Auditor (`auditor`), Act 1 boss
- **Talks:** procedural. No contractions, no humour he's aware of. Paperwork as violence. Breaks down into broken
  sentences when the procedures fail.
- **Owns:** "irregular", "discrepancy", "notice", capitals for FINAL NOTICE.
- *(in game)* "Hold still. This will not hurt. Nothing that never happened can hurt."
- *(in game)* "There is no form for it. There is no form for YOU."

### The Vacancy (not written yet)
Speaks only in redacted text: black bars, with the occasional terribly clear word (DESIGN.md section 11). It never
explains, threatens, or says "I". Its clear words are small and domestic ("door", "supper", "mother"), never
cosmic. No "I am the void" lines, ever.

### One-scene people
Each gets one note of colour. Concord officials are the funniest when they're completely sincere.

| Who | Note |
|---|---|
| Clerk Pettigrew (`clerk`) | Kafka at a counter: polite, logical, terrifying. "There is, in fact, nothing at all where you are standing." |
| Concord Warden (`warden`), Tithe-Captain Morrow (`captain`) | Officials reading out charges like a menu. |
| Governor Thale (`governor`) | Bluster and paperwork threats; runs away mid-sentence. |
| Ozias Crane (`crane`) | Silk-voiced contract broker; talks about people as stock that "appreciates". |
| Hester Vane (`hester`) | Coven elder; grave, guilty, formal; hides behind "the tree decides". |
| Notary Fennick (`marrow`) | Panicky, procedural, terrified of being audited himself. |
| Marguerite Penhallow (`penhallow`) | Odile, thirty years harder. Shortest sentences in the game. "Audit. Me." |
| Augustin Sallow (`sallow`) | Impresario patter, applause cues, "darling" (borrowed from his star). Blames "the commissions". |

### Not built yet
Seeds for chapters #28 to #32; flesh these out into full sheets when the character is written.

- **Hortense, the Velvet Marquise:** flirts with everyone, enemies included, mid-fight; a spy, so her flirting is
  a little too well-rehearsed. Must sound nothing like Fauvette: Hortense is aristocratic and light, Fauvette is
  showbusiness and dark. No "darling" (Fauvette's); her word is "sweet".
- **Ilse of the Mirror:** a reflection that walked out when her original was erased. Vain, precise, slightly
  backwards: describes things left-to-right reversed, compliments herself in the third person, never says "I
  remember".
- **Saffron Kiss** (registered name Maud Pickering): cabaret singer; talks in lyrics she hasn't finished writing.
- **Nan Cripps & Tally:** Nan is a cheerful liar; Tally, her talking shadow, is the honest one and hates it.
- **Cass & Kit Pruett:** twin chemists who disagree about everything; never finish each other's sentences, they
  contradict them.
