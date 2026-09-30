# Handoff

Updated on 2026-09-30, after making the stack edges bolder. The last release is release 3: GitHub
pull request #3 (`Luksanss/betterTab`) merged `dev` into `main` at 00:42, with the stack edges, the
first-launch prompt, the version in the menu, the app icon, the release workflow and the shorter
README. The handoff as of that release, with the story of the session that built it, is archived
at `docs/archive/handoffs/2026-09-30.md`.

The first release run failed at "Select Xcode 27" (see Findings). Pull request #4 fixed it and
merged at 00:47, and that run published **v0.1.49**, the first release. The maintainer installed it
in `/Applications` and it works. It's signed ad-hoc, because the run found no `SIGNING_CERT_P12`
secret.

After the release, the maintainer asked for a different app icon: the window glyph looked like
macOS's Screen Mirroring icon. `dev` now carries the keycap icon (concept B, "Key"), and it's
pushed.

Then the maintainer looked at the stack edges on the real switcher, in v0.1.49, and found them too
faint in both appearances: "light mode is a bit better but still not enough, dark mode is rough".
The next session made them bolder in `BetterTab/StackEdges/StackEdgesOverlay.swift` (see
Decisions). That commit isn't pushed.

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
- **`dev`** is `main` plus the keycap icon and the release 3 archive, both pushed, then two
  commits that aren't pushed: the bolder stack edges and this handoff.
- **Releases:** v0.1.49 is the latest, signed ad-hoc. The run log shows `P12:` empty, so either the
  secrets were never added or their names don't match `SIGNING_CERT_P12` and
  `SIGNING_CERT_PASSWORD`.
- **The Debug build is running, not the release.** The maintainer quit
  `/Applications/BetterTab.app` 0.1.49 so the bolder edges could be tried. Quit the Debug copy
  before starting the release again: two copies means two key taps both holding the switcher. The
  same goes the other way for live tests and the self-test.
- **Dev builds** go to `build/DerivedData.noindex`, which keeps them out of Spotlight. The
  `CLAUDE.md` check passes. The only `warning:` line is `appintentsmetadataprocessor`'s "Metadata
  extraction skipped", a tool message that isn't from our code.
- **GitHub:** `Luksanss/betterTab` is public, with its history unchanged and no LICENSE.
- **Dev machine:** macOS 27.0.1 (26A434) on Apple Silicon, Xcode 27.0, Swift 6.4.

## Next action

1. **The maintainer's verdict on the bolder stack edges,** in both appearances on the real
   switcher. The agent only saw them in an offscreen mock. The maintainer went to the handover
   without asking for more. If they're still too faint, the next step is variant C (see
   Decisions), which means changing a spec rule first. A switcher crowded enough to shrink its
   icons, and a second display, are still unchecked.
2. **Push `dev` and merge it** when the maintainer is happy with the keycap icon and the edges.
   That publishes them as the next release.
3. **Get the signing secrets working** (`docs/releasing.md` § Signing with your certificate). Check
   the names with `gh secret list`. The next run's summary says whether it signed. v0.1.49 is
   ad-hoc, so the first signed release makes macOS ask for Accessibility once more. After that,
   updates keep the grant.
4. **Fix the Space switch in `BetterTab/Focus/Focuser.swift`.** Every cross-Space pick in the first
   live run logged `space didn't` after its 300 ms poll and fell back to `activate`, which took
   about 336 ms before the fallback even started. The self-test runs didn't cover this, because no
   multi-window app had a window on another Space. Set one up (a Finder or TextEdit window made
   full-screen), quit the installed copy, and run the self-test with `--pause 3`.
5. **The maintainer runs acceptance tests 1–21 by hand** (`docs/spec.md`), especially 4 (flash),
   14 (`kill -9` recovery), 18 (the first-launch prompt) and 20 (other Spaces). For 18: did the
   system prompt appear when v0.1.49 first launched? The ad-hoc release had no grant yet, and the
   prompt flag was never set, because the Debug builds were always trusted.
6. **Still to discuss, from the brainstorm** (the maintainer said "we will discuss later"):
   - making a quick ⌘⇥ flip-back always native, rather than depending on whether Accessibility
     answered in time;
   - marking list rows whose window is on another Space.
7. **Optional: add a LICENSE.** The public repo is all rights reserved without one.

## Decisions already settled

- **Stack edges replace the window-count dots** (maintainer, 2026-09-29).
  - The maintainer found the dots too close to the Dock's "running" dots. They picked "stacked
    edges" from four mocks: dots, a count badge, stacked edges and a keycap chip.
  - The agent chose the top-centred stack over the diagonal one from the mock, after prototyping
    both on a screenshot of the real switcher. It's symmetrical and stays inside the Dock's
    highlight. The diagonal one looked like a Copy icon.
  - One edge for two windows, two for three or more. The exact count is the list's job.
- **Stack edges: bolder, still inside the highlight** (maintainer asked for bolder, 2026-09-30; the
  agent chose how far to go).
  - Opacity went from `[0.56, 0.34]` dark and `[0.36, 0.22]` light (front edge, back edge) to
    `[0.85, 0.55]` and `[0.62, 0.40]`.
  - `rise` went from 0.035 to 0.041 of the body's side, so each visible strip is about 3.2 pt, up
    from 2.6. `narrowing` went from 0.12 to 0.10, so the edges read more like windows.
  - The strips can't get thicker inside the highlight: two edges now rise 8.4 pt, and the room is
    8.5 pt. Acceptance test 2 says "The edges stay inside the switcher's highlight", and the
    self-test fails edges within 4 pt of the icon frame's top.
  - **Variant C, if still too faint:** `rise` 0.052, so strips of about 4.4 pt. The back edge then
    pokes about 2 pt above the highlight on the selected app. That needs the maintainer to drop
    the spec line, and the self-test headroom check in `SelfTestScenarios.swift` to go with it.
    The mock showed it as clearly bolder, but crossing the highlight looks less tidy.
- **Releases: the free route, automatic on every push to `main`** (maintainer, 2026-09-29). There's
  no Developer ID and no notarization; users click Open Anyway once, and the maintainer considers
  that normal on macOS. There are no automatic updates, because the app has no network code.
  - This replaces "personal use only".
  - The version is `MARKETING_VERSION` plus the commit count, so `0.1.87` means 87 commits.
- **The first launch without Accessibility shows the system prompt once,** and **the menu shows the
  version** (maintainer, 2026-09-29, from the brainstorm). The flag is `promptedForAccessibility`
  in `UserDefaults`, so the spec's privacy line now names two saved values.
- **The app icon is a home-row keycap labelled A** (maintainer, 2026-09-30). The first icon, the
  menu-bar glyph scaled up, looked like macOS's Screen Mirroring icon. The menu-bar item keeps the
  window glyph. The icon is an Icon Composer `.icon`, and its source is
  `design/icon/make-icon.swift`; don't edit `BetterTab/AppIcon.icon` by hand.
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
  An ad-hoc build's designated requirement is its cdhash, so every rebuild lost the grant. The
  same reasoning is why releases should be signed through the secrets.
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
  - The stack edges show beforehand which apps will ask.
  - The alternative was picking while ⌘ is held, with release confirming the most recent window.
    The maintainer rejected it: the list only appears for multi-window apps, so choosing is an
    expected step. The accepted cost is one key press (A) even for the most recent window.
  - Don't reopen this without new evidence from daily use.
- **Letters, not numbers:** A S D F G H J K L, the physical home-row keys, restarting at A for
  each app (maintainer's v4 design, 2026-09-29). Labels follow the keyboard layout.
- **DockDoor isn't an option, and being minimal is the point** (maintainer, 2026-09-29).
  DockDoor already puts a window picker on the native ⌘⇥, but the maintainer considers it far too
  bloated to use. BetterTab exists to do this one thing and nothing else. Treat every feature
  beyond `docs/spec.md` as needing a reason. "DockDoor has it" is not a reason.
- **One working branch** (maintainer, 2026-09-29).
  - Commit straight to `dev`, with no feature branches. It's one developer and one user.
  - `main` is the last working version. Merge `dev` into it only when the maintainer says a
    version works. The maintainer may do that through a GitHub pull request, as for releases 1
    to 3. Every push to `main` now publishes a release.
  - Agents never push or open pull requests; the maintainer does both. The 2026-09-30 session had
    a one-time exception, which it used for pull requests #3 and #4.
- **No ticket tracker.**

## Findings worth keeping

**From the stack edges session (2026-09-30):**
- **The old edges drew exactly as coded; they were just thin and grey.** Pixels sampled from a
  screenshot of the real dark switcher gave the front edge 162 and the back edge 121, on a
  background of 49 (0–255). That's what alphas 0.56 and 0.34 of white give. Each visible strip was
  about 2.6 pt: `rise` minus the 1 pt gap.
- **The highlight's visible top is 8 pt above the icon's body, not the 8.5 pt the geometry
  predicts.** Measured on the same 2× screenshot: body top at 98 px, highlight top at 82 px. So at
  `rise` 0.041 the back edge may overlap the highlight's top by about 0.4 pt. The self-test won't
  catch it, since it checks against the frame.
- **How the variants were compared, without touching the screen:** a Swift script drew the edges
  the way `StackEdgesView.draw` does onto an old screenshot of the real switcher (dark), and onto a
  stand-in with `NSWorkspace` icons (light). Both went to PNG. The script and screenshot were in a
  session scratchpad and are gone; rebuild them from `StackEdgesOverlay.stack` if needed.

**From the first releases (2026-09-30):**
- **`cmd | grep -q` fails a step under `pipefail`.** `grep -q` stops reading at the first match, so
  `xcodebuild -version` crashed with a broken pipe while writing its second line. The shell
  reported exit 141 every time, on the runner and on this Mac. That's what failed the first release
  run. Read the output into a variable and compare it instead. GitHub runs `run:` steps with
  `bash -eo pipefail`, so test workflow steps locally the same way.
- **The `xcode-27` runner works.** The release run took about a minute, with Xcode 27.0 at
  `/Applications/Xcode_27.0.app`. The version came out as 0.1.49: `MARKETING_VERSION` 0.1 plus 49
  commits on `main`.
- **actool fills every path in a layer, ignoring the SVG's `fill="none"`.** A stroked letter comes
  out as a solid shape in the compiled icon, although Icon Composer's `ictool` preview draws the
  stroke correctly. So check the icns from a real build (`iconutil -c iconset`), not just `ictool`.
  Draw letters as filled outlines; `make-icon.swift` builds the A from three capsules, one
  `<path>` each.
- **Every build gets registered as an app.** Spotlight and Launch Services listed every Debug,
  Release and Experiment build, plus about 40 deleted ones. A folder ending in `.noindex` keeps
  Spotlight out. `lsregister -u <path>`
  (`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`)
  removes a stale record.

**From the 2026-09-30 build session, all on this Mac:**
- **The self-test passes: 13 of 13 with `--long`.**
  - The switcher was up 150–180 ms after ⌘⇥.
  - The list opened 10–19 ms after the release.
  - Picks took 30–95 ms, and the timeout fired at 15.2 s.
  - The targets were TextEdit ×2 (home), Finder ×3 (multi) and Claude ×1 (single). No window was on
    another Space, so cross-Space picking wasn't exercised.
- **The self-test needs a multi-window app on screen,** or it skips almost everything. That's how
  the first run went: the maintainer's Chrome had one real window, full-screen, and Notes wasn't
  running. Safe targets:
  - scratch TextEdit documents, so a stray letter lands in a scratch file;
  - Finder windows on empty folders, so Return has nothing to rename.

  Open them with `open` and bring the home app to the front before launching the test with
  `open -g`.
- **Coming back from a full-screen Space, the Dock shows no switcher until the slide ends.** The
  frontmost app changes before the slide starts. The stack-edges scenario, which follows
  single-native, failed on every run until `SelfTest.restoreHome` waited 1.2 s whenever home's
  windows weren't on the current Space.
- **The native switcher's geometry** is in `docs/architecture.md` § How route A+ works. In short:
  - AX icon frames are 128 pt, and the icon image fills them;
  - the visible rounded square is 103 pt;
  - the highlight is the frame inset by 4 pt;
  - the app's name sits just under the frame, which is where the dots were drawn.

  The self-test's `stack-edges` scenario notes the frames.
- **Screenshots from the agent shell work; keys don't.** The shell (the Claude app) has Screen
  Recording but not Accessibility, so every key has to come from BetterTab's self-test. The
  capture method:
  - run with `--pause <s>`;
  - poll the report's `checkpoint` field;
  - `screencapture -x -m` when it changes.

  Opening BetterTab's own menu for a screenshot took a temporary patch that calls `performClick`
  on the status button. The patch wasn't committed.
- **GitHub's only hosted image with Xcode 27 is `xcode-27`** (macOS 27, arm64, a public preview
  since 2026-07-16, with macOS 27 as its base since 2026-09-16).
  - `macos-latest` and `macos-26` only have Xcode 26.
  - The workflow pins `/Applications/Xcode_27.0.app` and fails unless `xcodebuild` reports
    Xcode 27.
  - A public preview can queue, and the label may be renamed at GA
    (`actions/runner-images#14404`).
- **The release script was tested locally in both modes.** It produced
  `CFBundleShortVersionString` 0.1.99 and `CFBundleVersion` 99, the icon (`Assets.car` and
  `AppIcon.icns`), and a signature that verifies. The workflow's keychain import still hasn't run,
  because no secret has reached it.
- **A hand-written `.icon` compiles.** actool turns it into `Assets.car` plus `AppIcon.icns`.
  Icon Composer's command-line `ictool` renders it headless in every appearance; the command is in
  `design/icon/README.md`.

**From the build session (2026-09-29), all on this Mac:**
- **The live run at 22:57** (logs, subsystem `com.luksanss.BetterTab`):
  - the switcher was found in 170–183 ms and all 6 icons matched by name;
  - Chrome's list showed 3 windows, 2 full-screen, with none untitled and none missing an AX
    element, so titles resolve across Spaces;
  - focusing reported make-key `true` and raise `ok`, but `space didn't` switch in 300 ms (see Next
    action 4).
- **Accessibility alone is enough for the key tap.** BetterTab never asks for Input Monitoring, and
  its tap ran and swallowed releases with only Accessibility granted. On macOS 27 that pane is
  titled "Device Control and Data Access".
- **Test 0:** the hold, mouse moves, swallowed letters, the synthetic release finishing a switch, ⌘
  not stuck, and ⌘⇥ again all pass. See `docs/architecture.md` § Test 0 results.
- **The native switcher,** as found through AX: the Dock-owned `AXProcessSwitcherList` is found about
  150–220 ms after ⌘⇥; items are matched to pids by name (the Dock gives no `AXURL`). Its window is
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
  refuses to run then). For long unattended runs, keep the Mac awake with `caffeinate -d -i -u`.
- **macOS 27 may not draw `NSMenuItem.image`,** so the status line draws its own dot. This came from
  an in-process capture the maintainer's typing may have disturbed; the code works either way.

**From the public-repo check (2026-09-29):** there are no secrets anywhere in history, and no
binary files. The Team ID in `project.pbxproj` isn't a secret. The full check is in
`docs/archive/handoffs/2026-09-29-public-repo.md`.

**From the research before the build:**

These come from research on 2026-09-29, reading the source of three apps: AltTab
(`lwouis/alt-tab-macos`, GPL-3.0), DockDoor (`ejbills/DockDoor`, GPL-3.0) and WindowLens
(`FornaxChemica/WindowLens`, MIT). Plus a read-only probe on this machine. No code from these
three is in the repo; where the build borrowed code, it took it from yabai (see Decisions). The
detail and API table are in `docs/architecture.md`.

- **Nobody is known to hold the native switcher open by swallowing the ⌘ release.** Route A+
  rests entirely on that trick, which test 0 has since confirmed on this Mac. DockDoor and
  WindowLens only *read* the switcher and swallow other keys.
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
  need Screen Recording. BetterTab shows titles only.
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

- **The release workflow's keychain import has never run.** No `SIGNING_CERT_P12` has reached it.
- **The first-launch prompt is unconfirmed.** v0.1.49's first launch should have shown it; ask the
  maintainer. Acceptance test 18 covers it.
- **The bolder stack edges have no recorded verdict from the real switcher.** The maintainer saw
  the old ones in both appearances. The new ones were only mocked offscreen, and then run as a
  Debug build for the maintainer. Shrunk icons are unchecked. The geometry is proportional to the
  frame, so it should scale.
- **Unverified on macOS 27:**
  - how long the Space slide takes, and whether steps 4–6 of the focus sequence move the Space
    without `activate`;
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
  to press and release ⌘ once more; experiment test 0g (acceptance test 14) still has to verify
  that.
- **Route A+ never turns off native ⌘⇥.** If anything starts calling
  `CGSSetSymbolicHotKeyEnabled`, route B has been chosen. Record that decision here first.
- **If route B is ever built, never leave native ⌘⇥ turned off.** Turn symbolic hotkeys 1 and 2
  back on when the app quits, when it receives `SIGTERM`, and at the next launch if the previous
  run didn't exit cleanly. The dev loop *will* crash the app. So before the first build that turns
  ⌘⇥ off, commit `scripts/restore-native-cmd-tab.swift`. Its source is in `docs/architecture.md`
  § Recovery.
