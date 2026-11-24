# Crash reports and player feedback (issue #146)

How the game records problems, how players send reports, where reports land, and how Claude turns
them into GitHub issues. What players are told is in [PRIVACY.md](PRIVACY.md).

## In the game

| Piece | Where | What it does |
|---|---|---|
| Session log | `scripts/diag.gd` (autoload `Diag`) | `user://logs/session.log`: game version, build, OS, CPU, GPU, renderer, screen, then a timestamped line whenever the scene, mission or save slot changes. Last 5 sessions kept (`session.1.log` = the one before). |
| Engine log | Godot | Desktop only: `user://logs/godot.log` (plus `godot<date>.log` for earlier sessions) holds every error and warning. Diag prints its breadcrumbs there too (`[last-ink] ...`), so each error sits between "where the player was" lines. The web build has no engine log, so Diag copies the browser console's errors and warnings into `session.log`. |
| Crash / error notice | `Diag.previous`, `title.gd _offer_report` | Desktop: a session that never reached a clean exit (`session.lock` left behind) is a crash. Any build: errors in the last session's logs (shutdown noise after `[last-ink] exit` ignored) count. The title then offers once: Send report / Open log folder / Not now / Don't ask again (until the next game version). |
| Report form | `scripts/feedback_view.gd` | "Report a bug" on the title and every pause menu. Bug / feedback / idea, free text, optional contact, attach screenshot (of the game under the menu), logs, current save. Send, Save to file (zip), Cancel. Nothing is sent without Send. |
| Report building and sending | `scripts/feedback.gd` (`Feedback`) | Builds the report, zips it, POSTs JSON to `endpoint` in `data/feedback.json`. With no endpoint the form has no Send button and only saves zips. |
| Screenshots | `Diag.take_screenshot` | F12 (action `screenshot`) saves `user://screenshots/last-ink_<time>.png`; the web build downloads it. Steam's own overlay also uses F12; both work. |
| Test shortcut | title > Test shortcuts > Log a test error | Logs an error on purpose, so the next launch shows the report offer. Only in builds with the `test_shortcuts` feature; logging, the offer and the form work the same in release builds. |

## Where reports go

`tools/feedback_worker/worker.js` is a Cloudflare Worker (free plan: 100,000 requests a day, no card
needed). For each report it makes one commit in a **private** GitHub repository,
`reports/<yyyy-mm-dd>/<report id>/` with `report.md`, `report.json` and the attachments, and opens an
issue there titled `[bug] <first line> (LI-XXXXXXXX)` with labels `report`, the kind, and `crash`
when the last session crashed or hit errors. It checks the game key, file names and sizes, limits
each address to a few reports, and never stores the IP address. Tests: `node tools/feedback_worker/test.mjs`.

### One-time setup (about 15 minutes, free, no card)

Only Ojon can do steps 1 to 5 (they need his GitHub and a new Cloudflare account). Steps 6 and 7 Claude
can do once it has the worker's URL. Tracked in issue #175.

1. **Private repo.** github.com > **+** (top right) > New repository. Owner `Trabiin`, name
   `last-ink-reports`, **Private**, tick **Add a README file**, Create repository.
2. **Token.** github.com > your avatar > Settings > Developer settings > Personal access tokens >
   **Fine-grained tokens** > Generate new token.
   - Token name `last-ink-reports worker`, Resource owner `Trabiin`, Expiration: Custom, one year from today.
   - Repository access: **Only select repositories** > `Trabiin/last-ink-reports` (nothing else).
   - Permissions > Repository permissions: **Contents: Read and write**, **Issues: Read and write**
     (Metadata: Read-only is added by itself).
   - Generate token, copy it (it is shown once). Put a calendar reminder two weeks before it expires.
3. **Cloudflare account.** Sign up at dash.cloudflare.com (email + password, verify the email). The free
   plan is enough; skip any "add a domain" prompts.
4. **Worker.** In the Cloudflare dashboard: Workers & Pages (left menu, under Compute) > **Create** >
   Workers > **Start with Hello World!** Name it `last-ink-reports`, Deploy. (The first time, Cloudflare
   asks for a `workers.dev` subdomain: any name works, it becomes part of the URL.) Then **Edit code**,
   select all in `worker.js`, paste the whole of
   [`tools/feedback_worker/worker.js`](../tools/feedback_worker/worker.js) (on GitHub: the file > Copy raw
   file button), and press **Deploy**.
5. **Settings.** Back on the worker's page: Settings > **Variables and Secrets** > Add:
   - Type Text, name `REPORTS_REPO`, value `Trabiin/last-ink-reports`
   - Type Text, name `GAME_KEY`, value `last-ink-reports-1` (the `game_key` in `data/feedback.json`)
   - Type **Secret**, name `GITHUB_TOKEN`, value the token from step 2

   Press **Deploy** (or Save and deploy).
6. **Check.** Open `https://last-ink-reports.<subdomain>.workers.dev/check?key=last-ink-reports-1`.
   It tests everything against GitHub and answers `"ok": true` when a real report would go through;
   otherwise each failed line has a `fix` saying what to change. It also shows `token_expires`. (The first
   run creates the report labels in the reports repo.) The plain URL without `/check` only says the
   worker is up.
7. **Hook up the game.** Put the URL (without `/check`) in `endpoint` in `data/feedback.json`, or give it
   to Claude. Add `last-ink-reports` to the Claude project's repositories (Project settings > Resources)
   so triage can read reports. Then send one real report from the live web build (title > Report a bug >
   Send) and check it lands as an issue in `last-ink-reports`.

`tools/release_check.sh` fails until `endpoint` is set, so no release ships without the inbox.

**Renewing the token** (yearly): GitHub > Fine-grained tokens > the token > Regenerate token, then in
Cloudflare replace the `GITHUB_TOKEN` secret and Deploy. `/check` warns from 30 days before expiry.

**Optional: deploy updates automatically.** Without this, a change to `worker.js` means pasting it into
the dashboard again (step 4). With it, `.github/workflows/report-inbox.yml` deploys on every merge to main
that touches `tools/feedback_worker/`, and also turns on Cloudflare's shared per-address rate limit from
`wrangler.toml`.
1. Cloudflare: your profile (top right) > API Tokens > Create Token > template **Edit Cloudflare
   Workers** > Use template. Account Resources: your account; Zone Resources: All zones. Continue >
   Create Token, copy it.
2. Cloudflare: Workers & Pages overview > **Account ID** (right side) > copy.
3. GitHub: `Trabiin/last-ink` > Settings > Secrets and variables > Actions > New repository secret:
   `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. Then Actions > Report inbox > Run workflow.

The worker's tests run in the same workflow on every pull request that changes it
(`node tools/feedback_worker/test.mjs` locally).

## Triage routine (Claude)

Run it when Ojon asks, after each playtest round, or on a schedule during playtests.

1. If the worker's URL is reachable, open `<endpoint>/check?key=<game_key>`: tell Ojon about any failed
   line, and about `token_days_left` under 30. Then list open issues in `Trabiin/last-ink-reports` with
   label `report`, oldest first.
2. For each: read `report.md`; open the logs (`session.log`, `godot*.log`) and find the first error
   and the breadcrumbs before it; look at `screenshot.png`; load `save_*.json` in a local run when the
   bug needs the exact game (copy it to `user://save_1.json`, the migrations upgrade it).
3. Same problem already filed in `Trabiin/last-ink`? Add a comment there with the new report number,
   version and system (no contact details, no quotes of the player's words).
4. New problem? Open an issue in `Trabiin/last-ink`: what goes wrong, steps to reproduce, version,
   OS/GPU, the error lines, and `Reports: LI-XXXXXXXX`. Labels as usual (`bug`, `release`, milestone).
   Never copy the contact field, the save or the free text word for word into the public repo.
5. Feedback and ideas: collect them in one comment per playtest round on #126 (or the relevant
   design issue), summarised. Playtest surveys (label `survey`, `round-<id>`) are summed up with
   `tools/playtest_report.py` instead; see docs/PLAYTEST.md "After a round".
6. Comment on the report issue with the public issue link and close it (`completed`), or close as
   `not planned` with a reason. Reports for released fixes, and anything older than 12 months, are
   deleted (folder and issue), as PRIVACY.md promises.
7. A player asking for deletion quotes their report number: delete that folder and issue.
