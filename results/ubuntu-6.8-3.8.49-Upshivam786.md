# OmniRoute + Claude Code — verification report

- Date: `2026-08-13T07:45:28Z`
- Base URL: `http://localhost:20128`
- Model under test: `auto/coding`

## 1. Environment

| Component | Version |
|---|---|
| OS | `Linux 6.8.0-124-generic` |
| Node.js | `v22.22.3` |
| OmniRoute | `3.8.49` |
| Claude Code | `2.1.229 (Claude Code)` |

## 2. Server reachable

`GET /v1/models` -> **200**, ~`171` models advertised.

## 3. Routing attribution (prompt: `ping`)

| Field | Value |
|---|---|
| HTTP status | `200` |
| Provider | `kr` |
| Model served | `claude-haiku-4.5` |
| Gateway latency | `292 ms` |
| Wall-clock (curl) | `6.182477 s` |
| Tokens in / out | `4138` / `14` |
| Compression | `off; source=off` |
| Cache | `MISS` |

### Finding A — response-header telemetry is emitted before the upstream call

**Reproduced.** HTTP header `x-omniroute-latency-ms: 0`, body trailer `292`.
Headers must flush before the upstream responds, so latency/token/cost headers are always zero.
Anything scraping headers for observability silently records zeros.

## 4. Injected prompt overhead

The prompt `ping` is ~1 token, but the gateway reported **4138 input tokens**
with compression `off; source=off`. Roughly **4137 tokens** are injected per request
before it reaches the provider. Re-run with compression enabled to compare.

## 5. Unauthenticated access

| Check | Result |
|---|---|
| POST /v1/chat/completions with **no** `Authorization` header | `200` |
| `Access-Control-Allow-Origin` for a foreign Origin | `https://example.invalid` |

**A request with no credentials was served.** On a single-user localhost box this may be
intended zero-config behaviour, but combined with a permissive CORS origin it means any
local process — or a web page you visit — could drain provider quota. Verify against your
`.env` / dashboard auth settings before reporting.

## 6. Request amplification — unresolved

**Status: could not be measured cleanly. Do not cite the numbers below as a finding.**

### What was attempted

A dedicated API key (`code-test`) was created so that a single bare `curl` could be
isolated from all other traffic. Dashboard counters were read immediately before
and after each request.

### What happened

| Run | Client | HTTP | Wall-clock | Key's request count after |
|---|---|---|---|---|
| A | curl, authenticated | 200 | 7.79 s | unchanged |
| B | curl, authenticated | 200 | 3.25 s | unchanged |

Both requests were served successfully. **Neither appeared under the API key that
sent them.** The key's row in *Analytics -> Usage -> API Key Breakdown* stayed at
11 requests across both, while the global request total rose by tens over the same
window and `claude-haiku-4.5` gained requests.

This blocks the measurement: if authenticated requests are not attributed to their
key, per-key counters cannot isolate a single request, and any per-model delta is
contaminated by concurrent traffic.

### Earlier observation, now considered unreliable

An earlier before/after pair (93 -> 98 total requests for one `curl`) showed
`claude-haiku-4.5` gaining **+2 requests and +8,200 input tokens** — roughly twice
the ~4,138-token payload measured in section 4 — suggesting the served call was
executed twice. **This has not been reproduced and may simply reflect concurrent
Claude Code traffic during the same window.** It is recorded here only so the
question is not lost. It should not be repeated as a claim.

### What IS supported

Three models moved in exact lockstep across a later window — `gpt-5.6-luna`,
`gpt-5.6-sol` and `gpt-5.6-terra` each gained **+8 requests with zero tokens**.
Identical counts across three independent models indicate enumeration, not
independent failures.

`/v1/auto-combo/coding/candidates` returns 22 candidates including exactly these
models, all reporting `reachable: true`, `breakerState: CLOSED`, `excluded: false`
— i.e. they never failed. **The analytics layer appears to count candidate scoring
as requests.** The 0.0% fallback rate is consistent with this.

### Open questions for maintainers

1. Should requests carrying an API key be attributed to that key in the per-key
   breakdown? Two authenticated `POST /v1/chat/completions` calls returning 200
   did not increment their key's counter.
2. Are candidate-scoring probes intended to appear in the request count? If so,
   the headline "Total Requests" figure is not comparable to the number of client
   requests made.
3. Does one client request ever produce more than one billed upstream call?
   Unresolved here for the reason above.

### How to help

If you can measure this on an idle instance with no other clients running, please
do — see [FINDINGS.md](FINDINGS.md). The method needs a way to attribute a single
request, which the per-key breakdown did not provide.

## 7. Latency A/B

Identical prompt, two routing channels:

| Channel | Provider | Model | Wall-clock |
|---|---|---|---|
| `auto/coding` | `kr` | `claude-haiku-4.5` | `4.670449 s` |
| `auto/fast` | `kr` | `minimax-m2.5` | `2.235615 s` |

## Summary

- Automated checks passed: **3**, failed: **0**, warnings: **3**
- Provider that served this run: **kr** (`claude-haiku-4.5`)

Fill in section 6 by hand, then attach this file to an issue or PR.
