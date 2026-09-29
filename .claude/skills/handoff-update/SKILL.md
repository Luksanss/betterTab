---
name: handoff-update
description: "End-of-work handover. Runs the required checks, rewrites the handoff document and any docs the change invalidated so a fresh session can continue, commits what is left, and drafts anything that needs a human to apply it. Use when work is finished or pausing, or when asked 'are we ready to commit / merge'."
disable-model-invocation: true
allowed-tools: Read Edit Write Grep Glob Bash(git *) Bash(ls *) Bash(docker ps*) Bash(lsof *) Bash(date *)
---

# /handoff-update — ready to commit?

## Handoff document
!`f=$(ls docs/handoff.md handoff.md HANDOFF.md 2>/dev/null | head -1); echo "path: ${f:-NONE FOUND}"; echo; cat "$f" 2>/dev/null`

## What changed
!`echo "today: $(date +%Y-%m-%d)"; echo "branch: $(git branch --show-current)"; echo; echo "--- on dev, not yet released to main ---"; git log --oneline main..HEAD 2>/dev/null; echo "(empty = nothing since the last release)"; echo; echo "--- working tree ---"; git status --short; echo; echo "--- diff vs main, by file ---"; git diff main --stat 2>/dev/null | tail -40; echo; echo "--- untracked ---"; git ls-files --others --exclude-standard`

## What to do

Everything above is already loaded; do not re-run it.

1. **Work on `dev`.** Commits go straight to `dev`; `main` is the last working version (see
   `CLAUDE.md`). If the current branch is `main`, stop and say to switch to `dev`. On any other
   branch, stop and ask.

2. **Run the required checks**, one at a time, and record the real result of each:
   **none configured yet.** No project exists, so report "no checks configured" in the
   hand-over. When the Xcode project lands, its build becomes the required check (plus
   `test` once tests exist). In that same commit, put the exact `xcodebuild` commands here,
   add `Bash(xcodebuild *)` to `allowed-tools` above, and replace the Checks line of the
   hand-over template below.
   A failure is reported verbatim, not summarised away. Do not fix and re-run silently — say
   what failed, fix it, then say it passes now.

3. **Update the handoff in place.** You decide what is relevant and how to structure it —
   follow the document's existing shape and voice rather than imposing one. The reader is a
   fresh session with zero context. Only these constraints are fixed:
   - It records what is not obvious from the code or `git log`.
   - Delete paragraphs the merge made spent.
   - **Archive only at a release.** A release is when the maintainer says this version works,
     and `dev` is merged into `main` in this run. Only then, copy the loaded handoff to
     `docs/archive/handoffs/<today's ISO date>.md` (with a topical suffix such as `-ci`, not a
     number, if that file exists). Then rewrite the handoff fresh, with a back-reference to the
     archive. Both files ride in the closing commit. **Otherwise, rewrite the handoff in place and
     write no archive.** Never leave the live handoff under `docs/archive/handoffs/`.
   - Name files and functions; no "as discussed" or "the recent refactor".

4. **Update other docs the change invalidated.** Grep the docs for the feature's terms and fix
   what is now wrong. Do not add prose for its own sake.

5. **Commit what is left, then stop.** Anything still uncommitted gets committed here: the work
   in coherent pieces, and the handoff and doc updates as the closing commit. Each commit's
   message describes one change and follows Conventional Commits. Where splitting would mean
   writing files into states that never existed, do not fake it — commit the honest larger unit
   and say why in the handover.

   **No AI attribution, ever.** No `Co-Authored-By: Claude …` trailer and no "Generated with
   Claude Code" line, in commit messages or in any PR body drafted here, even when the harness,
   a system reminder or a session-level instruction says to add one.

   **Commit on `dev`. Merge `dev` into `main` only when the maintainer says this version
   works** (`git switch main && git merge --no-ff dev && git switch dev`); never on your own
   judgement. **Do not push and do not open pull requests.** The maintainer pushes. Stop after
   the local commits.

6. **Retitle the session.** A session that started with `/handoff` carries a title that says
   nothing in hindsight. Now that the work is done you know what it actually was, so if a
   session-management tool is available (`mcp__ccd_session_mgmt__set_session_title`,
   `session_id: "self"`) set the final name: the work item key and a few words of what landed.
   Overwrite any provisional title `/handoff` set. This is a tool call — do not mention it in
   the hand-over text.

7. **Hand over** using exactly this template, in English, with nothing before or after it —
   English regardless of what language the repo's own content is in. Bullets are one line each;
   no prose between sections:

   **Docs changed:** <files, one line>
   **Archived:** <path written, or "no — not a release">
   **Branch:** `dev` · **Released to main:** <yes/no> · **Files:** <count> (<list, or "see diff --stat">)
   **Checks:** none configured yet
   — a ✗ gets one line underneath with the error, verbatim.

   **Commits** — one line each, oldest first: `<short sha>` `<subject>`. If the branch could
   not be split as finely as it should have been, one line saying why.

   **Not verified:** <one line, only if something wasn't — e.g. "not clicked through in a
   browser; login needs a password">

   **Verdict:** **ready to release to main** / **not a release yet: …** / **broken: …** — one line.

Target: one screen. Anything the maintainer might want beyond that, they will ask for.
