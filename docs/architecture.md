# BetterTab: architecture

This is a proposal; nothing is built yet. Research was done on 2026-09-29. Anything marked
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
- **Unverified; this whole route depends on it:** swallowing the `flagsChanged` event for the ⌘
  release keeps the native switcher open. It fails if the Dock reads the hardware modifier state
  directly, or if it gets the release before any event tap sees it. It could also be fragile if
  the Dock notices ⌘ is up from the flags on later events, such as mouse moves. Nobody is known to
  ship this.

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
       sees ⌘⇥, ⌘ release,          │  Cycling: DotsOverlay draws window counts over native icons
       letters, Esc                  │  ⌘ released on an app with ≥ 2 windows: swallow it → Picking
                                     ▼
                        WindowList panel ─► pick ─► Focuser ─► the chosen window
```

| Component | Job |
|---|---|
| `SwitcherWatcher` | On ⌘⇥, find the Dock's `AXProcessSwitcherList`. Follow its selected child and read each child's frame. Report when the list is destroyed. |
| `WindowIndex` | When the switcher opens, read every listed app's standard windows in parallel, using AX with a 250 ms timeout. That gives the dot counts, and means the highlighted app's list is ready before ⌘ is released. |
| `DotsOverlay` | A transparent, click-through panel above the native switcher, drawing dots under each multi-window icon at its AX frame. |
| `KeyTap` | A session-level `CGEvent` tap; details below. |
| `WindowList` | The panel above the highlighted icon (design v4/v5). |
| `Focuser` | Bring one specific window to the front and make it key. |
| `Permissions` | Check for and request Accessibility; show its state in the menu-bar item. |

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

## APIs

| Need | API | Private? | Permission |
|---|---|---|---|
| Find the native switcher, its highlighted app and icon frames | `AXUIElementCreateApplication(dockPid)` → search the children for subrole `AXProcessSwitcherList` → `kAXSelectedChildrenAttribute`, and `kAXPositionAttribute` / `kAXSizeAttribute` of each child; observe `kAXSelectedChildrenChangedNotification` and `kAXUIElementDestroyedNotification` (verified, DockDoor `DockDoor/Utilities/DockObserver+CmdTab.swift`, WindowLens `Sources/Core/Accessibility/DockProcessSwitcherObserver.swift`) | public API, but an undocumented Dock structure | Accessibility |
| See and swallow keys and ⌘ changes | `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap)`; return nil to swallow (verified for keys, DockDoor `KeybindHelper.swift`; unverified for the ⌘ release). If the session level isn't early enough, try `.cghidEventTap` | public | Accessibility (verified, AltTab); the experiment checks whether Input Monitoring is needed too |
| Post the synthetic ⌘ release and Esc | `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `kVK_Command` / `kVK_Escape`, then `.post(tap: .cghidEventTap)` (DockDoor posts to that tap) | public | Accessibility |
| Windows and titles | `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`; for each window `kAXTitleAttribute`, `kAXSubroleAttribute`, `kAXMinimizedAttribute` | public | Accessibility |
| Letter labels for the user's layout | `UCKeyTranslate` on the current keyboard layout, for key codes `kVK_ANSI_A … kVK_ANSI_L` | public | none |
| AX window → `CGWindowID` | `_AXUIElementGetWindow` | private | Accessibility |
| Focus one window | `_SLPSSetFrontProcessWithOptions(psn, wid, userGenerated)`, then a make-key nudge, then `kAXRaiseAction`. For a minimized window, first set `kAXMinimizedAttribute` to false | private (links on macOS 27, verified by probe) | Accessibility |
| Route B only: turn native ⌘⇥ off and on | `CGSSetSymbolicHotKeyEnabled(1 or 2, Bool)`; read the state with `CGSIsSymbolicHotKeyEnabled` | private. Links on macOS 27; both read as enabled on 2026-09-29 (verified, probe) | none |

**Focusing (verified,** AltTab `src/switcher/state/Window.swift`, `applyFocus`**).** Since
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

**Other Spaces (both routes).** The public AX API only sees windows on the current Space. AltTab
reaches other Spaces with a private `_AXUIElementCreateWithRemoteToken` brute-force trick. For now
the MVP covers the current Space only.

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

## Project setup (proposed, not decided)

Use a plain Xcode project. Since Xcode 16, synchronized folders keep the `.pbxproj` stable when
files are added, so there's no generator to install. Set `LSUIElement = YES`. The deployment target
is the current macOS, since this is for personal use. Once a scheme exists, its `xcodebuild … build`
command becomes the required check in `/handoff-update`.
