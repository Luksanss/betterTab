# Handoff

Updated on 2026-09-30, just before release 4. On the Debug build of `dev` the maintainer said
"the cmd § is working for me" and "Otherwise the betterTab works perfectly", so this handoff
assumes `dev` is merged into `main` straight after it; `/handoff` checks that against git. The
handoff as it stood before, with the story of the ⌘§ session, is archived at
`docs/archive/handoffs/2026-09-30-window-switcher.md`. The one as of release 3 is
`docs/archive/handoffs/2026-09-30.md`.

Release 4 carries, since v0.1.49:
- **The keycap icon labelled A,** for the app and the menu bar.
- **Bolder stack edges,** approved on the real switcher.
- **⌘§, a window switcher for the front app** (see Decisions), which the maintainer has used live.
- **The ⌘⇥ list forgets its titles when it closes:** `WindowList.hide` resets the model and its
  rows (`docs/spec.md` § Privacy).

It's the first 1.0: `MARKETING_VERSION` went from 0.1 to 1.0, so the release is **v1.0.63**. That's
62 commits across `main` and `dev`, up to the one that bumped the version, plus the merge.

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

- **`main`** should be `dev` merged in: release 4. Before the merge it was `d565ede`, release 3.
  The agent merged it with `--no-ff` and pushed `main` and `dev`, on the maintainer's request.
  Check with `git log --oneline -3 main` and the repo's Releases page for v1.0.63.
- **`dev`** is `main`'s second parent, and pushed.
- **The installed app is still v0.1.49** in `/Applications`: ad-hoc, with the old window-glyph
  icon.
- **The Debug build is running** (pid 26995, started 23:41) from `build/DerivedData.noindex`, with
  every code change on `dev`. It's **untrusted**: Accessibility was reset to see the first-launch
  prompt (Findings), and its toggle is still off, so its tap isn't running and ⌘⇥ is native. Quit
  it before starting any other copy: two copies means two key taps.
- **A leftover worktree:** `.claude/worktrees/relaxed-swanson-940c4a` on branch
  `claude/relaxed-swanson-940c4a`, from the task session that made the list fix and this handoff.
  Its branch is at `dev`'s tip. Its Debug and Release builds are registered with Launch Services,
  so run `lsregister -u` on both `.app`s under its `build/DerivedData.noindex/Build/Products/`
  before `git worktree remove` and `git branch -D`.
- **Dev builds** go to `build/DerivedData.noindex`. The `CLAUDE.md` check passes. The only
  `warning:` line is `appintentsmetadataprocessor`'s "Metadata extraction skipped", a tool message
  that isn't from our code.
- **GitHub:** `Luksanss/betterTab` is public, with its history unchanged and no LICENSE.
- **Dev machine:** macOS 27.0.1 (26A434) on Apple Silicon, Xcode 27.0, Swift 6.4. An ISO keyboard
  with ABC and Czech-QWERTY layouts; the built-in 1512 × 982 display, and a 1920 × 1080 one to its
  left (x −1920 in global coordinates).

## Next action

1. **Install release 4, v1.0.63.** Quit the Debug copy, replace `/Applications/BetterTab.app` with
   the release's zip, and open it. It's ad-hoc like v0.1.49, so macOS asks for Accessibility again.
   Then check the menu's version (acceptance test 21), and that the Accessibility row in System
   Settings shows the keycap (Findings).
2. **Get the signing secrets working** (`docs/releasing.md` § Signing with your certificate). Check
   the names with `gh secret list`. The next run's summary says whether it signed. The first signed
   release makes macOS ask for Accessibility once more; after that, updates keep the grant.
3. **Find out what the Space switch in `BetterTab/Focus/Focuser.swift` really does.** Every
   cross-Space pick on 2026-09-30 logged "space didn't switch" after its 300 ms wait and fell back
   to `activate`, yet the maintainer says those picks work, ⌘§'s between two full-screen windows
   included. Measure when the Space actually changes, make the log say what happened, and see
   whether a pick can take less than the ~330 ms before the fallback plus the slide.
4. **Run the self-test** when the Mac is free: `open -g …/Debug/BetterTab.app --args --self-test
   /abs/path/report.json`. It has `windows-flip`, `windows-escape` and `windows-cycle` for ⌘§ (in
   `BetterTab/Debug/SelfTestWindowScenarios.swift`), which have never run. They need the home app
   to have two windows, and three for `windows-cycle`; scratch TextEdit documents work.
5. **The maintainer runs acceptance tests 1–29 by hand** (`docs/spec.md`), especially 4 (flash),
   14 (`kill -9` recovery), 20 (other Spaces) and 22–29 (⌘§). Test 18's first-launch prompt has
   been seen on a Debug build; whether v0.1.49 showed it on its own first launch is unknown.
6. **Still to discuss** (the maintainer said "we will discuss later"):
   - making a quick ⌘⇥ flip-back always native, rather than depending on whether Accessibility
     answered in time;
   - marking list rows whose window is on another Space;
   - ⌘§ on ANSI keyboards, which have no § key (their key above Tab is ⌘`'s);
   - ⌘§'s order across Spaces (Findings).
7. **Optional: add a LICENSE.** The public repo is all rights reserved without one.

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
- **Release 4 is 1.0** (maintainer, 2026-09-30: "this is the first 1.0.0 release"). Only the
  BetterTab target's `MARKETING_VERSION` moved to 1.0; Experiment's stays 0.1. Asked whether the
  last part should restart at 0, the maintainer kept the commit count, so the release is v1.0.63
  and `release.yml` is unchanged.
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
  so the grant should survive rebuilds. On 2026-09-30 it didn't, twice (Findings).
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
  push or open pull requests, unless the maintainer asks for that push, as for release 4.
- **No ticket tracker.**

## Findings worth keeping

**From the release 4 handover (2026-09-30, late):**
- **"space didn't switch" in the focus log doesn't mean the pick failed.** At 23:11 the
  maintainer's two ⌘§ picks between two full-screen windows both logged it and fell back to
  `activate` after about 335 ms, and the maintainer says ⌘§ works. Either the 300 ms wait gives
  its verdict before the Space has moved, or `activate` does more for the front app than assumed.
- **System Settings has one Accessibility row per bundle ID, with the icon of the copy in
  `/Applications`.** Five copies are registered as `com.luksanss.BetterTab`: v0.1.49, and the Debug
  and Release builds in the checkout and in the worktree. The row showed v0.1.49's window glyph
  while the keycap Debug build was the one running. It should change once a keycap release
  replaces v0.1.49; if not, quit and reopen System Settings.
- **Showing the first-launch prompt again takes two resets.** The grant:
  `tccutil reset Accessibility com.luksanss.BetterTab`, which the maintainer runs, since agents
  don't change security settings. It resets every registered copy, the installed release too. And
  the app's flag: `defaults delete com.luksanss.BetterTab promptedForAccessibility`. After both, the
  23:41 launch logged "First launch without Accessibility: showing the system prompt".
- **New Debug builds lost the grant twice; relaunching the same build kept it.** The 22:16 launch
  was untrusted and re-granted at 22:17. The 22:59 rebuild launched untrusted at 23:38 and was
  granted at 23:38:09, and that same build relaunched at 23:39:10 trusted. The Debug build's
  designated requirement names the certificate (`anchor apple generic and certificate
  leaf[subject.CN] = "Apple Development: …"`), which should survive rebuilds; v0.1.49's is a
  `cdhash`. The cause is unknown. The suspect is the one TCC record all five copies share.
- **The agent's shell may not quit or launch BetterTab.** Claude Code's auto-mode check refused
  both `kill -TERM` and `open -g` on the app ("Interfere With Workloads"). Ask the maintainer to run
  them. `kill -TERM` is safe: `TapSignals` stops the tap and posts any owed ⌘ release first.

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
  running only brings that copy forward. Check the process's start time against the binary's
  (`ps -o lstart`, `stat`) to know which build is live.
- **Plain `log` is a zsh builtin** (`too many arguments`). Use `/usr/bin/log show`.
- **Offscreen rendering can't show `NSVisualEffectView`.** It draws flat grey, so the agent's
  renders of `WindowSwitcherView` hid it and painted the design's colours behind.
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

- **Cross-Space focusing always logs a fallback,** although the picks work (Next action 3).
- **New builds lose the Accessibility grant** despite the certificate signing (Findings).
- **Whether ⌘§'s `.hudWindow` material looks right in light mode is unseen.**
- **The release workflow's keychain import has never run.**
- **The first-launch prompt is unconfirmed for a release** (acceptance test 18); it has been seen
  on a Debug build.
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
