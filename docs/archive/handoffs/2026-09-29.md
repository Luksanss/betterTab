# Handoff

Updated on 2026-09-29 at the end of the session that built the whole app. The first live run found
nothing to show, because the maintainer keeps windows full-screen on separate Spaces. That led to
listing windows on every Space. The rebuilt version then worked live at 22:57 ("works perfect",
maintainer): the list showed Chrome's 3 windows, 2 full-screen, all titled, and picks landed. The
self-test hasn't run yet.

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

- **`dev`** holds everything: the Xcode project, the app, the test 0 harness (`Experiment`), the
  debug self-test and the docs. `origin` is on GitHub. The session's 22 commits (`16bc688` to the
  closing handoff commit) are **not pushed**; agents never push.
- **`main`** is still `087e07e Initial commit`. Merging `dev` is the maintainer's call (see
  `CLAUDE.md`); archive this handoff in that commit.
- **Build:** the `CLAUDE.md` check passes. Both targets are signed with the maintainer's Apple
  Development certificate (Personal Team `5KDU5HYH35`), so the Accessibility grant survives
  rebuilds. The Debug app at `build/DerivedData/Build/Products/Debug/BetterTab.app` is granted and
  was running at the end of the session.
- **Dev machine:** macOS 27.0.1 (26A434) on Apple Silicon, Xcode 27.0, Swift 6.4. At the session's
  start, :5000/:7000 were AirPlay, :37701 the claude-mem worker and :44950/:44960 the Figma agent.

## Next action

1. **Run the self-test** while nobody is using the Mac. The command is in `CLAUDE.md`. Quit
   BetterTab first, and keep the screen from locking with `caffeinate -u`. Iterate on the report
   (`--long` adds the 15 s timeout).
2. **Fix the Space switch in `BetterTab/Focus/Focuser.swift`.** Every cross-Space pick in the live
   run logged `space didn't` after its 300 ms poll and fell back to `activate`, taking about 336 ms
   before the fallback even started. The maintainer still saw the right window. Find out whether
   the slide just takes longer than 300 ms, or whether only `activate` moves the Space, and drop
   the fallback's extra delay.
3. **The maintainer runs acceptance tests 1–20 by hand** (`docs/spec.md`), especially 4 (flash) and
   20 (other Spaces).
4. **Still owed from test 0:** 0a (hold ≥ 15 s), 0e (Esc cancels on a non-front app), 0g (`kill -9`
   recovery). These are acceptance tests 15, 7 and 14.
5. **When the maintainer says this version works,** merge `dev` into `main` and archive this handoff.

## Decisions already settled

- **Route A+: hold macOS's own switcher open** (test 0, 2026-09-29). The hold works with the session
  tap; the evidence is in `docs/architecture.md` § Test 0 results. Native ⌘⇥ is never turned off.
- **A plain Xcode project with synchronized folders** (maintainer, 2026-09-29), with a throwaway
  `Experiment` target for test 0.
- **Windows on every Space, full-screen ones included, are in scope** (agent's call, 2026-09-29,
  after the first live run found nothing: the maintainer keeps Chrome and Claude full-screen). The
  maintainer then used it live and called it working. Accessibility stays the only permission:
  SkyLight lists the windows with no permission, and AX supplies titles. Background native tabs
  still don't count.
- **Sign with the maintainer's Apple Development certificate** (maintainer, 2026-09-29), not ad hoc.
  An ad-hoc build's designated requirement is its cdhash, so every rebuild lost the grant.
- **The list ignores the mouse, and a click ends the switch** (test 0: any click, even on our own
  panel, closes the native switcher).
- **⌘ pressed and released while the list is open cancels** (agent's call). It doubles as the
  recovery gesture if anything seems stuck.
- **Focusing follows yabai (MIT, notice kept), not AltTab.** Make-key posts a mouse down only, at a
  point far past the window, so nothing can be clicked or resized (AltTab #5381/#5900, facts only).

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

**From this session (2026-09-29), all on this Mac:**
- **The live run at 22:57** (logs, subsystem `com.luksanss.BetterTab`):
  - the switcher was found in 170–183 ms and all 6 icons matched by name;
  - Chrome's list showed 3 windows, 2 full-screen, with none untitled and none missing an AX
    element, so titles resolve across Spaces;
  - focusing reported make-key `true` and raise `ok`, but `space didn't` switch in 300 ms (see Next
    action 2).
- **Accessibility alone is enough for the key tap.** BetterTab never asks for Input Monitoring, and
  its tap ran and swallowed releases with only Accessibility granted. On macOS 27 that pane is
  titled "Device Control and Data Access".
- **Test 0:** the hold, mouse moves, swallowed letters, the synthetic release finishing a switch, ⌘
  not stuck, and ⌘⇥ again all pass. See `docs/architecture.md` § Test 0 results.
- **The native switcher,** as found through AX: the Dock-owned `AXProcessSwitcherList` is found about
  220 ms after ⌘⇥; items are matched to pids by name (the Dock gives no `AXURL`). Its window is
  full-screen at layer 20.
- **Windows on other Spaces:** see `docs/architecture.md` § Windows on every Space. The expensive
  facts:
  - SkyLight enumeration plus yabai's filter returns exactly the real windows with **no
    permission**;
  - without Screen Recording the window server returns **empty titles**, so titles only come
    through AX;
  - `_SLPSSetFrontProcessWithOptions` alone, without Accessibility, makes the app frontmost but
    **doesn't switch Space**.
- **Permissions for testing:**
  - the agent shell (the Claude app) has Screen Recording but not Accessibility;
  - a `.app` launched with `open` runs under its own TCC identity, which is useful for probing what
    works with no permission.
- **The screen locks after 20 minutes idle,** and a locked screen stops live tests (the self-test
  refuses to run then). For long unattended runs, keep the Mac awake with `caffeinate -u`.
- **macOS 27 may not draw `NSMenuItem.image`,** so the status line draws its own dot. This came from
  an in-process capture the maintainer's typing may have disturbed; the code works either way.

**From the research before the build:**

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

- **The self-test has never run.** Whether the Dock reacts to synthetic ⌘⇥ is its first question.
- **Unverified on macOS 27:**
  - how long the Space slide takes, and whether steps 4–6 of the focus sequence move the Space
    without `activate`;
  - whether another window of the app flashes before the picked one;
  - whether a lone make-key mouse down leaves an app thinking the button is held;
  - tag bit 60 for minimized windows.
- **No CI.** The build check is run by hand.

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
