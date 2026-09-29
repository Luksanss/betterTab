# Handoff

Written 2026-09-29, when the handoff system was set up. There is no earlier session to carry
forward. This first version records the working copy as it stands, the idea validation done that
day, and the conventions agreed at setup. Everything below is meant to be rewritten by
`/handoff-update` as work lands. Treat the structure as a starting point, not a form to fill in.

**Convention.** The current handoff lives at this path and is rewritten in place by every
`/handoff-update`. It's archived only **at a release**, when `dev` is merged into `main` because
the maintainer says a version works. At that point it's copied to
`docs/archive/handoffs/<ISO date>.md` in the same commit, with a topical suffix such as `-ci` (not
a number) if that date is taken. This file is then started fresh. Never leave the live handoff
under `docs/archive/handoffs/`; readers are told to treat that directory as historical only.

This document records what is **not** obvious from the code or `git log`: decisions and the
reasoning behind them, findings that were expensive to learn, and the next action. There's no
ticket tracker; the next action below is the backlog.

## Working copy state

There are two branches and no remote (see `CLAUDE.md` § Branches, commits and handoffs):
- **`dev`** is where all work is committed. As of 2026-09-29 it holds `Initial commit` plus four
  docs commits:
  - the product docs, spec, architecture and the v5 design brief;
  - the repo-local handoff skills;
  - `CLAUDE.md` with this handoff;
  - a commit restoring those skills to their installed template form (the maintainer doesn't want
    them edited).
- **`main`** is the last working version. It's still `087e07e Initial commit`, because nothing
  works yet. It moves when the maintainer says a version works.

No code exists yet. Nothing project-related runs locally. The listeners on :5000 and :7000 are
macOS AirPlay Receiver (ControlCenter); :37701 is the claude-mem worker; :44950 and :44960 are
the Figma desktop agent. The dev machine: macOS
27.0 on Apple Silicon, Xcode 27.0, Swift 6.4. Neither XcodeGen nor Tuist is installed.

## Next action

1. **The maintainer creates design v5 in Claude Design** from `docs/design-brief-v5.md`. The
   project is "Mac Window Switcher Prototype"; v4 is `Window Switcher v4.dc.html`, reviewed
   2026-09-29. Check v5 against `docs/spec.md`, which has 19 acceptance tests.
2. **Run experiment test 0 before anything else** (`docs/architecture.md` § The experiment). It
   decides the route: can a swallowed ⌘ release hold the native switcher open? Build it as a
   throwaway menu-bar target. **If test 0 passes, use route A+; if it fails, use route B.** Record
   the result under Decisions already settled, with what failed.
3. Then run experiment tests 1–3: read the switcher, list windows, and focus one without a flash.
4. Once a build exists, record its `xcodebuild` command as the required check in `CLAUDE.md`
   § Branches, commits and handoffs. Don't edit the handoff skills in `.claude/skills/`: the
   maintainer keeps them as installed, and repo specifics belong in `CLAUDE.md`.

**Open decisions:**
- **Route A+ or B.** Test 0 decides; nothing else does.
- **How to set up the project.** A plain Xcode project with synchronized folders, or XcodeGen.
  A plain Xcode project is recommended: there's nothing to install.

## Decisions already settled

- **Pick the window after releasing ⌘** (maintainer, 2026-09-29).
  - Releasing on a multi-window app doesn't switch. The switcher stays, and a window list opens
    above the icon.
  - Single-window apps switch natively.
  - Window-count dots under the icons show beforehand which apps will ask.
  - The alternative was picking while ⌘ is held, with release confirming the most recent window.
    The maintainer rejected it: the list only appears for multi-window apps, so choosing is an
    expected step. The accepted cost is one key press (A) even for the most recent window.
  - Don't reopen this without new evidence from daily use.
- **Letters, not numbers:** A S D F G H J K L, the physical home-row keys, restarting at A for
  each app (maintainer's v4 design, 2026-09-29). Labels follow the keyboard layout.
- **Personal use only, for now** (maintainer, 2026-09-29). The App Store is ruled out anyway,
  because its sandbox forbids the Accessibility and private APIs this app needs. No Developer ID
  signing, notarization or update channel until that changes.
- **DockDoor isn't an option, and being minimal is the point** (maintainer, 2026-09-29).
  DockDoor already puts a window picker on the native ⌘⇥, but the maintainer considers it far too
  bloated to use. BetterTab exists to do this one thing and nothing else. Treat every feature
  beyond `docs/spec.md` as needing a reason. "DockDoor has it" is not a reason.
- **One working branch** (maintainer, 2026-09-29).
  - Commit straight to `dev`, with no feature branches and no pull requests. It's one developer
    and one user.
  - `main` is the last working version. Merge `dev` into it only when the maintainer says a
    version works.
  - Agents never push; the maintainer does, once a remote exists.
- **No ticket tracker.**

## Findings worth keeping

These come from research on 2026-09-29, reading the source of three apps: AltTab
(`lwouis/alt-tab-macos`, GPL-3.0), DockDoor (`ejbills/DockDoor`, GPL-3.0) and WindowLens
(`FornaxChemica/WindowLens`, MIT). Plus a read-only probe on this machine. None of it has been
used in this repo's code yet. The detail and API table are in `docs/architecture.md`.

- **Nobody is known to hold the native switcher open by swallowing the ⌘ release.** Route A+
  rests entirely on that unverified trick. DockDoor and WindowLens only *read* the switcher and
  swallow other keys.
- **The native ⌘⇥ switcher can't be modified, but it can be read.** The Dock draws it, and
  changing that would mean injecting code into the Dock, which requires turning off System
  Integrity Protection. Ruled out. What works without that:
  - While the switcher is up, the Dock exposes it through Accessibility as an element with the
    subrole `AXProcessSwitcherList`, and its selected child is the highlighted app.
  - A session-level event tap sees ⌘⇥, can swallow other keys while the switcher is open, and
    sees ⌘ being released.

  DockDoor and WindowLens both ship this approach. Sources:
  `DockDoor/Utilities/DockObserver+CmdTab.swift`, `KeybindHelper.swift`, and WindowLens
  `Sources/Core/Accessibility/DockProcessSwitcherObserver.swift`.
- **Replacing the switcher (route B) means turning native ⌘⇥ off,** using the private
  `CGSSetSymbolicHotKeyEnabled` on symbolic hotkeys 1 and 2. That lasts after the process exits,
  so a crash leaves the Mac with no ⌘⇥. Route A+ never touches it.
- **Public APIs can't reliably focus a specific window.** Since macOS 14,
  `NSRunningApplication.activate` is only a request. The sequence AltTab uses:
  1. the private `_SLPSSetFrontProcessWithOptions(psn, windowID, userGenerated)`;
  2. a nudge that makes the window key;
  3. `kAXRaiseAction`.

  Source: `src/switcher/state/Window.swift`, `applyFocus`. AltTab is still fixing this code in
  September 2026. It's the riskiest part of the project.
- **Window titles need Accessibility; thumbnails need Screen Recording.** The AX API returns
  titles with Accessibility alone. Window names from `CGWindowList` and any window image also
  need Screen Recording. The MVP plan is titles only.
- **Deciding which windows count is harder than it looks.** Dialogs, palettes and sidebars show up
  as AX windows too. AltTab's filter is `src/switcher/state/WindowAdmissionResolver.swift`.
- **AltTab and DockDoor are GPL-3.0.** Read them to learn how things work; copying their code
  would make this project GPL. WindowLens is MIT, so its code can be reused as long as its
  copyright notice is kept.
- **The gap is narrow.** AltTab's request to group windows by app and drill in
  (lwouis/alt-tab-macos#337) has been open since 2020-05-13. But DockDoor and WindowLens already
  put a window picker on top of the native ⌘⇥. They're preview-first: they show thumbnails and
  so need Screen Recording. That leaves BetterTab with titles only, letter keys, and
  Accessibility as the only permission.

## Known gaps

- No Xcode project, build or tests, so there are no checks. `/handoff-update` says so until a
  build exists.
- No remote and no CI.
- No signing identity has been chosen. macOS ties the Accessibility grant to the code signature,
  so ad-hoc-signed rebuilds are expected to lose it every time. This is known macOS behaviour but
  hasn't been hit here yet.

## Safety constraints

Nothing is deployed anywhere. The risk is to the maintainer's own Mac: the app under development
changes system state on the machine it runs on.

- **Route A+: never leave a ⌘ release swallowed.** Swallowing the ⌘ release holds the Dock's
  switcher open, and apps may believe ⌘ is still down. Every way out of Picking must post a
  synthetic ⌘ release: pick, cancel, the 15 s timeout, the tap being turned off
  (`kCGEventTapDisabledByTimeout`), and quit. The expected recovery if BetterTab dies mid-hold is
  to press and release ⌘ once more; experiment test 0g verifies that before anything else is
  built.
- **Route A+ never turns off native ⌘⇥.** If anything starts calling
  `CGSSetSymbolicHotKeyEnabled`, route B has been chosen. Record that decision here first.
- **If route B is ever built, never leave native ⌘⇥ turned off.** Turn symbolic hotkeys 1 and 2
  back on when the app quits, when it receives `SIGTERM`, and at the next launch if the previous
  run didn't exit cleanly. The dev loop *will* crash the app. So before the first build that turns
  ⌘⇥ off, commit `scripts/restore-native-cmd-tab.swift`. Its source is in `docs/architecture.md`
  § Recovery.
