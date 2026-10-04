# Design brief: Window Switcher v8

Written on 2026-10-04 for Claude Design. Project: "Mac Window Switcher Prototype". Base:
`Window Switcher v7.dc.html`, which had first been brought up to date with v1.0.88 (no ⌘⇥ list,
stack edges as built, ⌘§ direction 3 only, the current menu). The maintainer judged the stack edges
on a screenshot of the real switcher as "kinda ugly and not really noticable". Claude Design built
three directions in `Window Switcher v8.dc.html`, with a spec sheet for each: A "Spine", B "Chips"
and C "Count". The maintainer chose A, with C as the fallback. A was built, and dropped on
offscreen renders ("nah lets do the count, this is shi"), so C is next (`docs/handoff.md`). This
brief is kept as the record of what was asked for.

---

Make **Window Switcher v8** as a new file, starting from `Window Switcher v7.dc.html`. Leave v7 as it is. v8 redesigns one thing, the **stack edges** on the ⌘⇥ switcher; everything else stays as in v7.

## The problem

The attached screenshot is the real macOS 27 ⌘⇥ switcher with v7's stack edges on it (Claude and Google Chrome have more than one window). The maintainer's verdict: "kinda ugly and not really noticeable".
- One edge is a 4 pt strip above a 103 pt icon. At that size, dark grey on light glass reads as a smudge or a misplaced shadow, not as a window behind the icon.
- On the highlighted icon, the edge runs into the highlight's top border.
- The real glass is far more transparent than v7's mock: the text behind it shows through, so anything thin and grey gets lost.

## The job

While cycling ⌘⇥, you should see at a glance which apps have more than one window, because those are the apps where ⌘§ has something to do. It has to be noticeable on every icon, not only the highlighted one, yet quieter than the icons themselves. It should look like part of macOS 27, not a sticker on top of it.

## Requirements

1. **The native switcher can't change:** not its icons, sizes, spacing, highlight, app name or glass. BetterTab draws on a transparent, click-through layer over the switcher's pill, and only inside the pill.
2. **Don't hide the icon.** Nothing may cover the icon's artwork beyond what a macOS badge does. Keep clear of the top-right corner, where macOS draws notification badges (Discord in the screenshot).
3. **Already tried and rejected:** dots under the icon (they read as the Dock's "running" dots and sat on the highlighted app's name), and a stack offset diagonally (it looked like a Copy icon).
4. **Any icon, either appearance.** macOS 27 icons share one rounded-square shape, but range from white (Chrome) to near-black (Terminal, Keychain Access) to saturated (Claude, Discord). The design has to work on all of them, in light and in dark.
5. **It scales with the icon.** The switcher shrinks its icons when many apps are open, so give every size as a share of the icon body's side, which is 103 pt at full size. The highlight is the body plus 8.5 pt on each side, and the pill has more room above and below the icons. A design may reach past the highlight into that room if it still looks right on the highlighted icon.
6. **No animation.** It appears within 100 ms of the switcher, when the window counts arrive, and stays still.
7. **What BetterTab knows:** each icon's frame; each app's window count (any number); which icon is highlighted (from accessibility notifications, so anything that follows the highlight may trail it by a frame); light or dark; the accent colour; and each app's icon image, so a design can use the icon's own colours. It can't see the screen, so nothing can sample what's behind the glass.
8. **Stay minimal.** No text labels and no tooltips. Today there are two levels: one edge for 2 windows, two edges for 3 or more. A design may show the exact count instead, but say why that's worth it.

## What to make

- **Three directions,** each a different idea rather than three tunings of one, plus "v7 (current)" for comparison. Add a "Stack edges" control to the prototype panel that switches between them.
- **A mock that's fair to judge them in:** make the ⌘⇥ glass match the screenshot (light and see-through, with a busy text window behind it). Give a multi-window app a notification badge. Include a white icon, a dark one and a saturated one, each with 2 and with 3 or more windows. Add a "Many apps" scenario where the switcher shrinks its icons.
- **For each direction,** a short table of its geometry and colours as shares of the body's side, for light and dark, so it can be built in code exactly. End with which direction you recommend, and why.
