// Tests for the report worker with a fake GitHub API: node tools/feedback_worker/test.mjs
import assert from "node:assert/strict";
import worker, { validate, surveyRound, check, LABELS } from "./worker.js";

const env = { GITHUB_TOKEN: "t", REPORTS_REPO: "o/reports", GAME_KEY: "k" };
let calls = [];
let refMoves = 0;
globalThis.fetch = async (url, init) => {
  const path = url.replace("https://api.github.com", "");
  const body = init.body ? JSON.parse(init.body) : null;
  calls.push({ method: init.method, path, body });
  assert.equal(init.headers.authorization, "Bearer t");
  const ok = (o) => new Response(JSON.stringify(o), { status: 200 });
  if (path === "/repos/o/reports") return ok({ default_branch: "main" });
  if (path.startsWith("/repos/o/reports/git/ref/")) return ok({ object: { sha: "p1" } });
  if (path.startsWith("/repos/o/reports/git/commits/") && init.method === "GET") return ok({ tree: { sha: "t0" } });
  if (path === "/repos/o/reports/git/blobs") return ok({ sha: "b" + calls.length });
  if (path === "/repos/o/reports/git/trees") return ok({ sha: "t1" });
  if (path === "/repos/o/reports/git/commits") return ok({ sha: "c1" });
  if (path.startsWith("/repos/o/reports/git/refs/")) {
    if (refMoves > 0) { refMoves--; return new Response("{}", { status: 422 }); }
    return ok({});
  }
  if (path === "/repos/o/reports/issues") return ok({ number: 1 });
  throw new Error("unexpected " + init.method + " " + path);
};

const report = (extra = {}) => ({
  id: "LI-0A1B2C3D", game: "last-ink", game_key: "k", kind: "bug", created: "2026-11-21T10:00:00Z",
  text: "Froze in the Forge\nwhen upgrading", contact: "", system: { game_version: "0.9.0", os: "Windows" },
  context: { scene: "res://scenes/hub.tscn", day: 4 }, previous_session: { crashed: true, errors: 2, samples: ["SCRIPT ERROR: x"] },
  attachments: { "session.log": { type: "text/plain", data: "hello ✓" }, "screenshot.png": { type: "image/png", base64: "iVBORw0KGgo=" } },
  ...extra,
});
const post = (body, headers = {}) => worker.fetch(new Request("https://w.example/", {
  method: "POST", body: typeof body === "string" ? body : JSON.stringify(body),
  headers: { "content-type": "application/json", "cf-connecting-ip": headers.ip || "1.1.1.1" },
}), env);

// A good report: one commit with every file, then an issue.
let res = await post(report());
let out = await res.json();
assert.equal(res.status, 200, JSON.stringify(out));
assert.deepEqual(out, { ok: true, id: "LI-0A1B2C3D" });
assert.equal(res.headers.get("access-control-allow-origin"), "*");
const tree = calls.find((c) => c.path === "/repos/o/reports/git/trees").body.tree.map((t) => t.path.split("/").pop());
assert.deepEqual(tree.sort(), ["report.json", "report.md", "screenshot.png", "session.log"]);
const blobs = calls.filter((c) => c.path.endsWith("/git/blobs")).map((c) => c.body.content);
assert.ok(blobs.includes("iVBORw0KGgo="), "base64 attachments pass through");
assert.ok(blobs.includes(Buffer.from("hello ✓").toString("base64")), "text attachments are utf-8");
const meta = JSON.parse(Buffer.from(blobs[1], "base64").toString());
assert.equal(meta.game_key, undefined, "the key is not stored");
assert.equal(meta.attachments, undefined);
const issue = calls.find((c) => c.path === "/repos/o/reports/issues").body;
assert.equal(issue.title, "[bug] Froze in the Forge (LI-0A1B2C3D)");
assert.deepEqual(issue.labels, ["report", "bug", "crash"]);
assert.ok(issue.body.includes("> Froze in the Forge"));
assert.ok(issue.body.includes("https://github.com/o/reports/blob/HEAD/reports/"), "absolute links to the files");
assert.ok(!JSON.stringify(calls).includes("1.1.1.1"), "the IP is never written");

// The branch moved during the commit: retried.
calls = []; refMoves = 1;
res = await post(report(), { ip: "2.2.2.2" });
assert.equal(res.status, 200);
assert.equal(calls.filter((c) => c.path.startsWith("/repos/o/reports/git/refs/")).length, 2);

// Refused: wrong key, bad id, bad names, too much text, bad JSON, wrong method.
for (const [extra, why] of [[{ game_key: "x" }, "unknown game"], [{ id: "../x" }, "bad id"], [{ kind: "rant" }, "bad kind"],
  [{ text: "x".repeat(4001) }, "bad text"], [{ attachments: { "../etc": { data: "" } } }, "bad file name"],
  [{ attachments: { "report.md": { data: "" } } }, "bad file name"]]) {
  calls = [];
  res = await post(report(extra), { ip: "3.3.3." + why.length });
  assert.equal(res.status, 400, why);
  assert.equal((await res.json()).error, why);
  assert.equal(calls.length, 0, "nothing reaches GitHub: " + why);
}
assert.equal((await post("{nope", { ip: "4.4.4.4" })).status, 400);
assert.equal((await worker.fetch(new Request("https://w.example/", { method: "PUT" }), env)).status, 405);
assert.equal((await worker.fetch(new Request("https://w.example/", { method: "OPTIONS" }), env)).status, 204);
assert.equal(validate(report(), { GAME_KEY: "" }), "unknown game", "no key configured: refuse everything");

// A playtest survey (issue #168): accepted, labelled with its round; a round name that isn't plain is dropped.
calls = [];
const survey = (round) => report({ kind: "survey", text: "Playtest survey, round r1 (survey v1)", previous_session: {},
  attachments: { "survey.json": { type: "application/json", data: JSON.stringify({ round, answers: { enjoy: 4 } }) } } });
res = await post(survey("R1"), { ip: "5.5.5.5" });
assert.equal(res.status, 200);
const sIssue = calls.find((c) => c.path === "/repos/o/reports/issues").body;
assert.deepEqual(sIssue.labels, ["report", "survey", "round-r1"]);
assert.ok(sIssue.title.startsWith("[survey] Playtest survey, round r1"));
assert.equal(surveyRound(survey("../../x")), "");
assert.equal(surveyRound(report()), "", "only surveys have a round");

// Rate limit without a binding: the seventh report in an hour from one address is refused.
let last;
for (let i = 0; i < 7; i++) last = await post(report(), { ip: "9.9.9.9" });
assert.equal(last.status, 429);

// Setup check (GET /check?key=...): a fake GitHub per scenario.
const gh = (o) => async (url, init) => {
  const path = url.replace("https://api.github.com", "");
  const hdr = { "github-authentication-token-expiration": o.expires || "2027-11-20 08:00:00 UTC" };
  const r = (status, body = {}) => new Response(JSON.stringify(body), { status, headers: hdr });
  if (path === "/repos/o/reports" && init.method === "GET") return o.repo ? r(o.repo) : r(200, { private: o.public ? false : true, default_branch: "main", has_issues: true });
  if (path === "/repos/o/reports/git/ref/heads/main") return r(o.empty ? 404 : 200, { object: { sha: "p" } });
  if (path === "/repos/o/reports/git/blobs") return r(o.noContents ? 403 : 201, { sha: "b" });
  if (path === "/repos/o/reports/labels") { o.labels = (o.labels || 0) + 1; return r(o.noIssues ? 403 : o.labelsExist ? 422 : 201); }
  throw new Error("unexpected " + init.method + " " + path);
};
const now = Date.parse("2026-11-24T00:00:00Z");
const runCheck = async (o, e = env, key = "k") => {
  globalThis.fetch = gh(o);
  const res = await check(new Request("https://w.example/check?key=" + key), e, now);
  return { status: res.status, body: await res.json() };
};
const failed = (b) => b.checks.filter((c) => !c.ok).map((c) => c.name);

let c = await runCheck({});
assert.equal(c.body.ok, true, JSON.stringify(c.body));
assert.equal(c.body.token_expires, "2027-11-20");
assert.equal(c.body.token_days_left, 361);
assert.ok(c.body.checks.find((x) => x.name === "issues").detail.includes("made 6 labels"));
const o = { labelsExist: true };
c = await runCheck(o);
assert.equal(c.body.ok, true, "labels already there is fine");
assert.equal(o.labels, Object.keys(LABELS).length);
assert.equal((await runCheck({}, env, "wrong")).status, 403, "needs the game key");
assert.deepEqual(failed((await runCheck({}, { GAME_KEY: "k" })).body), ["settings"]);
assert.deepEqual(failed((await runCheck({ repo: 401 })).body), ["token"]);
assert.deepEqual(failed((await runCheck({ repo: 404 })).body), ["repo"]);
assert.deepEqual(failed((await runCheck({ public: true })).body), ["repo"], "a public repo fails the check");
assert.deepEqual(failed((await runCheck({ empty: true })).body), ["branch"]);
assert.deepEqual(failed((await runCheck({ noContents: true })).body), ["contents"]);
assert.deepEqual(failed((await runCheck({ noIssues: true })).body), ["issues"]);
c = await runCheck({ expires: "2026-12-10 08:00:00 UTC" });
assert.equal(c.body.ok, true, "a token running out soon still works");
assert.ok(c.body.checks.some((x) => x.warning && x.name === "token expiry"));
for (const x of (await runCheck({ noIssues: true })).body.checks) if (!x.ok) assert.ok(x.fix, "every failure says how to fix it");
// Routed through fetch: /check and /check/ reach it, / stays the plain health answer.
globalThis.fetch = gh({ labelsExist: true });
assert.equal((await (await worker.fetch(new Request("https://w.example/check/?key=k"), env)).json()).ok, true);
assert.deepEqual(await (await worker.fetch(new Request("https://w.example/"), env)).json(), { ok: true, service: "last-ink reports" });

console.log("worker tests passed");
