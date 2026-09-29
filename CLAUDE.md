# BetterTab

A macOS menu-bar utility. Release ⌘⇥ on an app with more than one window, and instead of
switching, the switcher stays open and lists that app's windows. Press A, S, D… to pick one.
Nothing is built yet.

## Start here

Read `docs/handoff.md` first. It has the current state, the next action, the decisions already
settled and the findings behind them. It's verified against git by `/handoff` and rewritten by
`/handoff-update`; both skills live in `.claude/skills/`. Then read:
- `docs/spec.md`: exactly what the app does. It's the source of truth for behaviour and scope.
- `docs/product.md`: why the app exists.
- `docs/architecture.md`: how it's built on macOS.

## Branches, commits and handoffs

One developer, one user, so keep it simple.
- **Work happens on `dev`.** Commit straight to it, with no feature branches. Use Conventional
  Commits and no AI attribution.
- **`main` is the last working version.** It moves only when the maintainer says a version works.
  Then merge `dev` into `main` (`git switch main && git merge --no-ff dev`). Never do this on your
  own judgement.
- **Never commit on `main` directly.**
- **Archive a handoff only at a release,** meaning a merge of `dev` into `main`: copy
  `docs/handoff.md` to `docs/archive/handoffs/<ISO date>.md`, adding a topical suffix if the date
  is taken. Between releases, `/handoff-update` rewrites `docs/handoff.md` in place and writes no
  archive.
- **No checks exist yet.** There's no build until the Xcode project lands. Its `xcodebuild`
  command then becomes the required check, recorded here.

## Rules that are expensive to forget

- **Stay minimal.** DockDoor does this too, but it's bloated; that's why BetterTab exists. New
  features need a reason beyond "an alternative app has it".
- **Never leave a ⌘ release swallowed.** Holding the native switcher open means hiding the ⌘
  release from macOS, so every way out must post a synthetic ⌘ release.
- **Don't turn off native ⌘⇥** unless route B has been chosen and recorded in the handoff. Turning
  it off lasts after the app exits. See `docs/handoff.md` § Safety constraints.
- **Don't copy code from AltTab or DockDoor.** Both are GPL-3.0; read them to learn the approach.
  WindowLens is MIT, so it can be reused as long as its copyright notice is kept.
- **Agents never push or open pull requests.** The maintainer does.
