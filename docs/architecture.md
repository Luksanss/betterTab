# BetterTab: architecture

Route A+ is built, on the evidence of test 0 (§ Test 0 results), and worked live on 2026-09-29,
windows on other Spaces included. Research was done on 2026-09-29. Anything marked
**(verified)** was either read in the source of an app that ships the technique, or probed
read-only on the dev machine (macOS 27.0, Xcode 27.0, Swift 6.4, arm64). The three apps are:

- [AltTab](https://github.com/lwouis/alt-tab-macos), GPL-3.0;
- [DockDoor](https://github.com/ejbills/DockDoor), GPL-3.0;
- [WindowLens](https://github.com/FornaxChemica/WindowLens), MIT.

File paths below are inside those repos. Anything marked **(unverified)** is the plan, and the
experiment at the end of this file decides it.

**Licences.** AltTab and DockDoor are GPL-3.0: read them to learn how things are done, because
copying their code would make this project GPL. WindowLens is MIT, so its code can be reused as
long as its copyright notice is kept.

## The problem the flow creates

`docs/spec.md` asks for this: release ⌘ on a multi-window app, and the switch **doesn't happen
yet**. The switcher stays on screen and a window list opens above it. The native macOS switcher
does the opposite: releasing ⌘ switches straight away and closes it. There are two ways to get
the specified flow.

### Route A+: hold the native switcher open (try first)

The switcher stays macOS's own. BetterTab watches it and, at the moment you release ⌘ on an app
with two or more windows, **hides that ⌘ release from the Dock**. The Dock still thinks ⌘ is held,
so its switcher stays open, and BetterTab shows the window list above it. Once you pick or
cancel, BetterTab lets the Dock finish.

What's verified and what isn't:
- **Verified (DockDoor, WindowLens):**
  - A session-level event tap sees ⌘⇥ and can swallow other keys while the native switcher is
    open.
  - The switcher can be read through Accessibility: its highlighted app and each icon's frame.
- **Verified on this Mac by test 0 (2026-09-29; § Test 0 results), and the whole route depends
  on it:** swallowing the `flagsChanged` event for the ⌘ release keeps the native switcher open,
  with the session tap and with the HID tap. Mouse moves don't disturb it, but any click closes
  it. Nobody else is known to ship this.

Why it's worth trying: nothing native gets rebuilt, and native ⌘⇥ is never turned off.

### Route B: replace the native switcher (fallback)

If the experiment fails, do what AltTab does:
1. turn off symbolic hotkeys 1 and 2 (⌘⇥ and ⌘⇧⇥) with the private `CGSSetSymbolicHotKeyEnabled`;
2. register ⌘⇥ ourselves;
3. draw our own switcher, using the design's icon row.

The spec's flow is then entirely ours to implement. The costs:
- rebuilding what the native switcher does (see Parity);
- turning native ⌘⇥ off lasts after the process exits, so a crashed build leaves the Mac with no
  ⌘⇥ (see Recovery).

### Rejected: pick while holding ⌘

With this option, the window row appears while ⌘ is still held, and releasing ⌘ confirms. It
needs no trick, because the native switcher runs unchanged. The maintainer chose picking after
release instead (2026-09-29, `docs/product.md`). The research still applies to route A+.

## How route A+ works

```
⌘⇥ ─► Dock (native switcher) ─► AXProcessSwitcherList ─► SwitcherWatcher: highlighted app + icon frames
 │                                                                 │
 └─► KeyTap (session event tap) ─► Controller ◄────────────────────┘
       sees ⌘⇥, ⌘ release,          │  Cycling: StackEdgesOverlay draws stack edges over native icons
       letters, Esc                  │  ⌘ released on an app with ≥ 2 windows: swallow it → Picking
                                     ▼
                        WindowList panel ─► pick ─► Focuser ─► the chosen window
```

| Component | Job |
|---|---|
| `SwitcherWatcher` | On ⌘⇥, find the Dock's `AXProcessSwitcherList`. Follow its selected child and read each child's frame. Report when the list is destroyed. |
| `WindowIndex` | When the switcher opens, read every listed app's real windows: SkyLight gives the windows and counts in about 1 ms per app, then AX adds the titles in parallel, with a 250 ms timeout. So the highlighted app's list is ready before ⌘ is released, and a hung app keeps SkyLight's untitled windows. |
| `StackEdgesOverlay` | A transparent, click-through panel above the native switcher. Behind each multi-window icon it draws the top edges of one or two more windows, from the icon's AX frame. |
| `KeyTap` | A session-level `CGEvent` tap; details below. |
| `WindowList` | The panel above the highlighted icon (design v4/v5). |
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

**`KeyTap` in detail.** In Cycling, it passes everything through, but watches for ⌘ being
released. If the highlighted app has two or more windows, it swallows that release and moves to
Picking. In Picking, it swallows every key and every ⌘ press or release, and acts on letters,
arrows, Return and Esc.

**Ending a Picking session.** Every way out ends by posting a synthetic ⌘ release, so the Dock and
every app agree that ⌘ is up. There are two candidate ways to pick; the experiment decides which
flashes less:
- **Picking A:** post the synthetic ⌘ release. The Dock finishes the switch natively, bringing the
  app's most recent window forward.
- **Picking another letter, option 1:** post the ⌘ release, let the Dock activate the app, then
  focus window n.
- **Picking another letter, option 2 (preferred if it works):** post Esc so the Dock cancels, post
  the ⌘ release, then focus window n directly. The app activates with the right window, so the most
  recent one never flashes up.
- **Cancel (Esc or the 15 s timeout):** pass Esc to the Dock, then post the ⌘ release.
- **⌘⇥ again:** pass Tab to the Dock, since it still believes ⌘ is held, and go back to Cycling.

## ⌘§: the window switcher (added 2026-09-30)

macOS has no switcher for one app's windows, so BetterTab draws this one entirely, and nothing
native is held open. That makes it much simpler than route A+:

```
⌘§ ─► KeyTap: swallow §, enter Windows ─► WindowSwitchController ─► WindowIndex (SkyLight order)
        § / keys: swallowed, forwarded        │  model: tiles, highlight
        ⌘ release: passed ─► "commit"        ▼
                                   WindowSwitcher panel (after 160 ms) ─► pick ─► Focuser
```

- **The tap** swallows the ⌘§ keyDown (key code 10, `kVK_ISO_Section`) and enters Windows. There it
  swallows every keyDown while ⌘ is held, forwarding § as a step and the rest as keys, and passes
  the ⌘ release, which commits. Nothing is ever owed to the Dock, so no exit posts anything. ⌘⇥
  passes and moves to Cycling. A keyDown with ⌘ up means the release got past the tap, and it
  counts as the release. The tap being turned off or stopped cancels.
- **The front app** is `NSWorkspace.frontmostApplication`. A SkyLight snapshot, about 1 ms, tells
  at once whether it has two windows; if not, the controller ends the session straight away, so a
  ⌘-shortcut typed next isn't swallowed.
- **Order:** `WindowIndex.load(order: .windowServer)` keeps SkyLight's order as it stands, which
  puts the window you're in first. The ⌘⇥ list moves AX's main window to the front instead, but on
  SkyLight's first delivery that comes from the element cache and can be stale; for ⌘§, right
  after a ⌘§ flip, it names the window you just left.
- **Frames:** `SLSGetWindowBounds` gives every real window's frame in global coordinates, on any
  Space, with no permission (measured on macOS 27, including full-screen windows on other Spaces
  and a second display at negative x). Each window's display is the one it overlaps most, from
  `CGGetActiveDisplayList` and `CGDisplayBounds`. The tile draws that display's box and the
  window's rectangle inside it.
- **The quick tap:** the panel appears 160 ms after ⌘§, or at once when the highlight moves. A
  release before SkyLight's windows arrive (a few milliseconds) opens the highlighted window as soon
  as they do.
- **Focusing** is the list's: `Focuser.focus`. The target app is already in front, so a window on
  another Space depends on the make-key record and the raise switching Space: `activate`, the
  fallback, does nothing for an app that's frontmost.
- **The panel** is an `OverlayPanel` that takes the mouse, since there's no native switcher for a
  click to close.

## APIs

| Need | API | Private? | Permission |
|---|---|---|---|
| Find the native switcher, its highlighted app and icon frames | `AXUIElementCreateApplication(dockPid)` → search the children for subrole `AXProcessSwitcherList` → `kAXSelectedChildrenAttribute`, and `kAXPositionAttribute` / `kAXSizeAttribute` of each child; observe `kAXSelectedChildrenChangedNotification` and `kAXUIElementDestroyedNotification` (verified, DockDoor `DockDoor/Utilities/DockObserver+CmdTab.swift`, WindowLens `Sources/Core/Accessibility/DockProcessSwitcherObserver.swift`) | public API, but an undocumented Dock structure | Accessibility |
| See and swallow keys and ⌘ changes | `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap)`; return nil to swallow (verified for keys, DockDoor `KeybindHelper.swift`; unverified for the ⌘ release). If the session level isn't early enough, try `.cghidEventTap` | public | Accessibility only (verified live 2026-09-29: no Input Monitoring needed) |
| Post the synthetic ⌘ release and Esc | `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `kVK_Command` / `kVK_Escape`, then `.post(tap: .cghidEventTap)` (DockDoor posts to that tap) | public | Accessibility |
| Windows and titles | `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`; for each window `kAXTitleAttribute`, `kAXSubroleAttribute`, `kAXMinimizedAttribute` | public | Accessibility |
| Letter labels for the user's layout | `UCKeyTranslate` on the current keyboard layout, for key codes `kVK_ANSI_A … kVK_ANSI_L` | public | none |
| AX window → `CGWindowID` | `_AXUIElementGetWindow` | private | Accessibility |
| A window's frame, on any Space (⌘§ outlines) | `SLSGetWindowBounds(cid, wid, &rect)` (verified by probe, 2026-09-30) | private | none |
| Display frames in the same coordinates | `CGGetActiveDisplayList`, `CGDisplayBounds` | public | none |
| Focus one window | `_SLPSSetFrontProcessWithOptions(psn, wid, userGenerated)`, then a make-key nudge, then `kAXRaiseAction`. For a minimized window, first set `kAXMinimizedAttribute` to false | private (links on macOS 27, verified by probe) | Accessibility |
| Route B only: turn native ⌘⇥ off and on | `CGSSetSymbolicHotKeyEnabled(1 or 2, Bool)`; read the state with `CGSIsSymbolicHotKeyEnabled` | private. Links on macOS 27; both read as enabled on 2026-09-29 (verified, probe) | none |

**Focusing (approach verified in** AltTab `src/switcher/state/Window.swift`, `applyFocus`**;
built from yabai's MIT make-key technique instead, with its notice kept).** Since
macOS 14, `NSRunningApplication.activate` is only a request, and it won't reliably move keyboard
focus to another app. `kAXRaiseAction` and making a window key only change the stacking order.
Passing the window id to `_SLPSSetFrontProcessWithOptions` brings just that window forward, not
all of the app's windows. AltTab is still fixing this code in September 2026, so treat focusing as
the second-riskiest part, after the hold-open trick.

**Which windows count.** AX reports dialogs, palettes, sheets and sidebars as windows too. Count
only the `AXStandardWindow` subrole, and include minimized windows. AltTab's filter,
`src/switcher/state/WindowAdmissionResolver.swift`, shows how many exceptions real apps need.

**Keeping the tap alive.** If the tap's callback runs too long, macOS turns the tap off
(`kCGEventTapDisabledByTimeout`). Handle that event by turning the tap back on. In route A+ this is
more serious: a tap turned off *during Picking* would leave the switcher held open with nothing
driving it. So on `kCGEventTapDisabledByTimeout`, if the session is in Picking, cancel it. Keep AX
calls off the tap's thread and set a short `AXUIElementSetMessagingTimeout`.

## Permissions

The MVP needs **Accessibility only**, because window titles come from AX. Window names from
`CGWindowListCopyWindowInfo` and any thumbnails (via ScreenCaptureKit) would also need **Screen
Recording**, which recent macOS versions ask the user to re-approve from time to time. Both are out
of scope.

macOS ties the Accessibility grant to the app's code signature. Sign every dev build with the
same Apple Development identity rather than ad hoc. Otherwise expect to grant access again in
System Settings → Privacy & Security → Accessibility after rebuilds. This is known macOS
behaviour but hasn't been hit here yet. Also fix the bundle ID from day one, because the grant
depends on it too.

The app can't be sandboxed or ship on the App Store. Both rule out using Accessibility to control
other apps and calling private APIs.

## Parity (route B only)

Route A+ inherits all of this from the native switcher. Route B has to rebuild it:

- **Must have:** MRU order · ⌘⇧⇥ goes backwards · a quick tap switches to the previous app
  without flashing the UI · Esc cancels · all regular apps are listed, including ones with no
  windows · the switcher appears on the right display · Q to quit and H to hide the highlighted app
  while cycling.
- **Later:** mouse hover and click on icons · dragging files onto an icon.

**Windows on every Space (both routes; decided 2026-09-29 after the first live run).** The public AX
API only sees windows on the current Space, and the maintainer keeps windows full-screen, so
BetterTab found nothing. Measured on this Mac and researched in AltTab, yabai, Hammerspoon and
WindowLens:
- **Which windows exist:** SkyLight, with no permission at all. `SLSCopyManagedDisplaySpaces`
  lists the Spaces; `SLSCopyWindowsWithOptionsAndTags` (options 0x7) lists their windows; and the
  `SLSWindowQueryWindows` iterator gives each window's pid, parent, level, tags and attributes.
  yabai's filter (MIT, `src/space.c`) keeps exactly the real windows, dropping the toolbars,
  title-bar strips and background tabs. It takes about 1 ms for every app, so the window counts come from it.
- **Titles:** only through AX. Without Screen Recording the window server returns empty titles.
  Per app: `kAXWindows` plus `kAXMainWindow` and `kAXFocusedWindow`, which reach the last main window
  on any Space. For windows still unresolved, a time-boxed `_AXUIElementCreateWithRemoteToken` scan
  runs, matching elements by `_AXUIElementGetWindow`. The element cache lives in memory; titles are
  never cached. A row without a title yet shows "Untitled", and is still focusable by its window id.
- **Order:** A is the main window, then SkyLight's order, which is the current Space first and then
  other Spaces by recent use, then minimized windows.
- **Focus:** `_SLPSSetFrontProcessWithOptions` with the window id, the make-key record and the AX
  raise. macOS then slides to the window's Space. Without Accessibility the first call alone
  doesn't switch Space (measured); falling back to `NSRunningApplication.activate` lands on the app's
  front window's Space.

Scratch notes and probes from that day are in the session scratchpad, not in the repo; the
findings above are what matters.

## Recovery

- **Route A+: a swallowed ⌘ release.** If BetterTab dies during Picking, the Dock is left thinking
  ⌘ is held, and its switcher stays open. The expectation (unverified; acceptance test 14) is that
  pressing and releasing ⌘ once more sends the Dock a real release and ends it. Every normal path
  out of Picking posts the synthetic ⌘ release: pick, cancel, timeout, the tap being turned off,
  and quit.
- **Route B: native ⌘⇥ turned off.** That lasts after the process exits (verified, AltTab's comment
  on `CGSSetSymbolicHotKeyEnabled` in `src/macos/api-wrappers/SkyLight.framework.swift`). If route
  B is ever built, commit this as `scripts/restore-native-cmd-tab.swift` before the first build that
  turns ⌘⇥ off. It's written from AltTab's declaration and hasn't been run yet:

  ```swift
  import CoreGraphics

  @_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
  func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int, _ isEnabled: Bool) -> CGError

  CGSSetSymbolicHotKeyEnabled(1, true)  // ⌘⇥
  CGSSetSymbolicHotKeyEnabled(2, true)  // ⌘⇧⇥
  ```

  Run it with `swift scripts/restore-native-cmd-tab.swift`.

## The experiment: decide the route before building any UI

Run this in a throwaway target on macOS 27. **Test 0 decides the route.** Every other test applies
to whichever route wins.

0. **Hold the native switcher open.** Have ⌘⇥ highlight Chrome. The tap swallows the ⌘ release;
   try the session-level tap first, then the HID-level one. Pass means all of these hold:
   - a. the native switcher stays on screen for at least 15 s after ⌘ is physically released;
   - b. moving the mouse doesn't close or confirm it (clicking on BetterTab's own panel is tested
     separately, and decides whether the list can take clicks);
   - c. swallowed letter keys reach neither the Dock nor the front app;
   - d. posting a synthetic ⌘ release makes the Dock finish the switch to the highlighted app;
   - e. posting Esc and then a synthetic ⌘ release makes the Dock cancel, leaving the original app
     in front;
   - f. afterwards, typing into TextEdit gives plain letters (⌘ isn't stuck);
   - g. if BetterTab is killed during the hold, one more ⌘ press-and-release closes the switcher;
   - h. with the switcher held open, ⌘⇥ moves the native highlight on;
   - i. a quick ⌘⇥ tap, released before the switcher draws, can also be held.

   **If a–g pass, use route A+.** If i fails, a quick tap stays native (spec § Edge cases). If any
   of a–g fail, use route B.
1. **Read the switcher.** Log the highlighted app and every icon frame while cycling; log when the
   list is destroyed. (Route A+ only.)
2. **List windows.** With two Chrome windows on the current Space, AX returns exactly two standard
   windows with the right titles, in front-to-back order. Also try a minimized window and a Finder
   window.
3. **Focus one without a flash.** From another app, bring Chrome's *back* window to the front as
   the key window, and check that typing goes into it. In route A+, compare the two ways of picking
   another letter (let the Dock activate, or cancel then focus) and keep whichever doesn't flash
   the most recent window.

If test 3 fails on both routes, the product doesn't work, so stop and rethink.

### Test 0 results (2026-09-29, the maintainer's run)

Run with the `Experiment` harness (`docs/experiment.md`); the evidence is its log.
- **Pass:** the hold itself, with both tap locations; b (mouse moves); c (swallowed letters); d (the
  synthetic ⌘ release finished a switch from Ghostty to Chrome); f (session and HID state both show
  ⌘ up 200 ms after every release); h (⌘ pressed again, then Tab, moves the highlight on).
- **Not yet shown:** a (the longest idle hold with the switcher up was about 6 s, not 15 s); e
  (every Esc was on an app that was already in front, so cancelling and switching look the same);
  g (`kill -9` recovery wasn't run); i (no deliberate quick tap).
- **Clicks close the switcher.** The first click, even on the harness's own panel at layer 21,
  closes it and never reaches the panel. So the window list is click-through, and the controller
  ends a hold with only the ⌘ release when the switcher closes.
- **The switcher's window** is Dock-owned, full-screen, at layer 20. The `AXProcessSwitcherList`
  is a direct child of the Dock's app element, found 150–210 ms after ⌘⇥. Its items are 128×128 pt
  tiles whose `AXTitle` is the app's name.
- **Input Monitoring:** not needed. The run itself granted both at once, but BetterTab's tap later
  ran with Accessibility alone.

On this evidence route A+ was built. a, e and g are still to be confirmed; they're also covered by
acceptance tests 7, 14 and 15.

## Project setup (decided 2026-09-29)

A plain Xcode project. Since Xcode 16, synchronized folders keep the `.pbxproj` stable when files
are added, so there's no generator to install. `LSUIElement = YES`, and the deployment target is
macOS 27, since this is for personal use. The required check is in `CLAUDE.md`.
