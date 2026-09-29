# BetterTab: spec

This file is the source of truth for what BetterTab does. `docs/product.md` explains why and
`docs/architecture.md` explains how. When they disagree with this file about behaviour, this
file wins. Rewritten 2026-09-29 around the maintainer's flow: pick the window after releasing ⌘.
The look comes from the Claude design (v4 reviewed; v5 brief in `docs/design-brief-v5.md`).

## In one sentence

Release ⌘⇥ on an app with more than one window, and instead of switching, a small list of that
app's windows opens above its icon. Press A, S, D… to go straight to the one you want.

## Principles

These decide every case this spec doesn't cover.

1. **Single-window apps aren't touched.** If the app you release on has one window (or none),
   the switch is pure native ⌘⇥.
2. **⌘⇥ always works.** Whatever happens to BetterTab (a crash, a hang, a missing permission,
   a macOS update), the Mac is never left without a working ⌘⇥ or with ⌘ stuck down.
3. **One feature.** No settings window, no thumbnails, no extra shortcuts, no window management.
   A new feature needs a reason stronger than "another app has it".
4. **Keyboard first.** Everything can be done from the keyboard. The mouse is a convenience,
   never a requirement.

## The flow

1. **Cycle.** Hold ⌘ and press Tab: the macOS switcher, as always. Apps with two or more windows
   show **window-count dots** under their icon (one dot per window, at most 4). That way you
   know before letting go which apps will ask you to pick.
2. **Release on a single-window app.** The switch happens natively. BetterTab stays out of it.
3. **Release on an app with two or more windows.** The switch does **not** happen yet. The
   switcher stays on screen, and the **window list** opens directly above the highlighted icon.
   The app you started from is still in front.
4. **Pick.** Press a window's letter: that exact window comes to the front as the key window, and
   the switcher and list close together.
5. **Or back out.** Esc closes everything, and you're where you started, with nothing changed.

### The window list

- Up to **9 windows**, labelled **A S D F G H J K L** (the home row, left to right).
  - **A** is the app's frontmost window, the one plain ⌘⇥ would have given you, and its row is
    highlighted.
  - After it come the app's other windows, most recently used first, then minimized windows.
    Windows on other Spaces and full-screen windows are listed like any other.
  - With more than 9 windows, the list ends with a line such as "+3 more", which can't be picked.
- Letters restart at A for every app: Chrome with 3 windows gets A S D, Terminal with 2 gets A S.
- Each row shows its letter badge, its title on one line (cut off at the end if too long), and a
  marker if the window is minimized.
  - A window with no title is shown as "Untitled".
  - Two windows with the same title are both listed; their letters tell them apart.
- Nothing else is shown: no thumbnails, no favicons, no colour squares. Real window data has no
  source for them.
- The list sits above the highlighted icon, centred on it, kept within the switcher's width and
  inside the screen. It opens instantly on release; the animation is at most 150 ms.
- It follows the system: light or dark appearance, the user's accent colour for the highlighted
  row, and system materials.

### Keys while the list is open

| Key | What happens |
|---|---|
| **A–L** (as listed) | Opens that window. A letter with no window next to it does nothing. |
| **↑ / ↓** | Moves the highlight. |
| **Return** | Opens the highlighted window. |
| **Esc** | Cancels the whole switch: you stay in the app you started from. |
| **⌘⇥** again | Closes the list and goes back to cycling, with the next app highlighted. Releasing ⌘ then follows the flow again. |
| **⌘** pressed and released | Cancels, like Esc. It's also the way out if anything ever seems stuck. |
| **Anything else** | Does nothing. The list keeps the keyboard until you pick or cancel. |

Letters are matched by **physical key position**, not by the character typed, and each badge is
labelled with what the user's keyboard layout prints on that key. On AZERTY the first key is
therefore labelled Q. **Mouse:** the list doesn't take the mouse. Experiment test 0 showed that
any click, even one on BetterTab's own panel, closes the held-open native switcher. So clicks pass
through the list, and a click anywhere ends the switch: the switcher and the list close together,
nothing is picked, and the click lands on whatever is under the pointer.

### Edge cases

- **Which windows count:** standard windows on every Space, including full-screen windows,
  minimized windows and the windows of hidden apps. Dialogs, palettes, sheets and background tabs
  don't count; an app's tabs are one window, as ⌘\` treats them. (Changed 2026-09-29: the first live
  run showed that listing only the current Space finds nothing for someone who keeps windows
  full-screen.)
- **A window on another Space:** picking it switches to that Space, with macOS's usual slide.
- **The app quits or loses windows while the list is open:** the list refreshes. If one window or
  none is left, BetterTab switches to the app natively (or cancels if the app is gone).
- **A quick ⌘⇥ tap** stays native when ⌘ is released before BetterTab has read the highlighted
  app's windows. The switcher takes about 150–210 ms to appear to Accessibility, so only a tap
  faster than roughly a quarter of a second is affected. Otherwise the flow is the same however
  fast you type.
- **You walk away:** after **15 s** with no key pressed, the switch is cancelled, as if you'd
  pressed Esc.
- **Picking A** gives exactly what native ⌘⇥ would have. BetterTab doesn't focus anything
  itself for A.

## States

```
Idle ──⌘⇥──► Cycling (native switcher; dots drawn)
                │ ⌘ released, highlighted app has ≤ 1 window ───────────► native switch ─► Idle
                │ ⌘ released, highlighted app has ≥ 2 windows
                ▼
             Picking (switcher held open, list shown, highlight = A)
                ├─ letter / Return ─► open that window ──────────────────────────────► Idle
                ├─ Esc, or 15 s with no key ─► cancel, stay where you were ─────────► Idle
                └─ ⌘⇥ ─► list closes, highlight moves on ─► Cycling
```

When idle, BetterTab uses no CPU. It has no timers and does no polling, only the key tap.

## The menu-bar item

This is the only UI besides the dots and the list. It shows a template icon, and the menu has:

- **A status line:** "Active", "Needs Accessibility permission", or "Can't find the ⌘⇥
  switcher". The last one appears when BetterTab has failed to find it three times in a row.
- **Grant Accessibility…**, shown only when the permission is missing. It triggers the system
  prompt and opens System Settings at Privacy & Security → Accessibility.
- **Launch at Login**, a checkmark toggle using `SMAppService`.
- **Quit BetterTab.**

There's no Dock icon and no windows. Quit is the off switch.

## Permissions and first launch

- **Accessibility is the only permission.** The key tap doesn't need Input Monitoring (confirmed
  live on 2026-09-29). On macOS 27 the pane is titled "Device Control and Data Access".
- **First launch without the permission:** only the menu-bar item appears, in its
  needs-permission state, and ⌘⇥ is plain native. There's no onboarding window.
- **When the permission is granted,** BetterTab notices within 2 s, without a restart. **When
  it's revoked,** BetterTab goes back to the needs-permission state. ⌘⇥ keeps working natively
  throughout.

## Privacy

BetterTab has no network code, analytics or crash reporting, and saves nothing to disk apart from
the Launch at Login state. Window titles are held in memory only while the switcher is open, and
are never logged. Release builds log counts and states only.

## Performance targets

| What | Target |
|---|---|
| List visible after releasing ⌘ | within one frame; window lists are read while the app is highlighted, before you let go |
| Dots drawn after the switcher appears | under 100 ms. All apps are read in parallel, and AX calls time out at 250 ms each, so a hung app just gets no dots |
| The chosen window in front after a key press | under 100 ms on the current Space; another Space adds macOS's slide |
| Idle CPU | 0% |
| Memory | under 30 MB |

## Constants

These are hard-coded, with no settings UI.

| Constant | Value |
|---|---|
| Letters | A S D F G H J K L (physical home-row keys) |
| Maximum windows listed | 9 |
| Maximum dots per icon | 4 |
| AX messaging timeout | 250 ms |
| Cancel after no input | 15 s |
| Permission re-check while missing | every 2 s |

## Out of scope

These aren't "later"; they're **no**, unless daily use proves otherwise:
- thumbnails or previews (they would need Screen Recording);
- closing, minimizing or moving windows from the list;
- Chrome tabs;
- a separate shortcut, or a second mode;
- a settings window, and per-app exclusion lists;
- Dock previews;
- distribution: signing for other people, notarization, automatic updates.

## Acceptance tests

Run these by hand on macOS 27 before calling the MVP done. "Chrome ×3" means three Chrome windows
on the current Space.

1. **Single window.** ⌘⇥ to Notes (one window) and release: a native switch, with no list.
2. **Dots.** While cycling, Chrome ×3 shows 3 dots, Terminal ×2 shows 2, and Notes shows none.
3. **The list opens.** Release on Chrome ×3. The switcher stays, the list shows A S D above
   Chrome with A highlighted, and the previous app is still in front.
4. **Pick.** Press S. Chrome's second window is in front and key, and typing goes into it. Note
   whether any other Chrome window flashes up first.
5. **Most recent.** Press A, or Return: you get Chrome's most recent window, as native would.
6. **Arrows.** Press ↓ ↓ then Return: window 3.
7. **Cancel.** Press Esc. Everything closes, the previous app is still in front, and nothing has
   changed.
8. **Back to cycling.** With the list open, press ⌘⇥. The list closes and the next app is
   highlighted. Release on Terminal ×2: the list shows A S.
9. **Minimized.** Pick a minimized window: it's restored and focused.
10. **Hidden app.** Pick window S of a hidden (⌘H) app: the app unhides and that window is in
    front.
11. **Many windows.** With 11 windows, the list shows A–L plus "+2 more".
12. **Keyboard layout.** On a non-US layout, the badges show what that layout prints, and the
    home-row keys pick windows.
13. **No stuck ⌘.** After a pick, a cancel and a timeout, type into TextEdit each time: you get
    plain letters, not ⌘-shortcuts.
14. **Crash during Picking.** `kill -9` BetterTab while the list is open, then press and release
    ⌘. The switcher closes and ⌘⇥ works normally afterwards.
15. **Timeout.** Leave the list open for 15 s: it cancels.
16. **Quick tap.** Tap ⌘⇥ quickly onto Chrome ×2: the list opens, or the switch stays native if the
    experiment ruled that out.
17. **Second display.** With the switcher on the other display, the dots and list appear there.
18. **Permission.** Revoke Accessibility: the status says so and ⌘⇥ is native. Grant it: active
    again within 2 s.
19. **Idle.** With the switcher closed for a minute, Activity Monitor shows 0% CPU.
20. **Other Spaces.** With one Chrome window on Desktop 1 and two full-screen, Chrome shows 3 dots
    and the list shows all three. Picking a full-screen one switches to its Space, and typing goes
    into it.
