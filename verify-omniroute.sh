#!/usr/bin/env bash
# verify-omniroute.sh — reproducible smoke test for OmniRoute as a Claude Code backend.
#
# Usage:
#   export OMNIROUTE_API_KEY='sk-...'      # from the OmniRoute dashboard
#   ./verify-omniroute.sh                  # writes report.md
#
# The script NEVER prints or writes your API key. Share report.md freely.

set -uo pipefail

BASE_URL="${OMNIROUTE_BASE_URL:-http://localhost:20128}"
KEY="${OMNIROUTE_API_KEY:-}"
MODEL="${OMNIROUTE_MODEL:-auto/coding}"
ALT_MODEL="${OMNIROUTE_ALT_MODEL:-auto/fast}"
REPORT="${1:-report.md}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0; warn=0
say()  { printf '%s\n' "$*"; }
rep()  { printf '%s\n' "$*" >> "$REPORT"; }
ok()   { pass=$((pass+1)); say "  [PASS] $*"; }
no()   { fail=$((fail+1)); say "  [FAIL] $*"; }
hm()   { warn=$((warn+1)); say "  [WARN] $*"; }

: > "$REPORT"
rep "# OmniRoute + Claude Code — verification report"
rep ""
rep "- Date: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`"
rep "- Base URL: \`$BASE_URL\`"
rep "- Model under test: \`$MODEL\`"
rep ""

# ---------------------------------------------------------------- environment
say "== 1. Environment =="
NODE_V="$(node -v 2>/dev/null || echo 'not found')"
OR_V="$(omniroute --version 2>/dev/null | head -1 || echo 'not found')"
OS_V="$(uname -sr 2>/dev/null || echo unknown)"
CC_V="$(claude --version 2>/dev/null | head -1 || echo 'not found')"

rep "## 1. Environment"
rep ""
rep "| Component | Version |"
rep "|---|---|"
rep "| OS | \`$OS_V\` |"
rep "| Node.js | \`$NODE_V\` |"
rep "| OmniRoute | \`$OR_V\` |"
rep "| Claude Code | \`$CC_V\` |"
rep ""

say "  node=$NODE_V omniroute=$OR_V claude=$CC_V"
case "$NODE_V" in
  v22.*|v24.*|v25.*|v26.*) ok "Node version is in the supported range" ;;
  "not found")             no "Node.js not found on PATH" ;;
  *)                       hm "Node $NODE_V is outside the documented range (>=22.22.2 <23 || >=24 <27)" ;;
esac

# ------------------------------------------------------------------ reachable
say ""
say "== 2. Server reachable =="
CODE="$(curl -s -o "$TMP/models.json" -w '%{http_code}' --max-time 15 "$BASE_URL/v1/models" 2>/dev/null)"
rep "## 2. Server reachable"
rep ""
if [ "$CODE" = "200" ]; then
  N_MODELS="$(grep -o '"id"' "$TMP/models.json" 2>/dev/null | wc -l | tr -d ' ')"
  ok "/v1/models returned 200 with ~$N_MODELS model entries"
  rep "\`GET /v1/models\` -> **200**, ~\`$N_MODELS\` models advertised."
else
  no "/v1/models returned HTTP $CODE — is \`omniroute\` running?"
  rep "\`GET /v1/models\` -> **$CODE**. Server not reachable; remaining tests are unreliable."
fi
rep ""

# ------------------------------------------------------------ request helper
# chat <outfile-prefix> <model> <prompt> [auth: yes|no]
chat() {
  local pre="$1" model="$2" prompt="$3" auth="${4:-yes}"
  local -a hdrs=(-H "Content-Type: application/json")
  [ "$auth" = "yes" ] && [ -n "$KEY" ] && hdrs+=(-H "Authorization: Bearer $KEY")
  local payload
  payload=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}]}' "$model" "$prompt")
  curl -sS --max-time 300 \
    -D "$TMP/$pre.h" -o "$TMP/$pre.b" \
    -w '%{http_code} %{time_total}' \
    "${hdrs[@]}" -d "$payload" \
    "$BASE_URL/v1/chat/completions" 2>/dev/null
}

# hval <prefix> <header-name>  -> looks in real headers AND in SSE ": x-..." comments
hval() {
  local pre="$1" name="$2" v=""
  v="$(grep -i "^${name}:" "$TMP/$pre.h" 2>/dev/null | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')"
  if [ -z "$v" ] || [ "$v" = "0" ]; then
    local b
    b="$(grep -i "^: *${name}=" "$TMP/$pre.b" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
    [ -n "$b" ] && v="$b"
  fi
  printf '%s' "$v"
}

# ------------------------------------------------------- routing / attribution
say ""
say "== 3. Routing attribution =="
R="$(chat ping "$MODEL" "ping")"
PING_CODE="${R%% *}"; PING_WALL="${R##* }"
P_PROV="$(hval ping x-omniroute-provider)"
P_MODEL="$(hval ping x-omniroute-model)"
P_LAT="$(hval ping x-omniroute-latency-ms)"
P_IN="$(hval ping x-omniroute-tokens-in)"
P_OUT="$(hval ping x-omniroute-tokens-out)"
P_COMP="$(hval ping x-omniroute-compression)"
P_CACHE="$(hval ping x-omniroute-cache)"

rep "## 3. Routing attribution (prompt: \`ping\`)"
rep ""
rep "| Field | Value |"
rep "|---|---|"
rep "| HTTP status | \`${PING_CODE:-?}\` |"
rep "| Provider | \`${P_PROV:-unreported}\` |"
rep "| Model served | \`${P_MODEL:-unreported}\` |"
rep "| Gateway latency | \`${P_LAT:-?} ms\` |"
rep "| Wall-clock (curl) | \`${PING_WALL:-?} s\` |"
rep "| Tokens in / out | \`${P_IN:-?}\` / \`${P_OUT:-?}\` |"
rep "| Compression | \`${P_COMP:-unreported}\` |"
rep "| Cache | \`${P_CACHE:-unreported}\` |"
rep ""

if [ "$PING_CODE" = "200" ]; then
  ok "chat/completions 200 via provider='${P_PROV:-?}' model='${P_MODEL:-?}'"
else
  no "chat/completions returned HTTP ${PING_CODE:-?}"
fi

# FINDING A: header latency reported as 0 while the SSE body reports the real value
H_LAT_RAW="$(grep -i '^x-omniroute-latency-ms:' "$TMP/ping.h" 2>/dev/null | tail -1 | cut -d: -f2- | tr -d ' \r')"
B_LAT_RAW="$(grep -i '^: *x-omniroute-latency-ms=' "$TMP/ping.b" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d ' \r')"
rep "### Finding A — response-header telemetry is emitted before the upstream call"
rep ""
if [ "${H_LAT_RAW:-}" = "0" ] && [ -n "${B_LAT_RAW:-}" ] && [ "${B_LAT_RAW}" != "0" ]; then
  hm "HTTP header says latency=0ms but body trailer says ${B_LAT_RAW}ms — header telemetry is unusable"
  rep "**Reproduced.** HTTP header \`x-omniroute-latency-ms: $H_LAT_RAW\`, body trailer \`$B_LAT_RAW\`."
  rep "Headers must flush before the upstream responds, so latency/token/cost headers are always zero."
  rep "Anything scraping headers for observability silently records zeros."
else
  rep "Not reproduced here. Header=\`${H_LAT_RAW:-n/a}\` body=\`${B_LAT_RAW:-n/a}\`."
fi
rep ""

# ------------------------------------------------------------ prompt overhead
say ""
say "== 4. Injected prompt overhead =="
rep "## 4. Injected prompt overhead"
rep ""
if [ "$PING_CODE" != "200" ]; then
  say "  [SKIP] no successful request to measure"
  rep "Skipped — the request in section 3 did not succeed."
elif [ -n "${P_IN:-}" ] && [ "${P_IN:-0}" -gt 100 ] 2>/dev/null; then
  hm "A 1-word prompt reported ${P_IN} input tokens (compression: ${P_COMP:-?})"
  rep "The prompt \`ping\` is ~1 token, but the gateway reported **${P_IN} input tokens**"
  rep "with compression \`${P_COMP:-?}\`. Roughly **$((P_IN - 1)) tokens** are injected per request"
  rep "before it reaches the provider. Re-run with compression enabled to compare."
else
  ok "Input tokens (${P_IN:-?}) look proportionate to the prompt"
  rep "Input tokens: \`${P_IN:-?}\` — no significant injected overhead detected."
fi
rep ""

# ----------------------------------------------------------------- no-auth
say ""
say "== 5. Unauthenticated access =="
rep "## 5. Unauthenticated access"
rep ""
R2="$(chat noauth "$MODEL" "x" no)"
NA_CODE="${R2%% *}"
CORS="$(curl -sI --max-time 10 -H "Origin: https://example.invalid" "$BASE_URL/v1/models" 2>/dev/null \
        | grep -i '^access-control-allow-origin:' | tr -d '\r' | cut -d: -f2- | sed 's/^ *//')"

rep "| Check | Result |"
rep "|---|---|"
rep "| POST /v1/chat/completions with **no** \`Authorization\` header | \`${NA_CODE:-?}\` |"
rep "| \`Access-Control-Allow-Origin\` for a foreign Origin | \`${CORS:-none}\` |"
rep ""
if [ "$CODE" != "200" ]; then
  say "  [SKIP] server unreachable"
  rep "Skipped — server unreachable."
elif [ "$NA_CODE" = "200" ]; then
  hm "Unauthenticated request succeeded (HTTP 200) and consumed provider quota"
  rep "**A request with no credentials was served.** On a single-user localhost box this may be"
  rep "intended zero-config behaviour, but combined with a permissive CORS origin it means any"
  rep "local process — or a web page you visit — could drain provider quota. Verify against your"
  rep "\`.env\` / dashboard auth settings before reporting."
else
  ok "Unauthenticated request rejected (HTTP ${NA_CODE:-?})"
  rep "Unauthenticated requests are rejected."
fi
rep ""

# ------------------------------------------------ request amplification probe
say ""
say "== 6. Request amplification =="
rep "## 6. Request amplification"
rep ""
rep "The dashboard can report far more upstream requests than prompts you sent, with several"
rep "models showing non-zero request counts and **zero tokens**. Check it manually:"
rep ""
rep "1. Note the request count at \`$BASE_URL/dashboard\` → Analytics → Usage."
rep "2. Send exactly one prompt through Claude Code."
rep "3. Re-read the count. Record the delta below."
rep "4. Open **Route Trace** and count upstream attempts for that single turn."
rep ""
rep "| | Value |"
rep "|---|---|"
rep "| Requests before | _fill in_ |"
rep "| Requests after | _fill in_ |"
rep "| Delta for 1 prompt | _fill in_ |"
rep "| Models with requests but 0 tokens | _fill in_ |"
rep "| Dashboard 'Fallback Rate' | _fill in_ |"
rep ""
rep "A delta far above 1, alongside a reported fallback rate of 0%, suggests either candidate"
rep "probing counted as requests, or retry churn — and would explain a large gap between the"
rep "gateway's reported latency and the latency you actually feel."
say "  (manual step — see report)"

# ---------------------------------------------------------- latency A/B
say ""
say "== 7. Latency: $MODEL vs $ALT_MODEL =="
rep "## 7. Latency A/B"
rep ""
PROMPT="Write a Python function that reverses a string."
RA="$(chat abA "$MODEL" "$PROMPT")";     A_WALL="${RA##* }"; A_PROV="$(hval abA x-omniroute-provider)"; A_MOD="$(hval abA x-omniroute-model)"
RB="$(chat abB "$ALT_MODEL" "$PROMPT")"; B_WALL="${RB##* }"; B_PROV="$(hval abB x-omniroute-provider)"; B_MOD="$(hval abB x-omniroute-model)"

rep "Identical prompt, two routing channels:"
rep ""
rep "| Channel | Provider | Model | Wall-clock |"
rep "|---|---|---|---|"
rep "| \`$MODEL\` | \`${A_PROV:-?}\` | \`${A_MOD:-?}\` | \`${A_WALL:-?} s\` |"
rep "| \`$ALT_MODEL\` | \`${B_PROV:-?}\` | \`${B_MOD:-?}\` | \`${B_WALL:-?} s\` |"
rep ""
say "  $MODEL -> ${A_WALL:-?}s (${A_PROV:-?}/${A_MOD:-?})"
say "  $ALT_MODEL -> ${B_WALL:-?}s (${B_PROV:-?}/${B_MOD:-?})"

# ------------------------------------------------------------------ summary
rep "## Summary"
rep ""
rep "- Automated checks passed: **$pass**, failed: **$fail**, warnings: **$warn**"
rep "- Provider that served this run: **${P_PROV:-unknown}** (\`${P_MODEL:-unknown}\`)"
rep ""
rep "Fill in section 6 by hand, then attach this file to an issue or PR."

say ""
say "== Done: $pass passed, $fail failed, $warn warnings =="
say "Report written to: $REPORT"
