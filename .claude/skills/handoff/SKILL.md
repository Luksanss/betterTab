---
name: handoff
description: "Start-of-session orientation. Reads the handoff document and the real git state, verifies the one against the other, and says whether the next piece of work can start. Use when the user asks where we left off, what the current state is, or whether we are ready to implement something."
allowed-tools: Read Grep Glob Bash(git *) Bash(ls *) Bash(cat *) Bash(docker ps*) Bash(lsof *)
---

# /handoff — where did we leave off?

Work named by the user (may be empty): `$ARGUMENTS`

## Handoff document
!`f=$(ls docs/handoff.md handoff.md HANDOFF.md 2>/dev/null | head -1); echo "path: ${f:-NONE FOUND}"; echo; cat "$f" 2>/dev/null`

## Git state
!`echo "branch: $(git branch --show-current)"; echo; echo "--- working tree ---"; git status --short; echo "(empty = clean)"; echo; echo "--- last 12 commits on dev ---"; git log --oneline -12 dev 2>/dev/null; echo; echo "--- on dev, not yet released to main ---"; git log --oneline main..dev 2>/dev/null; echo "(empty = main is up to date with dev)"; echo; echo "--- last release: main ---"; git log --oneline -1 main 2>/dev/null; echo; echo "--- local vs origin, ahead behind (as of last fetch) ---"; for b in dev main; do printf "%s: " "$b"; git rev-list --left-right --count $b...origin/$b 2>/dev/null || echo "no remote"; done; echo; echo "--- other local branches ---"; git branch --format="%(refname:short)" | grep -v -x -E "dev|main"`

## What to do

Everything above is already loaded; do not re-run it.

Work through these checks silently, then report using the template below and nothing else.

This repo has one working branch. Work is committed straight to `dev`; `main` is the last
working version and only moves when the maintainer says a version works (see `CLAUDE.md`).

- **Verify the handoff against git; never restate it as fact.** Commits on `dev` it doesn't know
  about? Anything it calls "uncommitted" that is now committed, or the reverse? Local `dev` or
  `main` behind `origin` (you may not `fetch` — tell them to)? Paragraphs it marks as spent?
- **Release check.** If the handoff says a version was released to `main`, is that work actually
  in `main`? If not, say so plainly.
- **Stray branches.** Any branch other than `dev` and `main` is unexpected here; name it.
- **Readiness.** On `main`? Say to switch to `dev` before any edit. Uncommitted changes?
  Services from an earlier day still running? Open questions blocking scope?

## Name the session before you answer

This skill is almost always the session's first message, so the app titles the whole session
"Handoff" — and a sidebar of identical "Handoff" rows is useless a week later, when the thing
worth finding is *which* session touched *what*. If a session-management tool is available
(`mcp__ccd_session_mgmt__set_session_title`, `session_id: "self"`), rename it as the last
thing before you print the report.

Title it after the work this session is about to do, not after the orientation: the work item
key first, then two to four words of what it is. With nothing named, use the next action from
the handoff. If the answer is "blocked", say that instead. Keep it under about 30 characters
of signal; sidebars truncate. If the rename is declined because the user titled the session
themselves, drop it silently and print the report.

## Output — this template, in English, nothing before or after it

**State**
- last landed: <one line>
- in flight: <one line, or "nothing">
- next per handoff: <one line, or "none named">

**Handoff vs git** — omit the section entirely if consistent; otherwise a table, only the
mismatches:

| Handoff says | Actually |
|---|---|
| <claim, ≤ 10 words> | <fact, ≤ 12 words> |

**Merge check:** <one line, only if the assumed merge did not land>

**<WORK ITEM>** — only if one was named. ≤ 3 lines: status · what it asks · the one open
question, if any.

**Ready?** — list only the items that fail, one line each. If nothing fails, skip the list.
Then exactly one closing line: **ready** / **ready after: …** / **blocked by: …** — and, when
a work item was named, the branch name you would create.

## Rules that keep it short

- Write in English, always. The repo's own content — field names, ticket summaries, parts of
  the handoff — may be in another language. That is the subject matter, not a signal about
  which language to answer in.
- One fact per bullet, one line per bullet. No hashes, PR numbers or file paths unless a
  mismatch hinges on that exact value.
- Do not list things that are fine — the template's silence means "checked, OK".
- Do not propose branch names, plans or candidates unless a work item was named.
- Target: the whole reply fits on one screen (≈ 20 lines). Details are available on request.
- The rename is a tool call, not text. "Nothing before or after the template" is about what
  you print — do not announce the rename or mention the new title in the reply.
- Stop after the closing line. Do not implement, run checks, or create the branch.
