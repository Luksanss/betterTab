# BetterTab: product

Working name, taken from the repo. A macOS menu-bar utility: a ⌘⇥ switcher that looks and feels
like the native one, but lets you pick a specific window when the app you land on has more than
one open. Written 2026-09-29, before the build.

## The problem

⌘⇥ switches between apps, not windows. If you switch to an app with several windows open (two
Chrome windows, three Finder windows), you always land on the one you used most recently. Getting
to any of the others takes a separate step.

What macOS already offers, and why it falls short:

- **⌘`** cycles through the front app's windows in order. You can't see where it's going, and
  which key it uses depends on the keyboard layout.
- **↓ / ↑ in the ⌘⇥ switcher** opens App Exposé for the highlighted app. It works, but it's a
  full-screen animated mode driven by arrow keys or the mouse, and few people know it exists.
- **The Window menu, right-clicking the Dock icon, Mission Control**: all mouse-first.

## Existing products

| Product | What it does | Why it doesn't cover this idea |
|---|---|---|
| [AltTab](https://github.com/lwouis/alt-tab-macos) (free, GPL-3.0) | Switcher over windows (a flat list, by default) or over apps | Grouping windows under their app and drilling in is [issue #337](https://github.com/lwouis/alt-tab-macos/issues/337), open since 2020-05-13 |
| [Witch](https://manytricks.com/witch/) ($14) | App, window and tab switcher with a list UI | Doesn't look or feel like the native ⌘⇥ |
| [GroupTab](https://apps.apple.com/app/grouptab/id6751125313) ($1.99, 2025) | Groups apps into rows on ⌥⇥ | Works on whole apps only, not windows |
| [DockDoor](https://github.com/ejbills/DockDoor) (free, GPL-3.0, macOS 14.5+) | Mainly Dock hover previews. It also has "Cmd+Tab enhancements": while the native switcher is up, it shows the highlighted app's window previews next to it, which you pick with arrows or a cycle key and confirm by releasing ⌘ | **Closest to this idea.** It's preview-first (thumbnails, so it needs Screen Recording) and part of a much larger app |
| [WindowLens](https://github.com/FornaxChemica/WindowLens) (free, MIT, macOS 26+) | Window switcher plus native ⌘⇥ previews, built the same way as DockDoor | Also preview-first, and also asks for Screen Recording |

**Verdict (revised 2026-09-29).** DockDoor and WindowLens already add a window picker on top of
the native ⌘⇥, which is the core of this idea. The maintainer has ruled DockDoor out as far too
bloated. **Being minimal is BetterTab's whole reason to exist:**
- a single-purpose app, with nothing else attached;
- window titles instead of thumbnails, so Accessibility is the only permission;
- one home-row letter per window, instead of hunting for it.

Any feature beyond `docs/spec.md` needs a reason. "DockDoor has it" is not a reason.

Worth building for personal use. As a business it's weak: two free apps are within a feature or
two of it.

The idea is simple. The platform makes one part hard: releasing ⌘ on the native switcher
switches straight away, and this flow needs it to wait. `docs/architecture.md` tries a trick first
(hiding the ⌘ release from macOS so its switcher stays open). If the trick fails, BetterTab draws
its own switcher. Either way, focusing the right window reliably is the other hard part. The window
list itself is the easy part.

## The interaction (decided 2026-09-29)

Press ⌘⇥ as usual. Apps with more than one window show the edges of more windows stacked behind
their icon. Release on a single-window app and it switches natively. Release on an app with two or more windows and
nothing switches yet: the switcher stays, and a list of that app's windows opens above its icon,
each with a home-row letter (A S D …). Press a letter to go to that window, or Esc to stay where
you were. Exact behaviour is in `docs/spec.md`.

**Why pick after release, not while holding ⌘.** Holding was considered: the window row would
show while ⌘ is still held, and releasing would confirm the most recent window. The maintainer
chose picking after release. The list only appears for apps with more than one window, so
choosing is an expected step, not a surprise. The stack edges show beforehand which apps will ask.
The accepted cost is one key press (A) even when the most recent window is the one you want.

**⌘§ for the app you're in (added 2026-09-30).** In daily use the maintainer found that the app
you're already in is the one ⌘⇥ makes hardest to reach: another Chrome window meant cycling
through every other app and back. ⌘§, the key above Tab on an ISO keyboard, is ⌘⇥ for the front
app's windows: hold ⌘, § steps, releasing opens, and a quick tap flips to the previous window. It
fixes what ⌘` lacks: you see where you're going, and it reaches full-screen windows and other
Spaces. Each tile draws the window's outline on its display, because pictures would need Screen
Recording. The maintainer chose these outlines from three Claude Design directions.

## Scope

The exact behaviour, what's out of scope, and the acceptance tests are in `docs/spec.md`. That
file is the source of truth; this one only records why.
