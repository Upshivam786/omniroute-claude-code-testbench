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

## Results so far

Two runs on one machine (Ubuntu 6.8, OmniRoute 3.8.49) — Run 1 warm, Run 2
immediately after a gateway restart. Full detail and grading in
**[FINDINGS.md](FINDINGS.md)**.

**Confirmed across both runs**

- Response-header telemetry (`x-omniroute-latency-ms`, token and cost headers)
  always reads `0`; real values appear only in the streaming body.
- A ~1-token prompt is billed **4,138 input tokens**, byte-identical across a
  restart — a fixed preamble on every request.
- Reported latency (~285 ms, very stable) vs observed wall-clock (**4.5-10.8 s**
  for identical prompts): a 16-21x gap.
- Zero-token "requests" climb in lockstep across models — candidate scoring
  counted as requests. In Run 2, **14 of 21** counted requests were never sent by
  a client.
- Per-key request counters never update, while the global total does.

**Ruled out after Run 2**

- `auto/fast` being faster than `auto/coding` — Run 2 showed it *slower*, picking
  the same backend model. The Run 1 result was backend luck, not a channel
  property.
- Duplicate billing — 6 client requests produced exactly 6 billed calls.
- Credential leakage via the ~167 generated `~/.claude/profiles/` directories —
  only 3 of 167 hold a token.

Two of six findings did not survive a second run. That is the reason this repo
exists: **run it twice before you believe it, and on more than one machine.**

**Still open**

- Windows and macOS runs.
- A different provider mix (results here are dominated by one backend).
- Compression on vs off, to quantify the token overhead.
- More `auto/*` channel samples — a single comparison proves nothing.
- Other agent CLIs; the config gotchas above are Claude Code specific.

If you run the harness, please open a PR adding your `report.md` to `results/`
and a row to the table in FINDINGS.md.

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
