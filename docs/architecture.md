# BetterTab: architecture

BetterTab draws the stack edges over the native ⌘⇥ switcher and runs ⌘§, its own switcher for the
front app's windows. Until 2026-10-01 it also held the native switcher open for a window list
(route A+, § Route A+, removed). Its only network code is the update check (§ Updates). Research
was done on 2026-09-29. Anything marked **(verified)** was either read in the source of an app that
ships the technique, or probed read-only on the dev machine (macOS 27.0, Xcode 27.0, Swift 6.4, arm64). The three apps are:

- [AltTab](https://github.com/lwouis/alt-tab-macos), GPL-3.0;
- [DockDoor](https://github.com/ejbills/DockDoor), GPL-3.0;
- [WindowLens](https://github.com/FornaxChemica/WindowLens), MIT.

File paths below are inside those repos.

**Licences.** AltTab and DockDoor are GPL-3.0: read them to learn how things are done, because
copying their code would make this project GPL. WindowLens is MIT, so its code can be reused as
long as its copyright notice is kept.

## How it fits together

```
⌘⇥ ─► Dock (native switcher) ─► AXProcessSwitcherList ─► SwitcherWatcher: icons, pids, frames
 │                                                                 │
 └─► KeyTap (session event tap) ─► SwitchController ◄──────────────┘
       ⌘⇥ and its end: passed          │  Cycling: StackEdgesOverlay draws stack edges over native icons
       ⌘§ and keys while ⌘ is held     ▼
                               WindowSwitchController ─► WindowSwitcher panel ─► pick ─► Focuser
```

| Component | Job |
|---|---|
| `SwitcherWatcher` | On ⌘⇥, find the Dock's `AXProcessSwitcherList`. Read each child's frame and match it to an app. Report changes, and when the list is destroyed. |
| `WindowIndex` | Read apps' real windows on every Space: SkyLight gives the windows and counts in about 1 ms per app, then AX adds titles and drops windows that aren't standard ones, in parallel, with a 250 ms timeout. While cycling it reads every regular app, so the counts are ready when the switcher appears. |
| `StackEdgesOverlay` | A transparent, click-through panel above the native switcher. Behind each multi-window icon it draws the top edges of one or two more windows, from the icon's AX frame. |
| `KeyTap` | A session-level `CGEvent` tap; details below. |
| `WindowSwitcher` | ⌘§'s own panel: one tile per window with its outline (design v6, direction 3). See § ⌘§. |
| `Focuser` | Bring one specific window to the front and make it key. |
| `Permissions` | Check for and request Accessibility; show its state in the menu-bar item. |

**The switcher's geometry on macOS 27** (measured on 2026-09-30 from a screenshot and the AX
frames, with five apps). The switcher is 712 × 176 pt. Each icon's AX frame is 128 pt, and the
icon image fills it, so the visible rounded square is 103 pt (Apple's icon grid: an 824 pt body
on a 1024 pt canvas). Icons are 6 pt apart, with 24 pt of padding around them. The Dock's
highlight is the frame inset by 4 pt, and the app's name sits just below the frame, where the old
dots were. That leaves 8.5 pt between the body and the highlight's top, and two stack edges rise
about 8.4 pt, filling it. The self-test notes these frames in its `stack-edges` scenario and fails
edges that come within 4 pt of the frame's top.

**The native switcher's window** is Dock-owned, full-screen, at layer 20; the overlay panels sit
at `.screenSaver`. The `AXProcessSwitcherList` is a direct child of the Dock's app element, found
150–210 ms after ⌘⇥, and its items are 128 × 128 pt tiles whose `AXTitle` is the app's name. Any
click closes the switcher, even one on BetterTab's own panel, so the stack edges are click-through.
(All measured by test 0 on 2026-09-29; § Route A+, removed.)

**`KeyTap` in detail.** It never swallows ⌘, so it never owes macOS anything. In Cycling it
passes everything through and only watches for the end: ⌘ released, Esc, or a key arriving with ⌘
up. In Windows it swallows § and the keys pressed while ⌘ is held (§ ⌘§).

## ⌘§: the window switcher (added 2026-09-30)

macOS has no switcher for one app's windows, so BetterTab draws this one entirely, and nothing
native is held open:

```
⌘§ ─► KeyTap: swallow §, enter Windows ─► WindowSwitchController ─► WindowIndex (SkyLight order)
        § / keys: swallowed, forwarded        │  model: tiles, highlight
        ⌘ release: passed ─► "commit"        ▼
                                   WindowSwitcher panel (after 160 ms) ─► pick ─► Focuser
```

- **The tap** swallows the ⌘§ keyDown and enters Windows. § is key code 10 (`kVK_ISO_Section`),
  or 50 (`kVK_ANSI_Grave`) from an ANSI keyboard: `KeyAboveTab` judges each event by its
  `keyboardEventKeyboardType`, against a table that `KBGetLayoutType` fills on main at launch,
  since that call isn't thread-safe. There it
  swallows every keyDown while ⌘ is held, forwarding § as a step and the rest as keys, and passes
  the ⌘ release, which commits. Nothing is ever owed to the Dock, so no exit posts anything. ⌘⇥
  passes and moves to Cycling. A keyDown with ⌘ up means the release got past the tap, and it
  counts as the release. The tap being turned off or stopped cancels.
- **The front app** is `NSWorkspace.frontmostApplication`. A SkyLight snapshot, about 1 ms, tells
  at once whether it has two windows; if not, the controller ends the session straight away, so a
  ⌘-shortcut typed next isn't swallowed.
- **Order:** `WindowIndex.load` keeps SkyLight's order as it stands, which puts the window you're
  in first. The ⌘⇥ list used to move AX's main window to the front instead, but on SkyLight's first
  delivery that came from the element cache and could be stale: right after a ⌘§ flip, it named
  the window you had just left.
- **Frames:** `WindowIndex.load(withFrames: true)`. `SLSGetWindowBounds` gives every real window's
  frame in global coordinates, on any Space, with no permission (measured on macOS 27, including
  full-screen windows on other Spaces and a second display at negative x). Each window's display is the one it overlaps most, from
  `CGGetActiveDisplayList` and `CGDisplayBounds`. The tile draws that display's box and the
  window's rectangle inside it.
- **The quick tap:** the panel appears 160 ms after ⌘§, or at once when the highlight moves. A
  release before SkyLight's windows arrive (a few milliseconds) opens the highlighted window as soon
  as they do.
- **Focusing:** `Focuser.focus`. The target app is already in front, so a window on another Space
  depends on the make-key record and the raise switching Space: `activate`, the fallback, does
  nothing for an app that's frontmost. They do switch it: SkyLight reports the new Space when the
  slide ends, 370–410 ms after the raise, so the fallback waits up to a second before it decides
  the switch is stuck (measured 2026-10-04).
- **The panel** is an `OverlayPanel` that takes the mouse, since there's no native switcher for a
  click to close.

## APIs

| Need | API | Private? | Permission |
|---|---|---|---|
| Find the native switcher, its highlighted app and icon frames | `AXUIElementCreateApplication(dockPid)` → search the children for subrole `AXProcessSwitcherList` → `kAXSelectedChildrenAttribute`, and `kAXPositionAttribute` / `kAXSizeAttribute` of each child; observe `kAXSelectedChildrenChangedNotification` and `kAXUIElementDestroyedNotification` (verified, DockDoor `DockDoor/Utilities/DockObserver+CmdTab.swift`, WindowLens `Sources/Core/Accessibility/DockProcessSwitcherObserver.swift`) | public API, but an undocumented Dock structure | Accessibility |
| See ⌘⇥, swallow ⌘§ and the keys after it | `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap)`; return nil to swallow (verified, DockDoor `KeybindHelper.swift`) | public | Accessibility only (verified live 2026-09-29: no Input Monitoring needed) |
| Windows and titles | `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`; for each window `kAXTitleAttribute`, `kAXSubroleAttribute`, `kAXMinimizedAttribute` | public | Accessibility |
| Letter labels for the user's layout | `UCKeyTranslate` on the current keyboard layout, for key codes `kVK_ANSI_A … kVK_ANSI_L` | public | none |
| AX window → `CGWindowID` | `_AXUIElementGetWindow` | private | Accessibility |
| A window's frame, on any Space (⌘§ outlines) | `SLSGetWindowBounds(cid, wid, &rect)` (verified by probe, 2026-09-30) | private | none |
| Display frames in the same coordinates | `CGGetActiveDisplayList`, `CGDisplayBounds` | public | none |
| Focus one window | `_SLPSSetFrontProcessWithOptions(psn, wid, userGenerated)`, then a make-key nudge, then `kAXRaiseAction`. For a minimized window, first set `kAXMinimizedAttribute` to false | private (links on macOS 27, verified by probe) | Accessibility |

**Focusing (approach verified in** AltTab `src/switcher/state/Window.swift`, `applyFocus`**;
built from yabai's MIT make-key technique instead, with its notice kept).** Since
macOS 14, `NSRunningApplication.activate` is only a request, and it won't reliably move keyboard
focus to another app. `kAXRaiseAction` and making a window key only change the stacking order.
Passing the window id to `_SLPSSetFrontProcessWithOptions` brings just that window forward, not
all of the app's windows. AltTab is still fixing this code in September 2026, so treat focusing as
the riskiest part.

**Which windows count.** AX reports dialogs, palettes, sheets and sidebars as windows too. Count
only the `AXStandardWindow` subrole, and include minimized windows. AltTab's filter,
`src/switcher/state/WindowAdmissionResolver.swift`, shows how many exceptions real apps need.

**Keeping the tap alive.** If the tap's callback runs too long, macOS turns the tap off
(`kCGEventTapDisabledByTimeout`). The tap turns itself back on, and ends any ⌘§ session, since
keys went past it meanwhile. AX calls stay off the tap's thread, with a short
`AXUIElementSetMessagingTimeout`.

## Permissions

The MVP needs **Accessibility only**, because window titles come from AX. Window names from
`CGWindowListCopyWindowInfo` and any thumbnails (via ScreenCaptureKit) would also need **Screen
Recording**, which recent macOS versions ask the user to re-approve from time to time. Both are out
of scope.

macOS ties the Accessibility grant to the app's designated requirement, which comes from its code
signature (§ Updates). Sign every build, dev builds and releases alike, with the same Apple
Development identity rather than ad hoc. Otherwise expect to grant access again in System Settings
→ Privacy & Security → Accessibility after every rebuild or update. The ad hoc releases up to
v1.0.71 did exactly that, and new Debug builds lost the grant twice on 2026-09-30 despite the
certificate, for a reason not yet found (`docs/handoff.md`, Findings). Also fix the bundle ID
from day one, because the grant depends on it too.

The app can't be sandboxed or ship on the App Store. Both rule out using Accessibility to control
other apps and calling private APIs.

## Updates (added 2026-10-04)

`docs/spec.md` § Updates says what it does. It's built on
[Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.0 (MIT), the usual macOS updater, as a
Swift package pinned to that exact version. Its code downloads, checks and replaces an app that
holds Accessibility, which is better borrowed from a well-tested project than written here.
`BetterTab/App/Updater.swift` is the whole of our side; `BetterTab/Info.plist` holds Sparkle's
settings and is merged into the generated Info.plist.
- **Only on request.** `SUEnableAutomaticChecks` is NO, so Sparkle never checks or asks to, and
  `SUAllowsAutomaticUpdates` NO removes its "install automatically" checkbox. The updater isn't
  even created until Check for Updates… is chosen, so idle stays at 0% CPU with no timers. Release
  builds only: Debug builds have no menu item, so a dev build never replaces itself.
- **What has to match.** The release workflow signs the disk image with an EdDSA key, and the app
  carries the public half (`SUPublicEDKey`). `SUVerifyUpdateBeforeExtraction` makes Sparkle check
  that signature before it unpacks anything. Without it, Sparkle accepts an update that passes
  *either* the EdDSA check or a code signature matching the running app, so that either key can be
  rotated; with it, the EdDSA check is required, and the only fallback is a Developer ID-signed
  disk image, which BetterTab doesn't make. After unpacking, the new app's code signature must be
  valid (`SUUpdateValidator.m`).
- **The grant follows the designated requirement.** A certificate-signed build's requirement names
  the certificate (`anchor apple generic and certificate leaf[subject.CN] = "Apple Development:
  …"`), and an ad hoc build's is its cdhash, which every build changes. Sparkle would install a
  validly signed update even if it were ad hoc, and the grant would be lost, so the release
  workflow refuses to publish without the certificate. The first certificate-signed release still
  asks once.
- **Replacing the app.** BetterTab isn't sandboxed, and a copy dragged into `/Applications` belongs
  to the user, so Sparkle's `Autoupdate` helper can replace it. BetterTab quits first, which removes
  the key tap, then the new copy is launched. Sparkle releases the new bundle from quarantine
  (`SUPlainInstaller.m`), so Gatekeeper doesn't ask for Open Anyway again; unverified on macOS 27
  (acceptance test 20).
- **The feed.** `SUFeedURL` is `releases/latest/download/appcast.xml` on GitHub: each release
  carries an appcast with one item, itself (`scripts/make-appcast.sh`). Its notes are Markdown,
  which Sparkle draws in a text view, so no web page is loaded. The feed isn't signed: it's served
  over HTTPS by GitHub, and anyone who could replace it could replace the release too.
- **What it sends and saves.** Requests carry only `User-Agent: BetterTab/<version>
  Sparkle/<version>`; `SUEnableSystemProfiling` is NO. Sparkle writes `SUHasLaunchedBefore`,
  `SULastCheckTime` and any skipped version to BetterTab's defaults (spec § Privacy). Skipping
  only filters automatic checks.
- **Sparkle's helpers** (`Autoupdate`, `Updater.app`) keep Sparkle's ad hoc signatures inside the
  framework, which Xcode re-signs with ours; `codesign --verify --deep --strict` passes. The XPC
  services are only for sandboxed apps and go unused.

## Windows on every Space

Decided 2026-09-29 after the first live run. The public AX API only sees windows on the current
Space, and the maintainer keeps windows full-screen, so BetterTab found nothing. Measured on this
Mac and researched in AltTab, yabai, Hammerspoon and WindowLens:
- **Which windows exist:** SkyLight, with no permission at all. `SLSCopyManagedDisplaySpaces`
  lists the Spaces; `SLSCopyWindowsWithOptionsAndTags` (options 0x7) lists their windows; and the
  `SLSWindowQueryWindows` iterator gives each window's pid, parent, level, tags and attributes.
  yabai's filter (MIT, `src/space.c`) keeps exactly the real windows, dropping the toolbars,
  title-bar strips and background tabs. It takes about 1 ms for every app, so the window counts come from it.
- **Titles:** only through AX. Without Screen Recording the window server returns empty titles.
  Per app: `kAXWindows` plus `kAXMainWindow` and `kAXFocusedWindow`, which reach the last main window
  on any Space. For windows still unresolved, a time-boxed `_AXUIElementCreateWithRemoteToken` scan
  runs, matching elements by `_AXUIElementGetWindow`. The element cache lives in memory; titles are
  never cached. A tile without a title yet shows "Untitled", and is still focusable by its window id.
- **Order:** SkyLight's, which is the current Space first and then other Spaces by recent use, then
  minimized windows.
- **Focus:** `_SLPSSetFrontProcessWithOptions` with the window id, the make-key record and the AX
  raise. macOS then slides to the window's Space. Without Accessibility the first call alone
  doesn't switch Space (measured); falling back to `NSRunningApplication.activate` lands on the app's
  front window's Space.

Scratch notes and probes from that day are in the session scratchpad, not in the repo; the
findings above are what matters.

## Route A+, removed

From 2026-09-29 to 2026-10-01, releasing ⌘⇥ on an app with two or more windows didn't switch.
BetterTab **hid that ⌘ release from the Dock**, so the Dock still thought ⌘ was held and kept its
switcher open, and showed a list of the app's windows above it to pick from with a letter. Every
way out posted a synthetic ⌘ release so the Dock could finish or cancel. Test 0, run with a
throwaway `Experiment` target on 2026-09-29, showed the hold worked with both the session and the
HID tap, that swallowed letters reached neither the Dock nor the app, and that any click closed
the held switcher.

It worked, and the maintainer dropped it (`docs/spec.md` § Out of scope): choosing a window at
every ⌘⇥ was too much thinking. Removing it removed the riskiest code, the swallowed ⌘ release, the
15 s no-input timeout and the synthetic keys. The code is in release v1.0.63 and in git history.

The alternative, **route B**, was never built: turn native ⌘⇥ off with the private
`CGSSetSymbolicHotKeyEnabled` and draw a switcher of BetterTab's own. Turning ⌘⇥ off lasts after
the process exits (verified, AltTab's comment in `src/macos/api-wrappers/SkyLight.framework.swift`),
so a crashed build would leave the Mac with no ⌘⇥. BetterTab never calls it.

## Project setup (decided 2026-09-29)

A plain Xcode project. Since Xcode 16, synchronized folders keep the `.pbxproj` stable when files
are added, so there's no generator to install. `LSUIElement = YES`, and the deployment target is
macOS 27, since this is for personal use. The required check is in `CLAUDE.md`.
