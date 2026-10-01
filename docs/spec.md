# BetterTab: spec

This file is the source of truth for what BetterTab does. `docs/product.md` explains why and
`docs/architecture.md` explains how. When they disagree with this file about behaviour, this
file wins. Written 2026-09-29; the stack edges come from the Claude design v5
(`docs/design-brief-v5.md`) and ⌘§ from v6 (`docs/design-brief-v6.md`). Changed 2026-09-30: stack
edges replaced the window-count dots, the first launch shows the Accessibility prompt, the menu
shows the version, every push to `main` publishes a release, and ⌘§ was added. Changed
2026-10-01: ⌘⇥ is native again. The window list it opened on release is gone (§ Out of scope).

## In one sentence

⌘§ is ⌘⇥ for the windows of the app you're in: hold ⌘, press § to step through them, and let go
to open one. And while you ⌘⇥, apps with more than one window show the edges of more windows
behind their icon.

## Principles

These decide every case this spec doesn't cover.

1. **⌘⇥ is macOS's.** BetterTab draws the stack edges over the native switcher and changes nothing
   else about it: every key passes, and every switch is native.
2. **⌘⇥ always works.** Whatever happens to BetterTab (a crash, a hang, a missing permission,
   a macOS update), the Mac is never left without a working ⌘⇥ or with ⌘ stuck down.
3. **One job: getting to the right window.** One shortcut, ⌘§, and nothing else: no settings
   window, no thumbnails, no more shortcuts, no window management. A new feature needs a reason
   stronger than "another app has it".
4. **Keyboard first.** Everything can be done from the keyboard. The mouse is a convenience,
   never a requirement.

## ⌘⇥: stack edges

Hold ⌘ and press Tab: the macOS switcher, as always. Apps with two or more windows show **stack
edges**: the top edges of more windows peeking out behind their icon, one edge for two windows
and two for three or more. Releasing ⌘ switches natively, as it always has. If the app's most
recent window isn't the one you want, ⌘§ gets you to the right one. (Dots under the icon were
tried first, but they read as the Dock's "running" dots and sat on the app name.)

- **Which windows count:** standard windows on every Space, including full-screen windows,
  minimized windows and the windows of hidden apps. Dialogs, palettes, sheets and background tabs
  don't count; an app's tabs are one window, as ⌘\` treats them. ⌘§ counts the same way.
  (Changed 2026-09-29: the first live run showed that counting only the current Space finds
  nothing for someone who keeps windows full-screen.)
- The edges stay inside the Dock's highlight, follow light and dark appearance, and appear on
  whichever display the switcher is on.
- A quick ⌘⇥ tap may close the switcher before the edges are drawn. Nothing else depends on them.

## ⌘§: the front app's windows

⌘⇥ lists apps, so the app you're in is the hardest one to reach: getting from one Chrome window to
another meant cycling through every other app and back to Chrome. ⌘§ is ⌘⇥ for the front app's
windows. Its look is direction 3, "window outlines", of the Claude design v6 (brief in
`docs/design-brief-v6.md`).

1. **Hold ⌘ and press §,** the key above Tab on an ISO keyboard. The window switcher opens in the
   middle of the display showing the window you're in. The highlight starts on the **second**
   window, the one you were in before, the way ⌘⇥ starts on the previous app. ⌘⇧§ starts on the
   last window instead.
2. **Press § again** to move the highlight on, wrapping from the last window to the first. ⇧§
   moves it back, and so do the arrow keys. Holding § down repeats.
3. **Release ⌘:** the highlighted window comes to the front as the key window, and the switcher
   closes.

**A quick ⌘§ tap** goes straight to the previous window without the switcher appearing: it shows
only once ⌘§ has been held for 160 ms, or as soon as the highlight moves. With two windows, ⌘§
flips between them.

### The window switcher

- **One tile per window,** up to 9, labelled **A S D F G H J K L** (the home row, left to right).
  Letters are matched by **physical key position**, not by the character typed, and each badge is
  labelled with what the user's keyboard layout prints on that key: on AZERTY the first key is
  labelled Q. With more than 9 windows, a last "+N more" tile can't be picked.
- **Each tile is a miniature of the window's display,** with the window's outline drawn where the
  window is and at its size. A full-screen window fills its display. A display of another shape
  gets a box of that shape. A minimized window's outline is dimmed, and its badge has the
  minimized marker.
- **Only the highlighted window's title shows,** under the tiles, on up to two lines. A window
  with no title is shown as "Untitled". The switcher keeps one size while it's open, however long
  the titles.
- **The highlighted tile** has the switcher's highlight behind it, and its outline and badge take
  the user's accent colour. Light and dark follow the system; the background is a system material.
- **No pictures of windows.** Frames need no permission; pictures would need Screen Recording.
- It appears at once, with no animation, as the native switcher does.

**Order:** the window you're in, then the app's other windows in the window server's order: the
current Space front to back, then the other Spaces, most recently visited first. Minimized windows
come last. That's close to most recently used, except that a window on another Space always comes
after those on the current one.

### Keys while ⌘ is held

| Key | What happens |
|---|---|
| **§** / **⇧§** | Moves the highlight to the next / previous window. |
| **→ ↓** / **← ↑** | The same. |
| **A–L** | Opens that window at once. |
| **Return** | Opens the highlighted window. |
| **Esc** | Closes the switcher and changes nothing. Releasing ⌘ afterwards does nothing. |
| **⌘ released** | Opens the highlighted window. |
| **Tab** | Closes the window switcher and opens ⌘⇥, as if ⌘⇥ had been pressed. |
| **Anything else** | Does nothing. No ⌘-shortcut reaches the app until ⌘ is released. |

**Mouse:** hovering over a tile highlights it, and a click opens that window. The pointer moves
the highlight only once it has moved, so a pointer resting where the switcher opens picks nothing.

### Edge cases

- **An app with one window or none:** ⌘§ does nothing.
- **Picking the window you're in (A)** only closes the switcher.
- **There's no timeout.** ⌘ is held down the whole time, and letting go ends it.
- **Nothing is held back from macOS.** ⌘ passes through both ways, so ⌘§ can't leave ⌘ stuck
  down. Only § and the keys pressed while the switcher is open are swallowed.
- **A window on another Space,** full-screen or not: opening it switches to its Space, with
  macOS's usual slide.
- **A minimized window** is restored and focused.
- **ANSI keyboards** have no § key. Their key above Tab is `, and ⌘` is macOS's own "Move focus to
  next window", so ⌘§ isn't available on them for now.

## States

```
Idle ──⌘⇥──► Cycling (native switcher; stack edges drawn)
                └─ ⌘ released, or Esc ─► native switch or cancel ─────────────────────► Idle

Idle ──⌘§──► Windows (switcher shown after 160 ms; highlight = the previous window)
                ├─ § / ⇧§ / arrows ─► highlight moves ─► switcher shown
                ├─ ⌘ released, letter, Return or click ─► open that window ──────────► Idle
                ├─ Esc ─► close, nothing changes ─────────────────────────────────────► Idle
                └─ ⌘⇥ ─► Cycling
```

When idle, BetterTab uses no CPU. It has no timers and does no polling, only the key tap.

## The menu-bar item

This is the only UI besides the stack edges and the ⌘§ switcher. It shows the app
icon's keycap labelled A as a template icon, and the menu has:

- **A status line:** "Active", "Needs Accessibility permission", or "Can't find the ⌘⇥
  switcher". The last one appears when BetterTab has failed to find it three times in a row.
- **Grant Accessibility…**, shown only when the permission is missing. It triggers the system
  prompt and opens System Settings at Privacy & Security → Accessibility.
- **Launch at Login**, a checkmark toggle using `SMAppService`.
- **The version,** greyed out, such as "Version 0.1.87". Debug builds add "(Debug)".
- **Quit BetterTab.**

There's no Dock icon and no windows. Quit is the off switch.

## Permissions and first launch

- **Accessibility is the only permission.** The key tap doesn't need Input Monitoring (confirmed
  live on 2026-09-29). On macOS 27 the pane is titled "Device Control and Data Access".
- **First launch without the permission:** the system's Accessibility prompt appears once, because
  a menu-bar item alone is easy to miss (the notch can hide it). After that only the menu offers
  it. The menu-bar item shows its needs-permission state, there are no stack edges, and ⌘§ does
  nothing. There's no onboarding window.
- **When the permission is granted,** BetterTab notices within 2 s, without a restart. **When
  it's revoked,** BetterTab goes back to the needs-permission state. ⌘⇥ keeps working natively
  throughout.

## Privacy

BetterTab has no network code, analytics or crash reporting, and saves nothing to disk apart from
the Launch at Login state and whether the first-launch prompt has been shown. Window titles and
frames are held in memory only while a switcher is open, and are never logged. Release builds log counts
and states only.

## Performance targets

| What | Target |
|---|---|
| Stack edges drawn after the switcher appears | under 100 ms. The window counts come from SkyLight, about 1 ms per app; AX only drops windows that aren't standard ones, with a 250 ms timeout, so a hung app still gets its edges |
| ⌘§ switcher visible | 160 ms after ⌘§ while ⌘ is held, at once when the highlight moves; a quicker release flips without it |
| The chosen window in front after ⌘§ | under 100 ms on the current Space; another Space adds macOS's slide |
| Idle CPU | 0% |
| Memory | under 30 MB |

## Constants

These are hard-coded, with no settings UI.

| Constant | Value |
|---|---|
| Letters | A S D F G H J K L (physical home-row keys) |
| Window switcher key | § (`kVK_ISO_Section`, above Tab on ISO keyboards) |
| Window switcher shows after | 160 ms |
| Maximum tiles | 9 |
| Stack edges per icon | at most 2 |
| AX messaging timeout | 250 ms |
| Permission re-check while missing | every 2 s |

## Out of scope

These aren't "later"; they're **no**, unless daily use proves otherwise:
- **a window list on ⌘⇥.** It was built: releasing ⌘⇥ on an app with two or more windows held the
  native switcher open and listed that app's windows to pick from. The maintainer used it, and
  dropped it on 2026-10-01: deciding on a window at every ⌘⇥ was more mental effort than it
  saved, while native ⌘⇥, then ⌘§ when it lands on the wrong window, needs no thought. It's in
  release v1.0.63 and in git history;
- thumbnails or previews (they would need Screen Recording);
- closing, minimizing or moving windows from the switcher;
- Chrome tabs;
- shortcuts or modes beyond ⌘§;
- a settings window, and per-app exclusion lists;
- Dock previews;
- notarization and automatic updates. Releases are zips on GitHub (`docs/releasing.md`); users
  click Open Anyway once, and download new versions themselves.

## Acceptance tests

Run these by hand on macOS 27. "Chrome ×3" means three Chrome windows on the current Space.

1. **Native ⌘⇥.** ⌘⇥ to Chrome ×3 and release: a native switch to Chrome's most recent window,
   with nothing else on screen. The same for Notes (one window).
2. **Stack edges.** While cycling, Chrome ×3 shows two edges behind its icon, Terminal ×2 shows
   one, and Notes shows none. The edges stay inside the switcher's highlight.
3. **Stack edges, other Spaces.** With one Chrome window on Desktop 1 and two full-screen, Chrome
   shows two stack edges.
4. **Stack edges, second display.** With the switcher on the other display, the edges appear there.
5. **⌘§ flip.** In Chrome ×2, tap ⌘§ quickly: the other Chrome window is in front and key, and no
   switcher appeared. Tap it again: back to the first.
6. **⌘§ cycle.** In Terminal ×3, hold ⌘ and press § twice: three tiles, the third highlighted.
   Release ⌘: that window is in front.
7. **⌘§ backwards and wrap.** Hold ⌘ and press ⇧§: the last window is highlighted. Press § on the
   last: the highlight wraps to the first.
8. **⌘§ letters and Esc.** Hold ⌘, press § then D: window 3 opens at once. Hold ⌘, press § then
   Esc, and release ⌘: nothing changes, and ⌘S afterwards saves as usual.
9. **⌘§ outlines.** A window on the left half of the screen shows a left-half outline, and a
   full-screen one fills its box. On a second display of another shape, the box has that shape.
10. **⌘§ one window.** In Notes ×1, ⌘§ does nothing.
11. **⌘§ full-screen.** With two full-screen Chrome windows, ⌘§ slides to the other one's Space and
    typing goes into it. Note whether another Chrome window flashes up first.
12. **⌘§ minimized.** In Chrome ×3 with one window minimized, its tile comes last, dimmed and with
    the minimized marker. Picking it restores it and focuses it.
13. **⌘§ many windows.** With 11 Finder windows, ⌘§ shows A–L plus "+2 more".
14. **Keyboard layout.** On a non-US layout, the badges show what that layout prints, and the
    home-row keys pick windows.
15. **No stuck ⌘.** After a native ⌘⇥, a ⌘§ flip, an Esc, a letter pick and a click pick, type into
    TextEdit each time: plain letters, not ⌘-shortcuts.
16. **Crash.** `kill -9` BetterTab while the ⌘§ switcher is open: the switcher goes, and ⌘⇥, ⌘ and
    typing work normally afterwards.
17. **Permission.** Revoke Accessibility: the status says so, there are no stack edges, ⌘§ does
    nothing, and ⌘⇥ works. Grant it: active again within 2 s. On the first launch without it, the
    system prompt appears once, and not on later launches.
18. **Idle.** With no switcher open for a minute, Activity Monitor shows 0% CPU.
19. **Version.** The menu shows "Version" and the release's version, such as 1.0.70.
