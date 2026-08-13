# Findings

Everything here came from a single machine unless a results row says otherwise.
One machine is an anecdote. The point of this repo is corroboration.

Findings are graded:

- **Confirmed** — reproduced across independent runs, measurement method sound.
- **Unresolved** — observed, but could not be isolated cleanly.
- **Ruled out** — suspected, tested, and found not to hold.

Two runs so far: Run 1 on a warm instance, Run 2 immediately after a gateway
restart. Anything confirmed twice is a property of the gateway rather than of
accumulated state.

---

## Confirmed

### F1 — Response-header telemetry is always zero

`x-omniroute-latency-ms`, `-tokens-in`, `-tokens-out` and `-response-cost` read
`0` in the HTTP response headers. The real values appear only as
`: x-omniroute-*=` comment lines in the streaming body.

| Run | Header | Body trailer |
|---|---|---|
| 1 | `0` ms | `292` ms |
| 2 (post-restart) | `0` ms | `283` ms |

Headers must flush before the upstream call completes. Any integration scraping
headers for observability silently records zeros.

### F2 — Fixed ~4,138-token overhead on every request

A one-word prompt (`ping`, ~1 token) was billed **4,138 input tokens** in both
runs, with compression reported `off; source=off`. The value was byte-identical
across a gateway restart, so the injected payload is a fixed preamble rather than
something that grows with session state.

Corroborated independently: 6 client requests in Run 2 produced 25.2K input
tokens against the served model — ~4,200 per request.

Still untested: whether enabling compression reduces this. The Compression
analytics page reported zero requests throughout, so compression has never run on
this instance.

### F3 — Reported latency is 16-21x lower than observed latency

| Run | Body-trailer latency | Wall-clock (`curl %{time_total}`) | Ratio |
|---|---|---|---|
| 1 | 292 ms | 6.18 s | 21x |
| 2 | 283 ms | 4.48 s | 16x |

Measured on bare `curl` with no agent framework, so client overhead and
multi-turn tool loops are excluded.

The notable part is the asymmetry: the gateway's reported figure is remarkably
stable (283, 292, 386 ms across every measurement) while wall-clock ranges from
**4.48 s to 10.84 s** for identical prompts. The reported number is not noisy —
it appears to time a small internal segment rather than request duration.

### F4 — Per-key request counters do not update

Two API keys were observed across Run 2:

| Key | Before | After | Global total |
|---|---|---|---|
| `claude` | 111 | 111 | +21 |
| `code-test` | 11 | 11 | +21 |

Neither per-key row moved while the global request total rose by 21, including
six requests the author sent directly. This survived a gateway restart.

Per-key usage and cost attribution in *Analytics -> Usage -> API Key Breakdown*
cannot be relied on. This also blocks any measurement that needs to isolate a
single request by key.

*(Promoted from "Unresolved" after Run 2.)*

### F5 — Candidate scoring is counted as requests

Zero-token models climb in exact lockstep. Run 2 delta:

| Model | Δ requests | Δ tokens |
|---|---|---|
| `gpt-5.6-luna` | +2 | 0 |
| `gpt-5.6-sol` | +2 | 0 |
| `gpt-5.6-terra` | +2 | 0 |
| `claude-sonnet-5` | +7 | 0 |
| `north-mini-code-free` | +1 | 0 |

Identical counts across three independent models indicate enumeration, not
failure. `/v1/auto-combo/coding/candidates` returns 22 candidates including
exactly these models, all `reachable: true`, `breakerState: CLOSED`,
`excluded: false`.

In Run 2, **14 of 21 counted requests consumed zero tokens** while only 6 were
real client calls. "Total Requests" is not comparable to the number of requests a
client actually made.

### F6 — Provider diversity collapses to a single backend

Shannon entropy fell from 35% to **0%**, with 100% of recent traffic on one
provider, while the dashboard simultaneously flagged "High Vendor Lock-in Risk".

Not a bug — sticky last-known-good routing behaving as designed — but users
choosing this tool for provider diversity should know the steady state.

---

## Unresolved

### U1 — Unattributed high-token request

Run 2 recorded `glm-5` gaining **+1 request and +26,000 input tokens** during a
window in which the author sent six requests, none of which routed to `glm-5`.
Source unidentified. Recorded only so it is not lost.

---

## Ruled out

### R1 — `auto/fast` is faster than `auto/coding`

Run 1 suggested a 2x speedup. Run 2 did not reproduce it:

| Run | `auto/coding` | `auto/fast` | Model picked by `auto/fast` |
|---|---|---|---|
| 1 | 4.67 s | 2.24 s | `minimax-m2.5` |
| 2 | 9.01 s | 10.84 s | `claude-haiku-4.5` |

In Run 2 `auto/fast` was **slower** and selected the *same model* as
`auto/coding`. The Run 1 result reflected which backend happened to be chosen,
not a property of the channel. **Do not cite the 2x figure.**

### R2 — One client request produces two billed upstream calls

Run 1 showed the served model gaining +2 requests and +8,200 input tokens for a
single `curl`, suggesting duplicate billing. Run 2 measured this cleanly:

**6 client requests -> exactly 6 billed calls** on `claude-haiku-4.5`, at ~4,200
input tokens each.

One request in, one billed call out. The Run 1 observation was contamination from
concurrent Claude Code traffic in the same window. **Retracted.**

### R3 — Generated profile directories leaking credentials

OmniRoute creates a Claude Code profile per catalog model under
`~/.claude/profiles/` — 167 directories on this machine, in the user's *primary*
config dir rather than an isolated one.

Initial concern was credential duplication. **Only 3 of 167 contained an auth
token**; the rest hold just `ANTHROPIC_BASE_URL`, a model name and window
settings. Files are mode 644, which matters only for those 3.

Recorded because the count is alarming at first glance. Not a finding.

---

## Reported privately

One issue was reported through GitHub's private advisory channel rather than
published here. It will be added once the maintainers have had a chance to
respond.

---

## Contributing your results

1. Run `./verify-omniroute.sh`
2. Copy `report.md` to `results/<os>-<version>-<handle>.md`
3. Add a row below
4. Open a PR

**Check no API key is in your report before pushing.** The script does not write
one, but verify.

| Reporter | OS | OmniRoute | Provider | F1 headers=0 | F2 tokens for `ping` | F3 reported vs actual | F4 key counters |
|---|---|---|---|---|---|---|---|
| Upshivam786 (run 1) | Ubuntu 6.8 | 3.8.49 | kiro | yes | 4138 | 292ms vs 6.18s | frozen |
| Upshivam786 (run 2) | Ubuntu 6.8 | 3.8.49 | kiro | yes | 4138 | 283ms vs 4.48s | frozen |

---

## Still needed

- **Windows / macOS runs.** Everything so far is Linux.
- **A different provider mix.** These results are dominated by one backend.
- **Compression on vs off**, to quantify F2. Never exercised on this instance.
- **More `auto/*` channel samples.** R1 shows a single comparison proves nothing;
  the channels need many runs each to say anything about relative latency.
- **Other agent CLIs.** The config gotchas in the README are Claude Code specific;
  Cursor, Cline and Codex likely have their own.
