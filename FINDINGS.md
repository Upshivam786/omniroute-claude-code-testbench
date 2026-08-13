# Contributing your results

The point of this repo is corroboration. One machine's numbers are an anecdote;
five machines across different OSes and provider mixes is evidence worth taking
to the upstream project.

## How to contribute

1. Run `./verify-omniroute.sh`
2. Fill in section 6 by hand (dashboard request delta — the script can't read it)
3. Copy `report.md` to `results/<os>-<omniroute-version>-<yourhandle>.md`
4. Add a row to the table below
5. Open a PR

**Before you push:** confirm no API key is in your report. The script doesn't
write one, but check anyway.

## Results

| Reporter | OS | OmniRoute | Provider served | Q1 headers=0 | Q2 tokens for `ping` | Q3 reqs per prompt | Q4 no-auth served |
|---|---|---|---|---|---|---|---|
| _example_ | Ubuntu 24.04 | 3.8.49 | Kiro AI | yes | 4145 | ~13 | yes |

## Reporting upstream

Once something reproduces on more than one machine, it's worth taking to the
project. Two things to do first:

- Run `npm run system-info` in your OmniRoute install — the maintainers ask for
  the generated `system-info.txt` on every issue report.
- Check whether issue creation is open. It has been restricted at times; if so,
  use Discussions or the project's Discord instead.

Frame findings as questions, not accusations. Several of these have plausible
innocent explanations — candidate probing counted as requests, zero-config
auth by design on localhost — and a maintainer will tell you faster than you
can reverse-engineer it.

## Areas that still need work

- **Windows / macOS runs.** Everything so far is Linux.
- **Other provider mixes.** Results so far are dominated by one provider; a run
  with a different set would show whether the numbers are provider-specific.
- **Compression on vs off.** Section 4 measures overhead with compression off.
  Someone should run both and diff the input-token counts.
- **Other agent CLIs.** The gotchas table is Claude Code specific. Cursor, Cline
  and Codex likely have their own equivalents.
