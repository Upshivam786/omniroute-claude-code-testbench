# OmniRoute + Claude Code — verification report

- Date: `2026-08-13T09:13:20Z`
- Base URL: `http://localhost:20128`
- Model under test: `auto/coding`

## 1. Environment

| Component | Version |
|---|---|
| OS | `Linux 6.8.0-124-generic` |
| Node.js | `v22.22.3` |
| OmniRoute | `3.8.49` |
| Claude Code | `2.1.231 (Claude Code)` |

## 2. Server reachable

`GET /v1/models` -> **200**, ~`171` models advertised.

## 3. Routing attribution (prompt: `ping`)

| Field | Value |
|---|---|
| HTTP status | `200` |
| Provider | `kr` |
| Model served | `claude-haiku-4.5` |
| Gateway latency | `283 ms` |
| Wall-clock (curl) | `4.483724 s` |
| Tokens in / out | `4138` / `13` |
| Compression | `off; source=off` |
| Cache | `MISS` |

### Finding A — response-header telemetry is emitted before the upstream call

**Reproduced.** HTTP header `x-omniroute-latency-ms: 0`, body trailer `283`.
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

The dashboard can report far more upstream requests than prompts you sent, with several
models showing non-zero request counts and **zero tokens**. Check it manually:

1. Note the request count at `http://localhost:20128/dashboard` → Analytics → Usage.
2. Send exactly one prompt through Claude Code.
3. Re-read the count. Record the delta below.
4. Open **Route Trace** and count upstream attempts for that single turn.

| | Value |
|---|---|
| Requests before | _fill in_ |
| Requests after | _fill in_ |
| Delta for 1 prompt | _fill in_ |
| Models with requests but 0 tokens | _fill in_ |
| Dashboard 'Fallback Rate' | _fill in_ |

A delta far above 1, alongside a reported fallback rate of 0%, suggests either candidate
probing counted as requests, or retry churn — and would explain a large gap between the
gateway's reported latency and the latency you actually feel.
## 7. Latency A/B

Identical prompt, two routing channels:

| Channel | Provider | Model | Wall-clock |
|---|---|---|---|
| `auto/coding` | `kr` | `claude-haiku-4.5` | `9.005211 s` |
| `auto/fast` | `kr` | `claude-haiku-4.5` | `10.838211 s` |

## Summary

- Automated checks passed: **3**, failed: **0**, warnings: **3**
- Provider that served this run: **kr** (`claude-haiku-4.5`)

Fill in section 6 by hand, then attach this file to an issue or PR.
