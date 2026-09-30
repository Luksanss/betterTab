# Design brief: Window Switcher v6

Written on 2026-09-30 for Claude Design. Project: "Mac Window Switcher Prototype". Base:
`Window Switcher v5.dc.html`. It adds a second shortcut, ⌘§, which the maintainer decided on
2026-09-30. Claude Design built all three directions as `Window Switcher v6.dc.html`; the
maintainer chose direction 3, window outlines, and `docs/spec.md` § ⌘§ now describes what was
built. This brief is kept as the record of what was asked for.

---

Make **Window Switcher v6** as a new file, starting from `Window Switcher v5.dc.html`. Keep
everything v5 has: the visual language, the desktop mock, the ⌥Tab stand-in for ⌘⇥ and its whole
flow, the window list, the menu-bar item and the prototype toggles. v6 adds one thing: a
**window switcher** for the app that's already in front.

One change to v5 itself: **the menu-bar item's icon is now the app's keycap labelled A,** not the
window in front of another, which looked like macOS's Screen Mirroring icon. It's a monochrome
template: a rounded-square key face, solid, with a geometric A cut out of it (two legs with round
ends and a crossbar), and the key's front showing as a 2.5 pt band below the face at 45% opacity.
The whole key is 15 × 16 pt. Use it in the mock menu bar.

## Why

Today, to get to another Chrome window while you're in Chrome, you press ⌘⇥, cycle through every
other app until Chrome is highlighted again, let go, and press S. The app you're in is the one
app ⌘⇥ makes hardest to reach. ⌘§ fixes that: it's ⌘⇥, but it cycles through the front app's
windows instead of through apps.

## The flow

It behaves exactly like ⌘⇥, but only for the front app's windows. These are requirements, not
suggestions.

1. **Hold ⌘ and press §** (the key above Tab on the maintainer's keyboard). The window switcher
   opens and shows the front app's windows, with the window you're in first. The highlight
   starts on the **second** window, the one you were in before, the way ⌘⇥ starts on the
   previous app.
2. **Press § again** to move the highlight to the next window, wrapping from the last to the
   first. **⇧§** moves it back. The arrow keys move it too.
3. **Release ⌘:** the highlighted window comes to the front, and the switcher closes.
4. **A quick ⌘§ tap** goes straight to the previous window, without the switcher flashing up, the
   way a quick ⌘⇥ flips to the previous app. With two Chrome windows, ⌘§ flips between them.
5. **Letters A S D F G H J K L,** pressed while ⌘ is still held, open that window at once. A is
   the window you're in.
6. **Esc,** with ⌘ still held, closes the switcher and changes nothing. Releasing ⌘ afterwards
   does nothing.
7. **Mouse:** hovering highlights a window and a click opens it, as in the native ⌘⇥ switcher.
8. **An app with one window or none:** ⌘§ does nothing and no switcher appears.
9. **There's no timeout.** The user is holding ⌘, and letting go ends it.

The prototype can't capture ⌘, so use **⌥§ as the stand-in**, just as ⌥Tab stands in for ⌘⇥.
Match the physical key by `event.code`, not by the character it types: the key above Tab is
`IntlBackslash` on an ISO Mac keyboard and `Backquote` on an ANSI one. Accept both.

## Which windows it lists

The same ones the ⌘⇥ list shows:
- the front app's standard windows on **every Space**, full-screen ones included;
- **most recently used first,** so the window you're in comes first, then minimized windows last,
  with v5's minimized marker (picking one restores it);
- **up to 9 windows,** labelled A–L, then v5's "+N more" footer, which can't be highlighted or
  picked;
- "Untitled" for a window with no title. Duplicate titles are both listed.

## What to design

macOS has no switcher for this, so BetterTab draws all of it. There's no ⌘⇥ icon row for it to
sit above, so it needs a shape and a place of its own.

**What the design can show.** For each window: its title, its app, its size and position on its
display, and whether it's full-screen or minimized. **There are no pictures of windows.** Those
need the Screen Recording permission, and BetterTab asks for Accessibility only. So no thumbnails,
and no blurred or faked previews either.

**The hard case is the maintainer's everyday one:** two Chrome windows, both full-screen. They're
the same shape and the same app, so only their titles tell them apart.

**Build all three directions below, each one complete, not a sketch:** the whole flow and every
scenario, in light and dark mode. Put them behind a prototype toggle, so each scenario can be
compared across all three, and say which one you'd pick and why:

1. **The list on its own.** v5's window list, centred on the screen, with a small header naming
   the app (its icon and name), since no switcher icon says which app this is. The most minimal.
2. **A panel shaped like the ⌘⇥ switcher.** The native switcher's material, corner radius and
   presence, with the app's icon large on one side and v5's rows beside or below it. ⌘⇥ and ⌘§
   then read as one family.
3. **Window outlines.** A row of tiles like ⌘⇥'s icons, but each tile is a window's outline drawn
   to its real proportions: a full-screen window has the display's shape, and a minimized one is
   dimmed. Each tile carries its letter badge. As in ⌘⇥, only the highlighted tile's title shows,
   under the row. It looks most like a switcher, but it has to pass the hard case, where the two
   outlines are identical.

Also decide whether the window you're in (row 1, or the first tile) needs any marking beyond
being first. The default is none.

For every direction:
- **wherever a direction has rows, keep v5's rows exactly as they are:** size, letter badge,
  title, minimized marker and accent-coloured highlight. The app draws both lists with the same
  code, and they should feel like one thing;
- **placement:** centred on the display that shows the front window, where macOS puts its own
  ⌘⇥ switcher;
- **light and dark mode,** the system accent colour for the highlight, and system materials, as
  in v5;
- **an opening animation of at most 150 ms,** like v5's list, or none at all, like the native
  switcher;
- **the "Show BetterTab layers" toggle** outlines the whole window switcher, because all of it
  is ours.

## Scenarios

Extend v5's scenario picker. Each scenario sets which app is in front on the desktop mock.

1. **Chrome ×2, both full-screen** (the default, and the hard case): a quick ⌥§ tap flips between
   the two windows.
2. **Chrome ×3.**
3. **Terminal ×5:** holding ⌥ and tapping § walks the highlight through them and wraps.
4. **Notes ×1:** ⌥§ does nothing.
5. **A list with one minimized window.**
6. **An app with 11 windows:** A–L plus "+2 more".
7. **An untitled window, and two identical titles.**
8. **A very long title.**

Use realistic titles. For Chrome, a window's title is its active tab's page title, such as
"Inbox (24) - Gmail". There are no URLs.

## Don't add

- thumbnails or previews of windows, real or faked, and favicons;
- a search field;
- a hint or legend naming the shortcut, and any onboarding;
- a setting to change the shortcut;
- window actions such as close or minimize;
- markers for windows on other Spaces (still undecided);
- switching apps from inside the window switcher.
