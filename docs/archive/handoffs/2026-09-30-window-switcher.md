# Handoff

Updated on 2026-09-30, late, after building ⌘§. The last release is release 3: GitHub pull request
#3 (`Luksanss/betterTab`) merged `dev` into `main` at 00:42, and pull request #4 fixed the release
workflow at 00:47. That run published **v0.1.49**, signed ad-hoc because the run found no
`SIGNING_CERT_P12` secret. The maintainer installed it and it works. The handoff as of that
release is archived at `docs/archive/handoffs/2026-09-30.md`.

Since the release, all on `dev` and not yet released:
- **The keycap icon labelled A** (concept B, "Key") replaced the window glyph, which looked like
  macOS's Screen Mirroring icon. It's now the menu-bar icon too, and a PNG of it is in the repo.
- **Bolder stack edges.** The maintainer checked them on the real switcher: "the edges look good
  now". That closes the question; variant C isn't needed.
- **The ⌘⇥ list forgets its titles when it closes** (`8992977`, from a separate task session).
- **⌘§**, a window switcher for the front app, which the maintainer asked for and designed with
  Claude Design (see Decisions). It's built, reviewed and checked offscreen, but it hasn't worked
  live yet: see Next action 1.

**Convention.** The current handoff lives at this path and is rewritten in place by every
`/handoff-update`. It's archived only **at a release**, when `dev` is merged into `main` because
the maintainer says a version works. At that point it's copied to
`docs/archive/handoffs/<ISO date>.md` in the same commit, with a topical suffix such as `-ci` (not
a number) if that date is taken. If the merge goes through a GitHub pull request, the archive
can't be in the merge commit, so the next `/handoff-update` on `dev` writes it; that's what
happened for releases 1, 2 and 3. This file is then started fresh. Never leave the live handoff
under `docs/archive/handoffs/`; readers are told to treat that directory as historical only.

This document records what is **not** obvious from the code or `git log`: decisions and the
reasoning behind them, findings that were expensive to learn, and the next action. There's no
ticket tracker; the next action below is the backlog.

## Working copy state

- **`main`** is `d565ede`, the merge of pull request #4: release 3. `origin/main` matches.
- **`dev`** is `main` plus the keycap icon, the release 3 archive, the bolder edges and their
  handoff, all pushed. On top of that, and not pushed: `8992977` (the list's titles), then this
  session's commits: the menu-bar icon, the Claude Design brief, window frames, ⌘§, its self-test
  scenarios, and the docs with this handoff.
- **A leftover worktree:** `.claude/worktrees/relaxed-swanson-940c4a` on branch
  `claude/relaxed-swanson-940c4a`, from the task session that made `8992977`. Its commit is on
  `dev` already, so the maintainer can remove the worktree and the branch.
- **The Debug build is running** (started 22:16), not the release, and it has every change in
  it. Quit it before starting the installed release, the self-test or a fresh Debug build: two
  copies means two key taps. The code hasn't changed since it was built; only docs have.
- **Accessibility had to be granted again** for this Debug build. It launched untrusted, showed
  the system prompt, and was trusted from 22:17. The Apple Development signing should have kept
  the old grant, and why it didn't is unknown.
- **Dev builds** go to `build/DerivedData.noindex`. The `CLAUDE.md` check passes. The only
  `warning:` line is `appintentsmetadataprocessor`'s "Metadata extraction skipped", a tool message
  that isn't from our code.
- **GitHub:** `Luksanss/betterTab` is public, with its history unchanged and no LICENSE.
- **Dev machine:** macOS 27.0.1 (26A434) on Apple Silicon, Xcode 27.0, Swift 6.4. An ISO keyboard
  with ABC and Czech-QWERTY layouts; the built-in 1512 × 982 display, and a 1920 × 1080 one to its
  left (x −1920 in global coordinates).

## Next action

1. **See ⌘§ work live.** The maintainer pressed it twice at 22:58, and both times the controller
   ended it at once: "⌘§: the front app has fewer than two windows". The log hides the pid, so it's
   unknown whether that app really had one window. Ask which app was in front. Then try it in
   Chrome ×2 (both full-screen) and in a Finder or TextEdit with windows on one Space, and read the
   log: `/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.luksanss.BetterTab"'`
   (plain `log` is a zsh builtin). If Chrome counts fewer than two, the check at the top of
   `WindowSwitchController.start` is the suspect: it counts `SkyLightWindows.snapshot()` windows
   for `NSWorkspace.frontmostApplication`. Then run acceptance tests 22–29.
2. **Fix the Space switch in `BetterTab/Focus/Focuser.swift`.** ⌘§ now depends on it: two
   full-screen Chrome windows are on two Spaces, and `activate`, the fallback, does nothing for an
   app that's already in front. Every cross-Space pick on 2026-09-30 logged "space didn't switch"
   after its 300 ms wait: 21 of 21, none "switched". The 17 picks on the current Space took 40–55 ms. Find out
   whether the slide starts later than 300 ms or never, and what makes it start for the front app.
3. **Run the self-test** when the Mac is free: `open -g …/Debug/BetterTab.app --args --self-test
   /abs/path/report.json`. It now has `windows-flip`, `windows-escape` and `windows-cycle` (in
   `BetterTab/Debug/SelfTestWindowScenarios.swift`). They need the home app to have two windows,
   and three for `windows-cycle`; scratch TextEdit documents work. They've never run.
4. **Push `dev` and merge it** when the maintainer is happy with the icon, the edges and ⌘§. That
   publishes the next release.
5. **Get the signing secrets working** (`docs/releasing.md` § Signing with your certificate). Check
   the names with `gh secret list`. The next run's summary says whether it signed. v0.1.49 is
   ad-hoc, so the first signed release makes macOS ask for Accessibility once more. After that,
   updates keep the grant.
6. **The maintainer runs acceptance tests 1–29 by hand** (`docs/spec.md`), especially 4 (flash),
   14 (`kill -9` recovery), 18 (the first-launch prompt: did it appear when v0.1.49 first
   launched?), 20 (other Spaces) and 22–29 (⌘§).
7. **Still to discuss** (the maintainer said "we will discuss later"):
   - making a quick ⌘⇥ flip-back always native, rather than depending on whether Accessibility
     answered in time;
   - marking list rows whose window is on another Space;
   - ⌘§ on ANSI keyboards, which have no § key (their key above Tab is ⌘`'s);
   - ⌘§'s order across Spaces (Findings).
8. **Optional: add a LICENSE.** The public repo is all rights reserved without one.

## Decisions already settled

- **⌘§: a window switcher for the front app** (maintainer, 2026-09-30).
  - The problem, in the maintainer's words: on Chrome, ⌘⇥ highlights the next app, so reaching the
    other Chrome window meant cycling through every app and back, then pressing S. The agent first
    pointed out ⌘⇥ ⇧⇥ (back onto Chrome), and then ⌘`; the maintainer proposed ⌘ plus the key above
    Tab instead.
  - "The behavior should be 1:1 with the cmd + tab", for that app's windows: hold ⌘, § steps, ⇧§
    steps back, release opens, and a quick tap flips. The agent added, and the maintainer didn't
    object: letters open a window at once, the mouse works, Esc cancels, there are at most 9 tiles,
    and an app with one window does nothing.
  - This overturns spec principle 3's "no extra shortcuts" and the old out-of-scope line "a
    separate shortcut, or a second mode". Both now name ⌘⇥ and ⌘§ as the only shortcuts.
  - The key is `kVK_ISO_Section` (10), which the tap swallows only with ⌘. On this Mac it types §;
    the keycap reads "><". ⌘` (key code 50, left of Z on ISO) stays macOS's.
  - **The look: direction 3, "window outlines"** (maintainer: "i love the 3rd option"). The brief is
    `docs/design-brief-v6.md`. Claude Design built all three directions (list, ⌘⇥-shaped panel,
    outlines) in `Window Switcher v6.dc.html` in the "Mac Window Switcher Prototype" project. The
    maintainer's first idea, window previews, was dropped: pictures need Screen Recording, and they
    aren't minimal.
  - Deviations from the prototype, agent's call: the HUD keeps one size per session (the widest
    title sets it) instead of resizing as the highlight moves; the display box takes each display's
    shape inside the 92 × 60 slot; and the pointer moves the highlight only after it has travelled
    3 pt, so a resting pointer under the HUD can't choose the window that ⌘'s release opens.
- **The menu-bar icon is the keycap too** (maintainer, 2026-09-30: "replace this old icon
  everywhere"). `BetterTab/App/StatusIcon.swift` draws it as a template: a solid face with the A cut
  out, and the key's front below it at 45%. It copies `design/icon/make-icon.swift`'s shapes by
  hand. `design/icon/AppIcon.png` is the Default rendition at 512 px for the README; re-export it
  when the icon changes (`design/icon/README.md`).
- **Stack edges: bolder, still inside the highlight** (maintainer asked for bolder, then approved,
  2026-09-30). Opacity `[0.85, 0.55]` dark and `[0.62, 0.40]` light (front, back); `rise` 0.041 of
  the body's side, `narrowing` 0.10. Variant C (`rise` 0.052, poking above the highlight) wasn't
  needed.
- **Stack edges replace the window-count dots** (maintainer, 2026-09-29). The dots were too close
  to the Dock's "running" dots. The top-centred stack beat the diagonal one, which looked like a
  Copy icon. One edge for two windows, two for three or more.
- **Releases: the free route, automatic on every push to `main`** (maintainer, 2026-09-29). There's
  no Developer ID and no notarization; users click Open Anyway once. There are no automatic
  updates, because the app has no network code. The version is `MARKETING_VERSION` plus the commit
  count, so `0.1.87` means 87 commits.
- **The first launch without Accessibility shows the system prompt once,** and **the menu shows the
  version** (maintainer, 2026-09-29). The flag is `promptedForAccessibility` in `UserDefaults`.
- **The app icon is a home-row keycap labelled A** (maintainer, 2026-09-30). It's an Icon Composer
  `.icon` generated by `design/icon/make-icon.swift`; don't edit `BetterTab/AppIcon.icon` by hand.
- **Route A+: hold macOS's own switcher open** (test 0, 2026-09-29), for ⌘⇥. Native ⌘⇥ is never
  turned off. ⌘§ doesn't use it: BetterTab draws that switcher entirely and holds nothing back.
- **A plain Xcode project with synchronized folders** (maintainer, 2026-09-29), with a throwaway
  `Experiment` target for test 0.
- **Windows on every Space, full-screen ones included, are in scope** (agent's call, 2026-09-29,
  after the first live run found nothing: the maintainer keeps Chrome and Claude full-screen).
  Accessibility stays the only permission. Background native tabs still don't count.
- **Sign with the maintainer's Apple Development certificate** (maintainer, 2026-09-29), not ad hoc,
  so the grant survives rebuilds (it didn't this once; see Working copy state).
- **The ⌘⇥ list ignores the mouse, and a click ends the switch** (test 0: any click closes the
  native switcher). The ⌘§ switcher does take the mouse, since nothing native is underneath.
- **⌘ pressed and released while the ⌘⇥ list is open cancels** (agent's call).
- **Focusing follows yabai (MIT, notice kept), not AltTab.**
- **Pick the window after releasing ⌘** (maintainer, 2026-09-29), for ⌘⇥: releasing on a
  multi-window app opens the list, and a letter picks. Don't reopen this without new evidence from
  daily use. ⌘§ is the opposite on purpose, because there you've already chosen to switch windows.
- **Letters, not numbers:** A S D F G H J K L, by physical key, labelled by the layout.
- **DockDoor isn't an option, and being minimal is the point** (maintainer, 2026-09-29). Treat
  every feature beyond `docs/spec.md` as needing a reason. "DockDoor has it" is not a reason.
- **One working branch** (maintainer, 2026-09-29). Commit straight to `dev`; `main` moves only when
  the maintainer says a version works, and every push to `main` publishes a release. Agents never
  push or open pull requests.
- **No ticket tracker.**

## Findings worth keeping

**From the ⌘§ session (2026-09-30, evening):**
- **SkyLight gives window frames with no permission.** `SLSGetWindowBounds(cid, wid, &rect)`
  answers for every window, including full-screen ones on other Spaces and windows on the second
  display at negative x, in global top-left coordinates. It's one round trip per window, so
  `SkyLightWindows.snapshot(framesOf:)` reads frames only for the app ⌘§ asks about; ⌘⇥'s snapshot
  stays at about 1 ms.
- **The ⌘⇥ list's order is wrong for ⌘§.** On the first, SkyLight-only delivery,
  `WindowReader.ordered` moves the main window remembered in `ElementCache` to the front, and right
  after a ⌘§ flip that's the window you just left. ⌘§ uses `WindowOrder.windowServer`: SkyLight's
  order, which puts the window you're in first. That order is close to most recently used, but a
  window on another Space always comes after the current Space's windows.
- **What `open` does with a running app.** `open build/…/BetterTab.app` on a copy that's already
  running only brings that copy forward; the maintainer quit the old one first. Check the process's
  start time against the binary's (`ps -o lstart`, `stat`) to know which build is live.
- **Plain `log` is a zsh builtin** (`too many arguments`). Use `/usr/bin/log show`.
- **Offscreen rendering can't show `NSVisualEffectView`.** It draws flat grey, so the agent's
  renders of `WindowSwitcherView` hid it and painted the design's colours behind. Whether `.hudWindow`
  looks right in light mode on screen is still unseen.
- **Claude Design projects are readable through `DesignSync`** (`get_file`), even an ordinary
  project rather than a design system. The v6 prototype is `Window Switcher v6.dc.html`. It has all
  three directions, the "Outlines: title" toggle (default Show), and the timings: the switcher shows
  160 ms after ⌥§, with no animation for outlines.
- **A review found no serious bugs** in the tap or the controller. Its smaller findings are fixed:
  the resting pointer; keys before the windows arrive are replayed; any ⌘-up ends Windows; the
  highlight follows its window when one drops out; a letter racing the ⌘ release still opens its
  window; frames only for ⌘§; the view forgets titles on hide.

**From the stack edges session (2026-09-30):**
- **The old edges drew exactly as coded; they were just thin and grey.** Pixels sampled from a
  screenshot of the real dark switcher gave the front edge 162 and the back edge 121, on a
  background of 49 (0–255).
- **The highlight's visible top is 8 pt above the icon's body, not the 8.5 pt the geometry
  predicts.** At `rise` 0.041 the back edge may overlap the highlight's top by about 0.4 pt; the
  self-test won't catch it, since it checks against the frame.
- **Comparing variants without touching the screen:** draw them the way `StackEdgesView.draw` does
  onto an old screenshot, in a scratch Swift script, and write PNGs.

**From the first releases (2026-09-30):**
- **`cmd | grep -q` fails a step under `pipefail`.** `grep -q` stops reading at the first match, so
  the writer dies of a broken pipe (exit 141). Read the output into a variable instead. GitHub runs
  `run:` steps with `bash -eo pipefail`.
- **The `xcode-27` runner works,** with Xcode 27.0 at `/Applications/Xcode_27.0.app`. It's GitHub's
  only hosted image with Xcode 27, a public preview whose label may be renamed at GA
  (`actions/runner-images#14404`).
- **actool fills every path in a layer, ignoring the SVG's `fill="none"`.** Check the icns from a
  real build (`iconutil -c iconset`), not just `ictool`. Draw letters as filled outlines.
- **Every build gets registered as an app.** A folder ending in `.noindex` keeps Spotlight out.
  `lsregister -u <path>` removes a stale record.
- **The release script was tested locally in both modes;** the workflow's keychain import still
  hasn't run, because no secret has reached it.

**From the 2026-09-30 build session, all on this Mac:**
- **The ⌘⇥ self-test passed 13 of 13 with `--long`.** Switcher up 150–180 ms after ⌘⇥, list 10–19
  ms after the release, picks 30–95 ms, timeout at 15.2 s. No window was on another Space.
- **The self-test needs a multi-window home app,** or it skips almost everything. Safe targets:
  scratch TextEdit documents, and Finder windows on empty folders. Open them with `open`, bring
  home to the front, then launch the test with `open -g`.
- **Coming back from a full-screen Space, the Dock shows no switcher until the slide ends,** so
  `SelfTest.restoreHome` waits 1.2 s whenever home's windows aren't on the current Space.
- **The native switcher's geometry** is in `docs/architecture.md` § How route A+ works.
- **Screenshots from the agent shell work; keys don't.** The shell (the Claude app) has Screen
  Recording but not Accessibility, so every key has to come from BetterTab's self-test.

**From the build session (2026-09-29), all on this Mac:**
- **Accessibility alone is enough for the key tap;** no Input Monitoring. On macOS 27 that pane is
  titled "Device Control and Data Access".
- **The native switcher,** as found through AX: the Dock-owned `AXProcessSwitcherList` appears about
  150–220 ms after ⌘⇥; items are matched to pids by name.
- **Windows on other Spaces:** SkyLight enumeration plus yabai's filter needs **no permission**;
  without Screen Recording titles come only through AX; `_SLPSSetFrontProcessWithOptions` alone,
  without Accessibility, makes the app frontmost but **doesn't switch Space**. Details in
  `docs/architecture.md` § Windows on every Space.
- **The screen locks after 20 minutes idle,** and a locked screen stops live tests. For long runs,
  `caffeinate -d -i -u`.
- **macOS 27 may not draw `NSMenuItem.image`,** so the status line draws its own dot.

**From the public-repo check (2026-09-29):** there are no secrets anywhere in history. The full
check is in `docs/archive/handoffs/2026-09-29-public-repo.md`.

**From the research before the build (2026-09-29):** AltTab and DockDoor are GPL-3.0 and only read;
WindowLens is MIT. The native ⌘⇥ switcher can't be modified but can be read through AX, and a
session tap can swallow keys while it's up. Replacing it (route B) means turning native ⌘⇥ off with
`CGSSetSymbolicHotKeyEnabled`, which outlasts the process. Public APIs can't reliably focus one
window. The detail and the API table are in `docs/architecture.md`.

## Known gaps

- **⌘§ hasn't worked live.** Its two presses ended as "fewer than two windows" (Next action 1). The
  outline view was only checked offscreen, and its material never on screen.
- **Cross-Space focusing falls back to `activate` every time,** which can't help ⌘§ (Next action 2).
- **The release workflow's keychain import has never run.**
- **The first-launch prompt is unconfirmed for v0.1.49** (acceptance test 18).
- **Unverified on macOS 27:**
  - whether another window of the app flashes before the picked one;
  - whether a lone make-key mouse down leaves an app thinking the button is held;
  - tag bit 60 for minimized windows.
- **Nobody but the maintainer has installed it yet.**
- **The build check is manual.** The only workflow is the release.

## Safety constraints

Nothing is deployed anywhere except the release zips on GitHub. The risk is to the maintainer's
own Mac: the app under development changes system state on the machine it runs on.

- **Route A+: never leave a ⌘ release swallowed.** Swallowing the ⌘ release holds the Dock's
  switcher open, and apps may believe ⌘ is still down. Every way out of Picking must post a
  synthetic ⌘ release: pick, cancel, the 15 s timeout, the tap being turned off
  (`kCGEventTapDisabledByTimeout`), and quit. The expected recovery if BetterTab dies mid-hold is
  to press and release ⌘ once more; acceptance test 14 still has to verify that.
- **⌘§ swallows keys but never ⌘.** In the tap's Windows phase every keyDown is swallowed while ⌘
  is held, and any ⌘-up ends it. Keep it that way: if a change ever swallowed a ⌘ release there,
  it would need Picking's synthetic-release discipline too.
- **Route A+ never turns off native ⌘⇥.** If anything starts calling
  `CGSSetSymbolicHotKeyEnabled`, route B has been chosen. Record that decision here first.
- **If route B is ever built, never leave native ⌘⇥ turned off.** Turn symbolic hotkeys 1 and 2
  back on when the app quits, when it receives `SIGTERM`, and at the next launch if the previous
  run didn't exit cleanly. Before the first build that turns ⌘⇥ off, commit
  `scripts/restore-native-cmd-tab.swift`. Its source is in `docs/architecture.md` § Recovery.
