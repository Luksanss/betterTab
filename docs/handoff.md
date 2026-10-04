# Handoff

Updated on 2026-10-04, after release 9: the release script stopped shipping `get-task-allow`, and
the stack edges redesign settled on a direction, a window count (below).

The maintainer found that releases carry `com.apple.security.get-task-allow = true`. Since
BetterTab holds Accessibility, any process running as the user could attach a debugger and act with
the grant. `e1dd4b3` makes `scripts/build-release.sh` sign the app again without it, and stop if
any code in the app still has it (Decisions, Findings, `docs/releasing.md` § The app's signature).
It's on `dev`, so release 10 is the first release without it.

Release 9 went through pull request 9 at 11:36 UTC and published v1.0.88, as its handoff
predicted. It merged `e5dd507`, the handoff written for it, so that handoff is archived at
`docs/archive/handoffs/2026-10-04-ansi.md`, as the convention below says. The agent checked the
published release: the app in the disk image is v1.0.88, signed by team `5KDU5HYH35` with a
designated requirement naming the certificate, and passes `codesign --verify --deep --strict`; the
latest-release `appcast.xml` names it, with the notes "Wait for the Space slide before falling back
to activate" and "Open the window switcher with ⌘\` on ANSI keyboards", and its EdDSA signature
matches the `SUPublicEDKey` in that app.

Release 9 carries, since v1.0.81:
- **A ⌘§ pick to another Space no longer logs a false "didn't switch"** or sends an `activate`
  that did nothing: `Focuser` waits up to a second, past macOS's slide (Decisions, Findings).
- **ANSI keyboards get ⌘\`,** with each key press judged by the keyboard it came from (Decisions).

With it, the work list is done except the stack edges redesign, which the maintainer will discuss
later. The rest was settled on 2026-10-04: the acceptance tests count as passed, ⌘§'s order across
Spaces stays, and there's no LICENSE (Decisions). The handoffs of that day tell how:
`docs/archive/handoffs/2026-10-04-grant.md` (release 8's first update through the menu) and
`docs/archive/handoffs/2026-10-04-ansi.md` (the self-test runs, the Space timing and the decisions).

The maintainer then updated to v1.0.88 through Check for Updates… at 13:40 and reported the checks
done: ⌘§ opens the switcher on this Mac's ISO keyboard, and ⌘\` stays macOS's. Acceptance test 22
counts as passed with the rest (Decisions), so the stack edges redesign is the only work left,
besides releasing the `get-task-allow` fix.

**The stack edges redesign started that afternoon.** The maintainer showed the real switcher in a
screenshot: v7's edges are 4 pt dark slivers that read as smudges on macOS 27's clear glass ("kinda
ugly and not really noticable"). Claude Design first brought the prototype up to date as `Window
Switcher v7.dc.html`, which matches v1.0.88, then built three directions in `Window Switcher
v8.dc.html` from the brief in `docs/design-brief-v8.md`: A "Spine", B "Chips" and C "Count", each
with a spec sheet. The maintainer picked A. The agent built it, but on offscreen renders with the
real icons the maintainer dropped it ("nah lets do the count, this is shi"). Spine is in a stash,
not on `dev` (Working copy state); C, "Count", is next, in a fresh session (Next action).

**Convention.** The current handoff lives at this path and is rewritten in place by every
`/handoff-update`. It's archived only **at a release**, when `dev` is merged into `main` because the
maintainer says a version works. At that point it's copied to `docs/archive/handoffs/<ISO date>.md`
in the same commit, with a topical suffix such as `-ci` (not a number) if that date is taken. If the
merge goes through a GitHub pull request, the archive can't be in the merge commit, so the next
`/handoff-update` on `dev` writes it; that's what happened for releases 1, 2, 3, 5, 6, 7, 8 and 9.
This file is then started fresh. Never leave the live handoff under `docs/archive/handoffs/`;
readers are told to treat that directory as historical only.

This document records what is **not** obvious from the code or `git log`: decisions and the
reasoning behind them, findings that were expensive to learn, and the next action. There's no
ticket tracker; the next action below is the backlog.

## Working copy state

- **`main`** is release 9, v1.0.88 (`09d2892`, the merge of pull request 9), published on
  2026-10-04. The local `main` was fast-forwarded to it.
- **`dev`** is five commits ahead of `main`: `3179eef` (the release 9 archive), `6c6d1cf` (a
  handoff), `e1dd4b3` (the `get-task-allow` fix), `e014a18` (its handoff) and this handoff, which
  adds `docs/design-brief-v8.md`. `origin/dev` is at `e014a18` as of the last fetch; this one isn't
  pushed. With nothing else landing, release 10 is v1.0.94: 88 commits on `main`, five on `dev` and
  the merge.
- **The Spine stack edges are in `stash@{0}`** ("Spine stack edges (Claude design v8, direction
  A), dropped 2026-10-04 for Count"), not on `dev`, so release 10 can't ship them. It holds
  `BetterTab/StackEdges/IconColour.swift` (icon colours in Oklab), the rewritten
  `StackEdgesOverlay.swift`, its call sites, the self-test check, and the spec and architecture
  text. Worth taking for Count: `bodyScale = 104.0 / 128` (Findings), the `Icon` struct, the
  static `draw(_:isDark:in:)` an offscreen harness can call, and the shape of the self-test's
  geometry check. `git stash show -p stash@{0}` shows it; drop it once Count lands.
- **The installed app is v1.0.88** in `/Applications`, certificate-signed (team `5KDU5HYH35`),
  updated from v1.0.81 through Check for Updates… at 13:40, with Accessibility granted. It still has
  `get-task-allow`, like every release so far.
- **A local test image:** `build/release/BetterTab-1.0.99.dmg`, ad hoc, from
  `scripts/build-release.sh 1.0.99 99`, with Sparkle in it; the version is a test number. It
  predates the fix, so it has `get-task-allow`. Beside it, an `appcast.xml` and `notes.md` from
  `scripts/make-appcast.sh`, signed with a throwaway key: the agent wrote that key's public half
  into the built app's Info.plist under `build/release-DerivedData.noindex` to test the signature
  check, so that build isn't a real one. `build/dmgbuild` is the venv the script made, on Homebrew's
  Python 3.14.
- **The fix was made in a worktree,** `.claude/worktrees/vigilant-engelbart-9acf5a` (branch
  `claude/vigilant-engelbart-9acf5a`, at the same commit as `dev`). Its `build/` has the fixed
  script's last output: `BetterTab-1.0.99.dmg` signed with the maintainer's certificate. The worktree
  and its branch can be deleted.
- **The Debug build** in `build/DerivedData.noindex` was rebuilt from `dev` after the stash, so it
  draws v7's edges, not Spine. It has Sparkle linked but no Check for Updates….
  The resolved package, and Sparkle's tools (`generate_keys`, `sign_update`), are under its
  `SourcePackages/`; the tools are in `artifacts/sparkle/Sparkle/bin/`.
- **Dev builds** go to `build/DerivedData.noindex`. The `CLAUDE.md` check builds the one scheme,
  BetterTab, and passes. The only `warning:` lines are xcodebuild's "Using the first of multiple
  matching destinations" and, sometimes, `appintentsmetadataprocessor`'s "Metadata extraction
  skipped"; neither is from our code.
- **GitHub:** `Luksanss/betterTab` is public, with its history unchanged and no LICENSE. The
  `release` environment (deployment branch `main` only) holds `SIGNING_CERT_P12`,
  `SIGNING_CERT_PASSWORD` and `SPARKLE_ED_PRIVATE_KEY`, set by the maintainer on 2026-10-04; there
  are no repository secrets. The account has two-factor sign-in.
- **The keys:** the Apple Development certificate is in the maintainer's login keychain, valid
  until 2027-09-29. Sparkle's private key is in the same keychain (`generate_keys -p` prints its
  public half, which matches `SUPublicEDKey`). The exported `.p12` and key file were deleted.
- **Dev machine:** macOS 27.0.1 (26A434) on Apple Silicon, Xcode 27.0, Swift 6.4. An ISO keyboard
  with ABC and Czech-QWERTY layouts; the built-in 1512 × 982 display, and a 1920 × 1080 one to its
  left (x −1920 in global coordinates).

## Next action

1. **Ship the `get-task-allow` fix as release 10, when the maintainer says so** (merge `dev` into
   `main`). It's the first release whose app `codesign` signs directly rather than through Xcode.
   Its notes will say "Keep other programs from attaching a debugger to BetterTab". Then check:
   - the published app: `codesign -d --entitlements :-` prints nothing, its `codesign -d -r-`
     matches v1.0.88's, and the release log lists every piece of code with "entitlements: none",
     except `Autoupdate`'s `com.apple.application-identifier`;
   - an update from v1.0.88 through Check for Updates… keeps the Accessibility grant, with no
     prompt.
2. **Build the stack edges as v8's direction C, "Count", in a fresh session** (Decisions). Read
   `Window Switcher v8.dc.html` through `DesignSync` (`get_file`, project
   `3de20039-32b6-469c-a83f-98c761ed286e`); its "Stack edges" control (or the 4 key) shows C, and
   "Spec sheet" shows the numbers. In shares of `s`, the icon body's side, origin the body's
   top-left, y down:
   - **Capsule:** height 0.26, width max(0.26, digits × 0.099 + 0.14), radius 0.13; left x =
     −0.02, top y = 0.76, growing rightward. The bottom-left corner, where Finder puts its alias
     arrow.
   - **Numeral:** the exact window count, 2 and up with no ceiling, in SF Pro Rounded Semibold at
     0.165, tabular figures, optically centred 0.005 down.
   - **Fill / text:** #FFFFFF / #1D1D1F in light, #3A3A3C / #F5F5F7 in dark.
   - **Rim, 0.005 wide:** #000 at 10% in light, #FFF at 14% in dark.
   - **Shadow:** y 0.01, blur σ 0.015, #000 at 22% in light, 50% in dark.

   The design took `s` as 103 pt; it's 104 (Findings). Then update `docs/spec.md` § ⌘⇥: stack
   edges and acceptance test 2, `docs/architecture.md`'s geometry paragraph and component row, the
   self-test's `stackEdgeProblems` (a capsule at the bottom left, not edges above),
   `StackEdgesOverlay.maxEdges` (a count has no ceiling) and the header of
   `docs/design-brief-v8.md`. Render it offscreen with real icons before the maintainer tries it
   (Findings), and put nothing on screen without asking.

## Decisions already settled

- **The stack edges become a window count, v8's direction C** (maintainer, 2026-10-04). v7's
  edges were "kinda ugly and not really noticable" on the real switcher. Of v8's three directions
  the maintainer first chose A, "Spine": the other windows as cards slid out to the icon's left,
  in the icon's colour, with C as the fallback ("lets first do the spine, if that fails we will do
  count"). Spine was built and rendered offscreen with the real icons, then dropped: "nah lets do
  the count, this is shi". B, "Chips" (a row of window frames above the icon), wasn't taken up.
  Claude Design had recommended A, then B, and warned that C puts a second badge on an app that
  has a notification badge, such as Discord.
- **Releases are signed again without `get-task-allow`** (maintainer, 2026-10-04: "re-sign the app
  inside-out with its own entitlements minus get-task-allow, using hardened runtime and no --deep.
  Keep Sparkle's nested components signed as they need to be"). The maintainer ruled out
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`, which drops the other derived entitlements too, and
  pointed to quickUschovna's `scripts/build-release.sh`, which reads each part's entitlements back,
  deletes `get-task-allow` and signs again.
  - **Only the app is signed again; Sparkle stays as Xcode leaves it** (agent's call). That's
    `Sparkle.framework` signed with our identity and its helpers with Sparkle's ad hoc signatures,
    as in every release, and two updates through the menu (releases 8 and 9) worked that way. None
    of them has `get-task-allow`. Signing the helpers with our identity would change what replaces
    the app during an update, and only a real update could test that.
  - **Xcode still signs first, with the identity,** unlike quickUschovna, which builds ad hoc and
    signs everything itself. The hardened runtime's library validation needs `Sparkle.framework` to
    carry our team, and Xcode already does that.
  - **The script stops** if any Mach-O in the app still has `get-task-allow`, or, with an identity,
    if signing again changed the designated requirement, which would cost every user the grant
    (agent's call).
  - The commit is a `fix:`, so release 10's notes show it to users.
- **The acceptance tests count as passed** (maintainer, 2026-10-04: "Consider the tests as
  passed"), for tests 1–21, and 22 after release 9 ("consider done"). The agent ran or measured
  1, 2, 5, 6, 8 (Esc), 15 and 18, and the maintainer ran the update in 20; the rest have no
  recorded run.
- **ANSI keyboards get ⌘\`, only from an ANSI keyboard** (maintainer, 2026-10-04: "If the support
  for the other keyboards is just adding a few more symbols that are supported, I suppose we
  should", and "the pair of command and key for that keyboard should be only local to that
  keyboard"). So the key above Tab works on each keyboard, and the other keyboard's key doesn't.
  - `KeyAboveTab` judges each key event by the keyboard it came from
    (`keyboardEventKeyboardType`), so with an ISO and an ANSI keyboard both plugged in, ` on the
    ISO one still passes to macOS.
  - On an ANSI keyboard, BetterTab takes ⌘\` from macOS's "Move focus to next window" while it
    runs (agent's note; it does the same job, with the switcher). Nothing is turned off: quit
    BetterTab and ⌘\` is macOS's again.
  - JIS keyboards, and types macOS reports no layout for, only get §.
- **⌘§'s order across Spaces stays** (maintainer, 2026-10-04: "order across spaces it's okay keep
  it"): the current Space's windows first, as SkyLight gives them (Findings).
- **No LICENSE** (maintainer, 2026-10-04: "keep it as it is the default license like you say is
  all rights reserved").
- **The stack edges stay, and get a redesign** (maintainer, 2026-10-04: "No, keep the stack edges,
  but the stack edges look a bit funky right now, so they will need to be redesigned"), when asked
  whether "only ⌘§" meant they go too. So "only ⌘§" was about the docs, which are done.
- **A Space switch counts as stuck after a second, not 300 ms** (agent's call, 2026-10-04, from the
  measurements in Findings). The slide takes 370–410 ms, and a second leaves room for a busier
  Mac. Only `activate` waits longer, and only for a switch that really is stuck; a pick queued
  behind another waits for the slide, about 100 ms longer than before.
- **Updates are in scope, but only on request** (maintainer, 2026-10-04; quotes above). Asked
  how, the maintainer chose:
  - **checking only when asked:** Check for Updates… in the menu, with no daily check, so
    BetterTab never goes online by itself (spec principle 5);
  - **asking before installing:** a window with the version and release notes, then download,
    check, replace and relaunch.
  - **Sparkle** (maintainer: "let's build it with sparkle"), after the agent recommended it: its
    code downloads, checks and replaces an app that holds Accessibility, and is better borrowed than
    written. So the window's buttons are Sparkle's: Install Update, Remind Me Later and Skip This
    Version, then Install and Relaunch.
  - Agent's calls, not discussed: Debug builds don't have the item, so a dev build never replaces
    itself with a release; `SUVerifyUpdateBeforeExtraction` makes the EdDSA signature mandatory
    (Sparkle's default accepts either it or a matching code signature); the workflow refuses to
    release without the certificate or Sparkle's key; the release notes are the `feat`, `fix` and
    `perf` commits since the last release, for the GitHub release too, instead of GitHub's
    generated list of pull requests titled "Dev"; the appcast isn't signed (HTTPS from GitHub,
    `docs/architecture.md` § Updates).
  - Privacy still holds. The spec says what GitHub sees (the IP address and `User-Agent:
    BetterTab/<version> Sparkle/<version>`) and what Sparkle saves (`SUHasLaunchedBefore`,
    `SULastCheckTime`, a skipped version).
  - It overturns "no automatic updates, because the app has no network code", from the releases
    decision below.
- **Releases are signed with the maintainer's certificate, and the key is guarded** (2026-10-04).
  The agent explained where the certificate comes from, how the designated requirement keeps the
  grant, and how to store the key. The maintainer did each step: two-factor sign-in, the `release`
  environment limited to `main`, the secrets set by piping into `gh secret set --env release`, and
  the exported files deleted. The agent pinned the workflow's actions by commit, because the key
  sits unlocked in the job's keychain while they run. Agents never handle the private keys; the
  maintainer exports and uploads them.
- **Releases ship as a disk image, in English, with no zip** (maintainer, 2026-10-04). Shown
  another app's installer window, the maintainer asked "what do we need so our installation is
  like this too?", then "use english and ship dmg only, generate something cool as a background
  for that installer and some cool but short message instead of generic "drag bettertab to
  apps"", and last, of a caption under the icons, "remove this text, the rest is good, commit PR
  and merge to main". The look was approved from an offscreen preview.
  - The background is drawn in code by `design/dmg/make-background.swift`, like the icon: a cool
    white with an indigo glow, "Drag. Drop." with ⌘ and § as the icon's keycaps, a dotted hop from
    the app to Applications, the window-picking letters A S D F J K drifting at the edges as
    keycaps, and a dot grid fading in at the corners.
  - The caption under the icons, "Then hold ⌘ and press the key above Tab.", was removed at the
    maintainer's request.
  - **dmgbuild, not create-dmg** (agent's call). dmgbuild writes the window's `.DS_Store` itself;
    create-dmg drives Finder through AppleScript, which needs a logged-in desktop and is known to
    time out on CI. Both are MIT. It's pinned by hash because it runs while the signing keychain is
    unlocked.
  - The image itself isn't signed. With an Apple Development certificate that changes nothing for
    Gatekeeper, so users still click Open Anyway.
- **⌘⇥ is native; the window list is gone** (maintainer, 2026-10-01: "cmd + tab seems to add to
  much mental strain in thinking of what window to choose. Keeping defautl switcher and then if the
  wrong window is triggered the cmd + § works super well", then "keep the stac edges, remove the
  cmd + tab. Keep the cmd + §").
  - The agent agreed when asked: native ⌘⇥ and then ⌘§ reach every window the list did. The cost
    is a second Space slide when the window you want is on a different Space from the app's front
    one.
  - The stack edges stay, because they say which apps ⌘§ has something to do for.
  - Removed rather than hidden behind a setting. v1.0.63 and git history keep it. The spec records
    it under § Out of scope, and `docs/architecture.md` § Route A+, removed says how it worked.
  - It overturns "pick the window after releasing ⌘" and route A+.
  - What went: `BetterTab/WindowList/`, `Tap/SyntheticKeys.swift`, `Tap/TapSignals.swift`, the
    Picking phase and 15 s timeout in `TapMachine`, `WindowIndex.watch`, `WindowOrder`'s main
    window first, the `Experiment` target, the self-test's list scenarios and `--long`, and the
    list previews.
  - What moved: `OverlayPanel` to `BetterTab/App/`; `MinimizedGlyphView` and `roundedMask` to
    `WindowSwitcherView.swift`; `displayTitle` to `WindowSwitcherModel`.
- **⌘§: a window switcher for the front app** (maintainer, 2026-09-30).
  - The problem, in the maintainer's words: on Chrome, ⌘⇥ highlights the next app, so reaching the
    other Chrome window meant cycling through every app and back, then pressing S. The agent first
    pointed out ⌘⇥ ⇧⇥ (back onto Chrome), and then ⌘`; the maintainer proposed ⌘ plus the key above
    Tab instead.
  - "The behavior should be 1:1 with the cmd + tab", for that app's windows: hold ⌘, § steps, ⇧§
    steps back, release opens, and a quick tap flips. The agent added, and the maintainer didn't
    object: letters open a window at once, the mouse works, Esc cancels, there are at most 9 tiles,
    and an app with one window does nothing.
  - It's now the only shortcut (spec principle 3).
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
  2026-09-30). What ships until Count replaces it. Opacity `[0.85, 0.55]` dark and `[0.62, 0.40]`
  light (front, back); `rise` 0.041 of the body's side, `narrowing` 0.10. Variant C (`rise` 0.052,
  poking above the highlight) wasn't needed.
- **Stack edges replace the window-count dots** (maintainer, 2026-09-29). The dots were too close
  to the Dock's "running" dots. The top-centred stack beat the diagonal one, which looked like a
  Copy icon. One edge for two windows, two for three or more.
- **Releases: the free route, automatic on every push to `main`** (maintainer, 2026-09-29). There's
  no Developer ID and no notarization; users click Open Anyway once. Updates were by hand until
  2026-10-04, when the updater came into scope (above). The version is `MARKETING_VERSION` plus the
  commit count, so `1.0.68` means 68 commits.
- **Release 4 was 1.0** (maintainer, 2026-09-30: "this is the first 1.0.0 release"). Only the
  BetterTab target's `MARKETING_VERSION` moved to 1.0. Asked whether the last part should restart
  at 0, the maintainer kept the commit count, so release 4 was v1.0.63.
- **The first launch without Accessibility shows the system prompt once,** and **the menu shows the
  version** (maintainer, 2026-09-29). The flag is `promptedForAccessibility` in `UserDefaults`.
- **Grant Accessibility… only opens System Settings** (maintainer, 2026-10-04, after installing
  v1.0.77: the click showed the system's "would like to control this Mac" dialog and opened
  Settings too; "lets keep only the launch of the system preferences"). The first-launch prompt
  stays. If BetterTab's row is ever missing from the list, the + button adds it.
- **The app icon is a home-row keycap labelled A** (maintainer, 2026-09-30). It's an Icon Composer
  `.icon` generated by `design/icon/make-icon.swift`; don't edit `BetterTab/AppIcon.icon` by hand.
- **Native ⌘⇥ is never turned off.** Route B (`CGSSetSymbolicHotKeyEnabled` and a switcher of our
  own) was never built, and nothing calls it.
- **A plain Xcode project with synchronized folders** (maintainer, 2026-09-29). Its throwaway
  `Experiment` target was removed on 2026-10-01; the `.pbxproj` was edited by hand for that.
- **Windows on every Space, full-screen ones included, are in scope** (agent's call, 2026-09-29,
  after the first live run found nothing: the maintainer keeps Chrome and Claude full-screen).
  Accessibility stays the only permission. Background native tabs still don't count.
- **Sign with the maintainer's Apple Development certificate** (maintainer, 2026-09-29), not ad hoc,
  so the grant should survive rebuilds. On 2026-09-30 it didn't, twice (Findings).
- **Focusing follows yabai (MIT, notice kept), not AltTab.**
- **Letters, not numbers:** A S D F G H J K L, by physical key, labelled by the layout.
- **DockDoor isn't an option, and being minimal is the point** (maintainer, 2026-09-29). Treat
  every feature beyond `docs/spec.md` as needing a reason. "DockDoor has it" is not a reason.
- **One working branch** (maintainer, 2026-09-29). Commit straight to `dev`; `main` moves only when
  the maintainer says a version works, and every push to `main` publishes a release. Agents never
  push or open pull requests, unless the maintainer asks for that push, as for release 4. When the
  maintainer asked for release 6, auto mode refused it (Findings).
- **No ticket tracker.**

## Findings worth keeping

**From the stack edges redesign (2026-10-04, after release 9):**
- **The real switcher's glass is nearly clear on macOS 27:** text behind it shows through (the
  maintainer's screenshot). v7's frosted mock flattered thin grey marks; v8's mock copies the
  screenshot.
- **Switcher icons have a 104 pt body, not 103.** NSWorkspace icons drawn at 128 and 256 px put
  the body at 12.0–116.0 pt of the 128 pt frame, for all eleven apps tried; only the 1024 px
  rendition matches 824/1024. That explains the highlight's top sitting 8 pt above the body, not
  8.5 (stack edges session, 2026-09-30). `StackEdgesOverlay.bodyScale` on `dev` is still
  824/1024; the stash has 104/128.
- **Reading icon colours, if a design ever needs them:** the first `NSRunningApplication.icon` read
  is slow when cold, up to 56 ms (GitHub Desktop) and 127 ms for ten apps, so read ahead at launch.
  A mean of the icon's left column made Calendar's cards pink from its red header; a per-channel
  median in Oklab gave its white. Count needs no icon colours.
- **Rendering the overlay offscreen with real icons:** compile `StackEdges/StackEdgesOverlay.swift`
  and `App/OverlayPanel.swift` (without `-D DEBUG`) with a `main.swift`, using `xcrun swiftc
  -swift-version 6 -default-isolation MainActor -enable-upcoming-feature InferIsolatedConformances
  -enable-upcoming-feature NonisolatedNonsendingByDefault -framework AppKit`. Draw a stand-in
  switcher and the overlay into a CGContext bitmap at 2×, so icons use their 256 px rendition, and
  write PNGs. No window and no `open`. It needs the drawing as a static function, as in the stash;
  on `dev` it's inside a private view.
- **Clipping to a path and then filling the same path antialiases its edge twice,** so the edge
  sits about 0.1 pt in. Fill the path, and clip only what has to stay inside it.
- **v8 has a spec sheet per direction** (its "Spec sheet" control), read through `DesignSync` like
  v6. Those numbers are what to build.

**From the `get-task-allow` fix (2026-10-04, after release 9):**
- **xcodebuild adds `get-task-allow` to Release builds** signed with an Apple Development identity
  or ad hoc. The maintainer found it in v1.0.77 and both local Release builds; the agent saw it in
  the installed v1.0.88. Sparkle's framework and helpers never had it.
- **Signing again kept the designated requirement.** Built locally with the maintainer's identity
  (`scripts/build-release.sh 1.0.99 99 <identity>`), the app's `codesign -d -r-` matched Xcode's
  signature from the same build and the installed v1.0.88's. codesign used the login keychain's
  key without a prompt, the same way xcodebuild's Debug builds do.
- **Without entitlements, `codesign -d --entitlements :-` prints nothing,** and the code directory
  has 3 special slots instead of 7 (`hashes=44+3`). Sparkle's helpers print an empty `<dict>`.
- **The ad hoc run passed every check:** no `get-task-allow` in the app, the framework, `Autoupdate`,
  `Updater.app` or either XPC service, in the build or in the app inside the disk image, and
  `codesign --verify --strict --deep` passed on both.
- **Testing `scripts/make-appcast.sh` without the real Sparkle key:** a throwaway Ed25519 seed from
  CryptoKit (`Curve25519.Signing.PrivateKey().rawRepresentation`, base64) works as `sign_update
  --ed-key-file -`. With the real `SUPublicEDKey` the check failed, as it should. With the throwaway
  public half written into the built Info.plist it passed. Copying the original Info.plist back
  made the app's seal valid again. The key was deleted.
- **`file -b --mime-type` prints one line per architecture** for Sparkle's universal binaries, so
  the script matches a prefix.
- **`dev` is checked out in the main checkout, so a worktree can't switch to it.** The agent reset
  the worktree's branch to `dev`, committed there, and fast-forwarded `dev` with `git -C
  <main checkout> merge --ff-only`.

**From release 9 (2026-10-04):**
- **The release and its checks passed on the first run** (Actions run `37199297706`, 2 min 26 s),
  and the version count held: 81 commits on `main`, six on `dev` and the merge made v1.0.88.

**From ANSI support (2026-10-04, after release 8):**
- **`KBGetLayoutType` is "Not thread safe"** (`HIToolbox/Keyboards.h`), so the key tap can't call
  it. Over keyboard types 0–255 it returns 69 ANSI, 67 ISO, 66 JIS and 54 `'????'`, 0 among them,
  so an unknown keyboard never takes ⌘\`. `KeyAboveTab` builds its table on main when `KeyTap`
  is made.
- **This Mac's built-in keyboard is type 92, ISO** (`LMGetKbdType`). Events from
  `CGEventSource(stateID: .hidSystemState)` carry the same type, so the self-test's synthetic §
  still counts.

**From the self-test and the Space switch (2026-10-04, after release 8):**
- **Six self-test runs, all passing.** At 13:16, with TextEdit ×3 as home, Claude as the
  multi-window app and Messages as the single: all 8 scenarios in 7 s. Then five runs with Chrome
  as home, whose two windows (SkyLight's count) are on full-screen Spaces: 7 pass each, and
  `windows-cycle` is skipped for having fewer than three windows.
- **The make-key record and the raise switch Space; `activate` never did.** Five ⌘§ picks between
  Chrome's full-screen windows came on screen 373–407 ms after the raise: 379 and 384 ms with the
  fallback skipped (a Debug-only switch, removed after the test), and 373, 397 and 407 ms with
  `activate` sent at about 310 ms. SkyLight changes a display's current Space when the slide ends,
  not when it starts. With the one-second wait, run 6 logged "space switched" at about 375 ms.
- **A pick can't get much faster.** Front, make-key and raise take 10–35 ms; the rest is macOS's
  slide.
- **Idle (acceptance test 18) passes.** Over 60 s, v1.0.81 used 0.00 s of CPU (`ps -o time`) and
  14 MB, with no idle wakeups (`top -stats idlew`) and no sockets in 30 `lsof -i` samples.
- **Fresh Debug builds kept the grant.** Both rebuilt Debug builds came up "Active" for the
  self-test, which stops otherwise, with the certificate-signed release installed.
- **With the maintainer's go-ahead in chat, auto mode let the agent `kill -TERM` the installed
  BetterTab and `open -g` both builds,** unlike on 2026-09-30.
- **Chrome as home:** `open -a "Google Chrome"`, wait two seconds, then `open -g` the Debug app.

**From release 8 (2026-10-04):**
- **An update through the menu keeps the Accessibility grant.** v1.0.77 and v1.0.81 are both signed
  by team `5KDU5HYH35` with the same designated requirement, and the maintainer saw no permission
  prompt and no Open Anyway. That bears out the finding below that ad hoc signing, not the way the
  app was installed, is what lost the grant.
- **Telling, without the screen, that an update went through Sparkle:** `defaults read
  com.luksanss.BetterTab` shows `SULastCheckTime` and `NSWindow Frame SUUpdateAlert2` (the update
  window was open), and the bundle's `stat` time sits a second before the process's
  `ps -o lstart`.
- **The version count held** when nothing landed after the handoff: 77 commits on `main`, three on
  `dev` and the merge made v1.0.81, as predicted.

**From release 7 (2026-10-04):**
- **The certificate import and the Sparkle step worked on their first run** (Actions run
  `37195707044`, 2 min 15 s).
- **The version is counted at the merge,** so a commit made after the maintainer merges lands in
  the next release: release 7 was v1.0.77, not the v1.0.78 its handoff predicted.
- **Checking a published release without touching the screen:** `curl -sSL` the latest-release
  `appcast.xml` and the disk image it names, `hdiutil attach -readonly -nobrowse -noautoopen
  -mountpoint <scratch dir>`, then `codesign -d -r-` the app and run
  `scripts/check-update-signature.swift` with the image, the appcast's signature and the app's
  Info.plist.
- **`log show` doesn't keep BetterTab's `logger.info` lines,** with or without `--info`; info
  messages live in memory only. Use `log stream --info` while it happens, or log at `.notice`.

**From building the updater on Sparkle 2.10.0 (2026-10-04), read in its source:**
- **Sparkle accepts an update that passes either check by default,** the EdDSA signature or a code
  signature matching the running app, so either key can be rotated (`SUUpdateValidator.m`). With
  `SUVerifyUpdateBeforeExtraction` the EdDSA check comes before unpacking and can't be skipped;
  the only fallback is a Developer ID-signed archive. After unpacking, the new app's code signature
  only has to be valid, not to match, so an ad hoc release would install and lose the grant.
- **Skipped versions only filter background checks** (`SUAppcastDriver.m`), so Skip This Version
  does nothing for BetterTab.
- **Sparkle's defaults:** `SUHasLaunchedBefore` when its update cycle starts, `SULastCheckTime` per
  check, skipped versions; `SUUpdateGroupIdentifier` only for phased rollouts. Setting
  `SUEnableAutomaticChecks` in Info.plist stops it from ever asking about automatic checks.
- **Its requests carry `User-Agent: <name>/<version> Sparkle/<version>`** and nothing else of ours
  (`SPUUserAgent+Private.m`, `SPUDownloadDriver.m`).
- **Markdown release notes** (`<description sparkle:format="markdown">`) are drawn by an
  `NSTextView`, without WebKit. Sparkle activates the app for checks the user starts, so its window
  comes forward from a menu-bar app.
- **`sign_update --ed-key-file -` reads the key from stdin;** `generate_keys -x <file>` refuses a
  path that exists, so it can't write to `/dev/stdout`. Without `--ed-key-file`, `sign_update`
  uses the login keychain.
- **Xcode re-signs the embedded `Sparkle.framework` with our team** on a plain `xcodebuild build`,
  but its `Autoupdate` and `Updater.app` keep Sparkle's ad hoc signatures;
  `codesign --verify --deep --strict` passes.
- **Release tags sit on `main`'s merge commits, which `dev` can't reach,** so `git describe` on
  `dev` finds no tag. On CI, `HEAD` is the new merge on `main`, whose first parent carries the
  last tag.
- **`gh release create` with files** makes a draft, uploads them, and then publishes (its
  `--help`), so the latest release never lacks its appcast.

**From bringing updates into scope (2026-10-04):**
- **Ad hoc signing is why every install asks for Accessibility again,** not the way it's
  installed. The installed v1.0.71 says `Signature=adhoc` (`codesign -dv`), and an ad hoc app's
  designated requirement is its cdhash, which every build changes. An updater alone doesn't fix it;
  signing does.
- **The Debug build's designated requirement names the certificate** (`identifier
  "com.luksanss.BetterTab" and anchor apple generic and certificate leaf[subject.CN] = "Apple
  Development: … (M44FR7B6NJ)" and certificate 1[field.1.2.840.113635.100.6.2.1]`), and the
  installed v1.0.71's is `cdhash H"2198310d…"`. A guess, not tested: the one Accessibility record
  per bundle ID holds whichever copy's requirement was granted last, so the ad hoc release and the
  Debug builds took the grant from each other. Signed releases share the Debug builds' requirement.
- **Repository secrets reach a workflow pushed to any branch;** environment secrets reach only the
  branches the environment allows, and only jobs that name it. `gh secret set --env` needs the
  environment to exist first.
- **A pull request merged on GitHub doesn't move the local `origin/main`.** Without a fetch,
  `gh pr list --state all` and `gh release list` show what landed.
- **Release 6's workflow ran its Python and disk image steps on CI for the first time,** and
  published v1.0.71.

**From the disk image (2026-10-04):**
- **Finder's window bounds include its 32 pt title bar, and icon positions are centres.** Measured
  on the installer the maintainer showed (Vorssaint 3.4.0, in `~/Downloads`): bounds 600 × 400, a
  1200 × 800 background at 144 dpi of which 368 pt show, icons at (150, 200) and (450, 200). So
  ours is 640 × 400 with 32 pt of bleed at the bottom (`docs/releasing.md` § The disk image).
- **Mounting an image without touching the screen:** `hdiutil attach -readonly -nobrowse
  -noautoopen -mountpoint <scratch dir>`, then `hdiutil detach`. No Finder window opens. The
  `ds_store` package opens files for writing, so copy a read-only mount's `.DS_Store` out first.
- **dmgbuild's `hide_extensions` breaks the signature check:** it sets a Finder flag on the bundle,
  and `codesign --verify --strict` answers "resource fork, Finder information, or similar detritus
  not allowed". It isn't used; Finder hides `.app` anyway.
- **`/usr/bin/python3` is 3.9.6 on macOS 27,** below dmgbuild's 3.10; Homebrew's is 3.14. The
  release script checks the version, and the workflow sets up 3.13.
- **macOS 27 deprecates `hdiutil create`, `attach` and `convert`** in favour of `diskutil image`.
  dmgbuild 1.6.7 still calls them; the warnings don't fail the build.
- **Previewing the installer offscreen:** in a scratch Swift script, draw
  `design/dmg/background@2x.png`, then `design/icon/AppIcon.png` and
  `NSWorkspace.shared.icon(forFile: "/Applications")` at 128 pt on the icon centres, with 13 pt
  names below, cropped to the top 368 pt. The maintainer approved the design from that; the script
  wasn't kept.
- **Auto mode refused `git push origin dev` with `gh pr create`** ("External System Writes"), though
  the maintainer had asked for "commit PR and merge to main", and then refused a plain
  `git status` straight after. The maintainer runs the push, the pull request and the merge, or
  adds a permission rule for them.

**From the removal of the ⌘⇥ list (2026-10-01):**
- **⌘§'s order didn't change.** It already took the window server's order with minimized windows
  last; only the list moved AX's main window to the front. So `WindowOrder` went without touching
  ⌘§, and `WindowIndex.load(withFrames:)` now only says whether to read frames.
- **The tap passes every flagsChanged event, in every phase.** Only keyDowns during Windows, and
  their keyUps, are swallowed. Nothing BetterTab does can leave ⌘ stuck, so `TapSignals` and the
  synthetic events had no job left.
- **On ⌘⇥ the tap now records ⌘ as down,** as ⌘§ already did. Before, a stale `commandDown` (say,
  after the tap restarted with ⌘ held) let the release pass unnoticed, and Cycling ended only at
  the next key or ⌘ press.
- **The Experiment target came out of the `.pbxproj` by hand,** nine objects by id. `plutil -lint`
  passes and `xcodebuild -list` shows one target and one scheme.

**From the release 4 handover (2026-09-30, late):**
- **"space didn't switch" in the focus log doesn't mean the pick failed.** At 23:11 the
  maintainer's two ⌘§ picks between two full-screen windows both logged it and fell back to
  `activate` after about 335 ms, and the maintainer says ⌘§ works. Either the 300 ms wait gives
  its verdict before the Space has moved, or `activate` does more for the front app than assumed.
  It was the first (measured on 2026-10-04, above).
- **System Settings has one Accessibility row per bundle ID, with the icon of the copy in
  `/Applications`.** Several copies are registered as `com.luksanss.BetterTab`: the release in
  `/Applications`, and the Debug and Release builds in the checkout and in the worktree. With a
  release installed, the row should show the keycap; if not, quit and reopen System Settings.
- **Showing the first-launch prompt again takes two resets.** The grant:
  `tccutil reset Accessibility com.luksanss.BetterTab`, which the maintainer runs, since agents
  don't change security settings. It resets every registered copy, the installed release too. And
  the app's flag: `defaults delete com.luksanss.BetterTab promptedForAccessibility`.
- **New Debug builds lost the grant twice; relaunching the same build kept it.** The Debug build's
  designated requirement names the certificate (`anchor apple generic and certificate
  leaf[subject.CN] = "Apple Development: …"`), which should survive rebuilds. The cause is unknown.
  The suspect is the one TCC record all the copies share. On 2026-10-04, with a certificate-signed
  release installed, two fresh Debug builds kept it.
- **The agent's shell may not quit or launch BetterTab.** Claude Code's auto-mode check refused
  both `kill -TERM` and `open -g` on the app ("Interfere With Workloads"). Ask the maintainer to run
  them. With `TapSignals` gone, `kill -TERM` simply ends the process; nothing is owed.

**From the ⌘§ session (2026-09-30, evening):**
- **SkyLight gives window frames with no permission.** `SLSGetWindowBounds(cid, wid, &rect)`
  answers for every window, including full-screen ones on other Spaces and windows on the second
  display at negative x, in global top-left coordinates. It's one round trip per window, so
  `SkyLightWindows.snapshot(framesOf:)` reads frames only for the app ⌘§ asks about; ⌘⇥'s snapshot
  stays at about 1 ms.
- **⌘§'s order is close to most recently used,** but a window on another Space always comes after
  the current Space's windows. That's SkyLight's order, which puts the window you're in first.
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
- **A review found no serious bugs** in ⌘§'s tap phase or its controller. Its smaller findings are
  fixed: the resting pointer; keys before the windows arrive are replayed; any ⌘-up ends Windows;
  the highlight follows its window when one drops out; a letter racing the ⌘ release still opens
  its window; frames only for ⌘§; the view forgets titles on hide.

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
- **The release script was tested locally in both modes** when it made a zip; its disk image only
  ad hoc (2026-10-04), until the `get-task-allow` fix ran it with the certificate too. The
  workflow's keychain import first ran for release 7, and worked.

**From the 2026-09-30 build session, all on this Mac:**
- **The self-test needs a multi-window home app,** or it skips almost everything. Safe targets:
  scratch TextEdit documents, and Finder windows on empty folders. Open them with `open`, bring
  home to the front, then launch the test with `open -g`.
- **Coming back from a full-screen Space, the Dock shows no switcher until the slide ends,** so
  `SelfTest.restoreHome` waits 1.2 s whenever home's windows aren't on the current Space.
- **The native switcher's geometry and window** are in `docs/architecture.md` § How it fits
  together. Any click closes it, even one on BetterTab's own panel.
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
WindowLens is MIT. The native ⌘⇥ switcher can't be modified but can be read through AX. Replacing
it means turning native ⌘⇥ off with `CGSSetSymbolicHotKeyEnabled`, which outlasts the process.
Public APIs can't reliably focus one window. The API table is in `docs/architecture.md`.

## Known gaps

- **The `get-task-allow` fix hasn't run on CI or through an update.** It was checked locally, ad
  hoc and with the maintainer's certificate (Findings). Installed copies up to v1.0.88 keep
  `get-task-allow` until they update.
- **Accepted as passed without a recorded run** (Decisions): "You're up to date!", a check with
  Wi-Fi off, and a day of test 21; the first-launch prompt on a release (test 17); whether another
  window flashes before the picked one (test 11); ⌘§'s `.hudWindow` material in light mode; ⌘\` on
  a real ANSI keyboard (test 22).
- **`windows-cycle` hasn't run across Spaces:** Chrome had two windows.
- **Unverified on macOS 27:** whether a lone make-key mouse down leaves an app thinking the button
  is held, and tag bit 60 for minimized windows.
- **Nobody but the maintainer has installed it yet.**
- **The build check is manual.** The only workflow is the release.

## Safety constraints

Nothing is deployed anywhere except the GitHub releases: zips up to v1.0.68, disk images after,
with an appcast from release 7. Most of the risk is to the maintainer's own Mac: the app under
development changes system state on the machine it runs on. From release 7, the release keys also
decide what every installed copy accepts as an update.

- **Never swallow ⌘.** The tap passes every flagsChanged event in every phase. ⌘§ swallows only
  the keyDowns pressed while ⌘ is held, and their keyUps. If a change ever swallowed a ⌘ release,
  every way out would have to post a synthetic one, as route A+ did (v1.0.63's
  `TapMachine.planEnd` and `SyntheticKeys`), and `kill -9` recovery would need testing again.
- **Never turn off native ⌘⇥.** `CGSSetSymbolicHotKeyEnabled` outlasts the process, so a crashed
  build would leave the Mac with no ⌘⇥. If it's ever needed, record the decision here first, and
  commit a script that turns symbolic hotkeys 1 and 2 back on before the first build that calls it
  (the draft is in `docs/architecture.md` § Recovery as of v1.0.63).
- **Keep Sparkle's guards on, and the keys where they are.** `SUVerifyUpdateBeforeExtraction`
  stays on, the workflow keeps refusing to release without both keys, and the keys stay in the
  `release` environment and the maintainer's keychain. Whoever holds Sparkle's key or the
  certificate can ship an app that inherits Accessibility (`docs/architecture.md` § Updates).
- **Keep `get-task-allow` out of releases.** `scripts/build-release.sh` signs the app again without
  it and stops if any code in the app still has it. Don't drop that step or add `--deep` to it
  (`docs/releasing.md` § The app's signature).
