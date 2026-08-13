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

## 6. Request amplification

Measured with a single bare `curl` (no agent loop), reading the dashboard
Usage counters immediately before and after.

| | Value |
|---|---|
| Requests before | 93 |
| Requests after | 98 |
| **Delta for 1 request** | **5** |
| Models with requests but 0 tokens | 6 (claude-sonnet-5, gpt-5.6-luna/sol/terra, claude-sonnet-5-medium, north-mini-code-free) |
| Dashboard 'Fallback Rate' | 0.0% |

### Per-model delta

| Model | Δ requests | Δ input tokens |
|---|---|---|
| `claude-haiku-4.5` | +2 | **+8,200** |
| `claude-sonnet-5` | +2 | 0 |
| `north-mini-code-free` | +1 | 0 |
| **Total** | **5** | **8,200** |

**Result — two distinct effects, not one.**

**(a) Scoring probes counted as requests.** Three of the five (claude-sonnet-5 x2,
north-mini-code-free x1) consumed zero tokens. `/v1/auto-combo/coding/candidates`
returns 22 candidates including exactly these models, all reporting
`reachable: true`, `breakerState: CLOSED`, `excluded: false` — i.e. they never
failed. The analytics layer appears to count candidate evaluations as requests.

**(b) The served call was executed twice.** `claude-haiku-4.5` recorded **+2
requests and +8,200 input tokens** for a single client request — roughly
2x the ~4,138-token injected payload measured in section 4. One user request
produced two real, billed upstream calls. This is not explained by probing and
is a second candidate explanation for the gap in section 3 (292 ms reported
vs 6.18 s wall-clock).

The 0.0% fallback rate is consistent with (a) but does not account for (b).

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
