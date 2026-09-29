# Design brief: Window Switcher v5

Given to Claude Design on 2026-09-29. Project: "Mac Window Switcher Prototype". Base:
`Window Switcher v4.dc.html`. The behaviour it has to match is `docs/spec.md`.

---

Make **Window Switcher v5** as a new file, starting from `Window Switcher v4.dc.html`. Keep v4's
visual language, desktop mock, ⌥Tab stand-in for ⌘Tab, and the "Open switcher" button. v5 has to
match an engineering spec exactly, so the changes below are requirements, not suggestions.

## What's real and what's BetterTab

The icon row is **macOS's own ⌘⇥ switcher**. BetterTab doesn't restyle it; it only adds two
layers:
1. **window-count dots** under icons;
2. **the window list** above the highlighted icon.

So make the icon row look as close to the real macOS switcher as you can, not like a new design.
Add a small prototype toggle, **"Show BetterTab layers"**, that outlines the dots and the list,
so it's clear which parts we build.

## The flow (replaces v4's behaviour)

1. **Hold ⌥, press Tab to cycle apps.** Apps with 2 or more windows show dots under their icon:
   one per window, at most 4. Single-window apps show no dots.
2. **Release ⌥ on a single-window app:** the switcher closes and that app comes to the front.
   There's no list.
3. **Release ⌥ on an app with 2 or more windows:** the switcher **stays open** and the window list
   opens above the highlighted icon. **Nothing on the desktop changes yet.** The previous app is
   still in front.
4. **In the list:**
   - **A S D F G H J K L** open windows 1–9. Letters restart at A for every app: Chrome with 3
     windows gets A S D, Terminal with 2 gets A S.
   - **↑ / ↓** move the highlight, and **Return** opens the highlighted window.
   - **Esc** cancels everything: the switcher and list close and the desktop is unchanged.
   - **⌥Tab** closes the list and goes back to cycling, with the next app highlighted.
   - **Every other key does nothing.**
   - **Mouse:** hover highlights a row, and a click opens it.
5. **Opening a window:** the switcher and list close together, and that exact window is in front
   on the desktop mock.
6. **After 15 s without a key,** everything closes as if Esc were pressed. Show no countdown.

**Remove from v4:**
- Tab / ⇧Tab and ← / → cycling inside the list;
- Return in the app row;
- the "picker disappears" behaviour of the original idea.

## The window list

- **Row content:** a **letter badge**, the **window title** on one line (cut off at the end), and a
  **minimized marker** (dimmed title plus a small glyph) where it applies.
  - **Remove the coloured squares.** Real window data has no favicon or colour to show.
  - Moving the letter badge to the left edge is your call. The letter is what the user acts on.
- **Row A** is the app's most recent window and starts highlighted.
- **Up to 9 rows.** With more windows, add a footer row such as "+2 more", which can't be picked.
- **"Untitled"** for a window with no title. Two windows with the same title (for example two
  "New Tab") are both listed.
- **Keep v4's placement:** above the highlighted icon, centred on it, kept within the switcher's
  width, opening with v4's quick scale-and-fade (at most 150 ms).
- **The highlighted row uses the system accent colour, not a fixed blue.** Add a prototype toggle
  between Blue and one other accent (Graphite or Purple).
- **Add a full dark-mode variant** with a toggle. The materials, text and badges all adapt.

## Scenarios to include

Add a small scenario picker in the prototype chrome:
1. Chrome ×3 (the default);
2. Terminal ×2;
3. Notes ×1, where release switches straight away with no list;
4. a list with one minimized window;
5. an app with 11 windows (A–L plus "+2 more", and 4 dots);
6. an untitled window and two identical titles;
7. a very long title.

Use realistic titles. For Chrome, a window's title is its active tab's page title, e.g.
"Inbox (24) - Gmail". There are no URLs.

## Menu-bar item

Add BetterTab's status item to the mock menu bar: a monochrome template icon, which you design.
Clicking it opens a native-style menu:
- **A status line,** in one of three states: "Active", "Needs Accessibility permission", or
  "Can't find the ⌘⇥ switcher".
- **"Grant Accessibility…",** only in the needs-permission state.
- **"Launch at Login"** with a checkmark.
- **"Quit BetterTab".**

Add a toggle to preview the three states. Design it in light and dark mode.

## Don't add

Thumbnails, favicons, a search field, a settings window, extra modes or shortcuts, or window
actions (close, minimize).
