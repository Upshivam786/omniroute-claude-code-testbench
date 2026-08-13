# Findings

Everything here came from a single machine unless a results row says otherwise.
One machine is an anecdote. The point of this repo is corroboration.

Findings are graded:

- **Confirmed** — reproduced on a clean run, measurement method sound.
- **Unresolved** — observed, but the measurement could not be isolated.
- **Ruled out** — suspected, tested, and found to be a non-issue.

---

## Confirmed

### F1 — Response-header telemetry is always zero

`x-omniroute-latency-ms`, `-tokens-in`, `-tokens-out` and `-response-cost` read `0`
in the HTTP response headers. The real values appear only as `: x-omniroute-*=`
comment lines in the streaming body.

Measured: header `0` ms vs body trailer `292` ms for the same request.

Headers must flush before the upstream call completes. Any integration scraping
headers for observability silently records zeros.

### F2 — Large fixed token overhead per request

A one-word prompt (`ping`, ~1 token) was billed **4,138 input tokens** with
compression reported as `off; source=off`. A second run measured 4,145 — the same
magnitude but not byte-identical, suggesting the injected payload contains
something dynamic rather than a static block.

Roughly 4K tokens are added to every request before it reaches the provider.
Untested: whether enabling compression reduces this.

### F3 — Reported latency is ~21x lower than observed latency

| Measure | Value |
|---|---|
| `x-omniroute-latency-ms` (body trailer) | 292 ms |
| Wall-clock, `curl` `%{time_total}` | 6.18 s |

Measured on a bare `curl` with no agent framework, so client-side overhead and
multi-turn tool loops are excluded. Repeat single requests varied widely
(7.79 s, then 3.25 s), suggesting a warm-up effect on first call.

Whatever consumes the remaining ~5.9 s happens inside the gateway, outside the
window it reports.

### F4 — `auto/fast` is roughly 2x faster than `auto/coding`

Identical prompt, same provider, different channel:

| Channel | Model chosen | Wall-clock |
|---|---|---|
| `auto/coding` | `claude-haiku-4.5` | 4.67 s |
| `auto/fast` | `minimax-m2.5` | 2.24 s |

Actionable for anyone using the gateway interactively.

### F5 — Candidate scoring is counted as requests

`gpt-5.6-luna`, `gpt-5.6-sol` and `gpt-5.6-terra` each gained exactly **+8
requests with zero tokens** over the same window. Identical counts across three
independent models indicate enumeration, not failure.

`/v1/auto-combo/coding/candidates` returns 22 candidates including exactly these
models, all `reachable: true`, `breakerState: CLOSED`, `excluded: false`.

Consequence: "Total Requests" on the dashboard is not comparable to the number of
client requests made.

### F6 — Provider diversity collapses to a single backend

Shannon entropy fell from 35% to **0%**, with 100% of recent traffic on one
provider, while the dashboard simultaneously flagged "High Vendor Lock-in Risk".

Not a bug — sticky last-known-good routing behaving as designed — but users
choosing this tool for provider diversity should know the steady state.

---

## Unresolved

### U1 — Authenticated requests not attributed to their API key

Two `POST /v1/chat/completions` calls carrying a valid `Authorization: Bearer`
header returned HTTP 200 and were served. **Neither incremented that key's row in
Analytics -> Usage -> API Key Breakdown**, which stayed at 11 requests across
both, while global totals rose over the same window.

Needs confirming on an idle instance. If reproducible, per-key usage and cost
attribution cannot be relied on.

### U2 — Does one client request produce more than one billed upstream call?

One before/after pair showed `claude-haiku-4.5` gaining +2 requests and +8,200
input tokens (~2x the 4,138-token payload) for a single `curl`. Not reproduced.
Attempts to isolate it were blocked by U1. **Treat as unverified.**

---

## Ruled out

### R1 — ~167 generated profile directories leaking credentials

OmniRoute creates a Claude Code profile per catalog model under
`~/.claude/profiles/` — 167 directories on this machine, in the user's *primary*
config dir rather than an isolated one.

Initial concern was credential duplication. **Only 3 of 167 contained an auth
token**; the rest hold just `ANTHROPIC_BASE_URL`, a model name and window
settings. Files are mode 644, which matters only for those 3.

Recorded because the directory count is alarming at first glance and others will
hit it. Not a finding.

---

## Reported privately

One issue is being reported through `SECURITY.md` rather than published here, and
will be added once the maintainers have had a chance to respond.

---

## Contributing your results

1. Run `./verify-omniroute.sh`
2. Fill in section 6 by hand if you can isolate the measurement
3. Copy `report.md` to `results/<os>-<version>-<handle>.md`
4. Add a row below
5. Open a PR

**Check no API key is in your report before pushing.** The script does not write
one, but verify.

| Reporter | OS | OmniRoute | Provider | F1 headers=0 | F2 tokens for `ping` | F3 reported vs actual | U1 key attribution |
|---|---|---|---|---|---|---|---|
| Upshivam786 | Ubuntu 6.8 | 3.8.49 | kiro | yes | 4138 | 292ms vs 6.18s | not attributed |

---

## Still needed

- **Windows / macOS runs.** Everything so far is Linux.
- **A different provider mix.** These results are dominated by one backend.
- **Compression on vs off**, to quantify F2.
- **An idle-instance measurement** of U1 and U2.
- **Other agent CLIs.** The config gotchas in the README are Claude Code specific;
  Cursor, Cline and Codex likely have their own.
