# BetterTab: product

Working name, taken from the repo. A macOS menu-bar utility that gets you to the right window:
⌘§ switches between the front app's windows the way ⌘⇥ switches between apps, and the native ⌘⇥
switcher shows which apps have more than one window. Written 2026-09-29, before the build, and
revised on 2026-10-01, when the window list on ⌘⇥ was dropped, and on 2026-10-04, when updating
came into scope.

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
the native ⌘⇥, which was the core of the first idea. The maintainer has ruled DockDoor out as far too
bloated. **Being minimal is BetterTab's whole reason to exist:**
- a single-purpose app, with nothing else attached;
- window outlines and titles instead of thumbnails, so Accessibility is the only permission;
- one home-row letter per window, instead of hunting for it;
- offline unless you ask it to check for updates.

Any feature beyond `docs/spec.md` needs a reason. "DockDoor has it" is not a reason.

Worth building for personal use. As a business it's weak: two free apps are within a feature or
two of it.

The first version had one hard part the platform imposed: releasing ⌘ on the native switcher
switches straight away, and its window list needed it to wait. BetterTab hid the ⌘ release from
macOS so the switcher stayed open (`docs/architecture.md` § Route A+, removed). That's gone now.
What's still hard is focusing the right window reliably, especially on another Space.

## The interaction

**First, a window list on ⌘⇥ (2026-09-29).** Press ⌘⇥ as usual; apps with more than one window
show the edges of more windows stacked behind their icon. Release on one of those, and nothing
switched yet: the switcher stayed, and a list of that app's windows opened above its icon, each
with a home-row letter. Picking after release won over picking while holding ⌘, because the list
appeared only for apps with more than one window, and the stack edges said beforehand which apps
would ask.

**⌘§ for the app you're in (added 2026-09-30).** In daily use the maintainer found that the app
you're already in is the one ⌘⇥ makes hardest to reach: another Chrome window meant cycling through
every other app and back. ⌘§, with the key above Tab (\` on an ANSI keyboard), is ⌘⇥ for the front
app's windows: hold ⌘, § steps, releasing opens, and a quick tap flips to the previous window. It
fixes what ⌘` lacks: you see where you're going, and it reaches full-screen windows and other
Spaces. Each tile draws the window's outline on its display, because pictures would need Screen
Recording. The maintainer chose these outlines from three Claude Design directions.

**Then, native ⌘⇥ again (2026-10-01).** In daily use the list cost more than it saved: every ⌘⇥
onto an app with several windows became a decision about which one. Native ⌘⇥ needs no thought,
and when it lands on the wrong window, ⌘§ fixes it in a tap; the maintainer said ⌘§ "works super
well" for exactly that. So the list went, and ⌘⇥ is native. The stack edges stayed: they still
show which apps have more than one window, which is when ⌘§ has somewhere to go. Exact behaviour
is in `docs/spec.md`.

## Updates (added 2026-10-04)

Installing each release by hand meant deleting the old copy, dragging in the new one and granting
Accessibility again. The maintainer: "we value privacy, but updater is needed." So BetterTab
updates itself, but only when asked: Check for Updates… in the menu, which shows the new version
and installs it on a click. It never checks by itself, so it goes online only when you ask it to.
The repeated permission prompt is a separate problem with a separate fix: macOS keeps the grant
only when every release is signed with the same certificate (`docs/releasing.md`).

## Scope

The exact behaviour, what's out of scope, and the acceptance tests are in `docs/spec.md`. That
file is the source of truth; this one only records why.
