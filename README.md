# omniroute-claude-code-testbench

A reproducible harness for pointing **Claude Code** at a local **OmniRoute** gateway,
verifying the routing actually works, and capturing the numbers.

Getting this wired up is fiddly and most of the failures look identical from the
outside ("Claude Code just won't connect"). This repo encodes the config that
works, the four ways it silently doesn't, and a script that produces a shareable
report so results can be compared across machines.

Not affiliated with the OmniRoute project. Tested against OmniRoute `v3.8.49`
and Claude Code `v2.1.139`.

---

## Quick start

```bash
git clone https://github.com/Upshivam786/omniroute-claude-code-testbench.git && cd omniroute-claude-code-testbench

# 1. OmniRoute running in another terminal
omniroute

# 2. Create an API key in the dashboard (http://localhost:20128/dashboard)
export OMNIROUTE_API_KEY='sk-...'

# 3. Run the checks
./verify-omniroute.sh

# 4. Wire up an isolated Claude Code profile
./setup-claude-profile.sh
CLAUDE_CONFIG_DIR="$HOME/.claude-omniroute-test" claude
```

`verify-omniroute.sh` writes `report.md`. It never prints or stores your key.

---

## The config that works

`~/.claude-omniroute-test/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:20128",
    "ANTHROPIC_AUTH_TOKEN": "sk-your-omniroute-key",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "auto/coding",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "auto/coding",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "auto/coding"
  }
}
```

Launch with `CLAUDE_CONFIG_DIR="$HOME/.claude-omniroute-test" claude` so this
never touches your real `~/.claude`.

## The four ways it silently fails

| # | Mistake | Symptom | Fix |
|---|---|---|---|
| 1 | Using `anthropic_api_url` / `anthropic_api_key` keys | Config ignored entirely, no error | Settings must live under an `env` block using the real env-var names |
| 2 | `ANTHROPIC_BASE_URL` ending in `/v1` | Connection failures / 404s | Use `http://localhost:20128` — Claude Code appends the path itself |
| 3 | Setting only `ANTHROPIC_MODEL` | `Ambiguous model` errors | Map all three tiers: `..._OPUS_MODEL`, `..._SONNET_MODEL`, `..._HAIKU_MODEL` |
| 4 | Requesting a specific catalog model from `/v1/models` | `Invalid model` | Advertised model IDs aren't always routable — `auto/coding` is |

Gotcha 3 is the load-bearing one. Claude Code switches tiers internally
(cheap model for small tasks, larger for reasoning). If a tier isn't mapped, it
asks for something like `claude-opus-4-7` and the gateway can't resolve it.

---

## What the script checks

| § | Check |
|---|---|
| 1 | Node / OmniRoute / Claude Code versions against the supported range |
| 2 | `/v1/models` reachable, model count |
| 3 | Routing attribution — which provider and model actually served the request |
| 4 | Injected prompt overhead (tokens billed vs tokens sent) |
| 5 | Whether unauthenticated requests are served, plus CORS origin policy |
| 6 | Request amplification (manual — dashboard delta per prompt) |
| 7 | Latency A/B between `auto/coding` and `auto/fast` |

---

## Open questions this harness is meant to answer

These came out of one session and need corroboration on other machines before
any of them is worth filing upstream. If you run this, please open a PR adding
your `report.md` to `results/` — see [FINDINGS.md](FINDINGS.md).

**Q1 — Are latency/token/cost response headers always zero?**
On one run the HTTP header read `x-omniroute-latency-ms: 0` while the SSE body
trailer for the same request read `386`. If headers flush before the upstream
call completes, every header-scraping integration records zeros.

**Q2 — How much is injected per request?**
A 1-token prompt (`ping`) was billed **4,145 input tokens** with compression
off. Is that tool definitions, a system preamble, or double counting?

**Q3 — Why do request counts exceed prompt counts?**
A dashboard showed 79 requests for roughly six prompts, with four models at
exactly 14 requests each and **zero tokens**, while "Fallback Rate" read 0.0%.
Candidate probing, or retry churn? If it's churn, it would explain a gateway
reporting 386ms while the user waits 41 seconds.

**Q4 — Is unauthenticated local access intended?**
A request with an empty `Authorization` header was served and consumed quota.
Plausibly deliberate zero-config behaviour — but worth confirming, especially
alongside the CORS policy.

**Q5 — Does `auto/fast` meaningfully beat `auto/coding`?**
Section 7 measures it. Enough samples across machines would make this a real
answer instead of an anecdote.

---

## Repo layout

```
verify-omniroute.sh      the test suite -> report.md
setup-claude-profile.sh  creates an isolated Claude Code profile
settings.template.json   the working config, no secrets
FINDINGS.md              template for contributing your results
results/                 collected reports
```

## Security

`.gitignore` excludes `settings.json`, `report.md`, and `*.local.json`.
`report.md` is designed to be safe to share — it records providers, models,
latencies and token counts, never keys. Check before you push anyway.

If you've already pasted a key into a terminal, a chat, or a screenshot,
rotate it in the dashboard and clear your shell history.

## License

MIT.
