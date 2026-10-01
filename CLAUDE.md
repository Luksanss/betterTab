# BetterTab

A macOS menu-bar utility. ⌘§ (the key above Tab on ISO keyboards) is ⌘⇥ for the front app's
windows, drawn by BetterTab itself, windows on other Spaces included. ⌘⇥ stays native: BetterTab
only draws stack edges behind the icons of apps with more than one window. Until 2026-10-01,
releasing ⌘⇥ on such an app opened a window list; that was removed (`docs/spec.md` § Out of
scope). See `docs/handoff.md` for where testing stands.

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
  own judgement. A push to `main` publishes a GitHub Release (`docs/releasing.md`).
- **Never commit on `main` directly.**
- **Archive a handoff only at a release,** meaning a merge of `dev` into `main`: copy
  `docs/handoff.md` to `docs/archive/handoffs/<ISO date>.md`, adding a topical suffix if the date
  is taken. If the maintainer merges through a GitHub pull request, the next `/handoff-update` on
  `dev` writes that archive. Between releases, `/handoff-update` rewrites `docs/handoff.md` in
  place and writes no archive.
- **The required check is a clean build of the BetterTab scheme,** Debug and Release, with no
  warnings in our code. There are no automated tests; `docs/spec.md` § Acceptance tests are run by
  hand. The `.noindex` suffix keeps the dev builds out of Spotlight, so the launcher doesn't list
  them.
  ```
  for c in Debug Release; do xcodebuild -project BetterTab.xcodeproj -scheme BetterTab -configuration $c -derivedDataPath build/DerivedData.noindex build | grep -E 'error|warning: |BUILD' ; done
  ```
- **The project is a plain Xcode project with synchronized folders.** Files added under
  `BetterTab/` join the target automatically, so `project.pbxproj` rarely needs editing.
- **Builds are signed with the maintainer's Apple Development certificate** (Personal Team
  `5KDU5HYH35`), so the Accessibility grant survives rebuilds. Only the maintainer can grant it;
  agents never change security settings. If signing ever fails for a new target or bundle ID, add
  `-allowProvisioningUpdates` once.
- **Debug builds have a self-test** that drives native ⌘⇥ under the stack edges, and ⌘§, with
  synthetic keys, and writes a report without titles. The app in front needs two or more windows
  (three for `windows-cycle`); scratch TextEdit documents work. Quit BetterTab first, then run
  `open -g build/DerivedData.noindex/Build/Products/Debug/BetterTab.app --args --self-test /abs/path/report.json`.
  It presses keys and switches Spaces for about a minute, so only run it when the maintainer isn't
  using the Mac, and never with the screen locked.

## Rules that are expensive to forget

- **Stay minimal.** DockDoor does this too, but it's bloated; that's why BetterTab exists. New
  features need a reason beyond "an alternative app has it".
- **Never swallow ⌘.** ⌘§ swallows § and the keys pressed while its switcher is up, but ⌘ passes
  both ways, so BetterTab can't leave ⌘ stuck. Holding the native switcher open meant hiding the
  ⌘ release from macOS; it was removed on 2026-10-01, so don't bring it back unasked.
- **Never turn off native ⌘⇥.** `CGSSetSymbolicHotKeyEnabled` lasts after the app exits
  (`docs/architecture.md` § Route A+, removed).
- **Don't copy code from AltTab or DockDoor.** Both are GPL-3.0; read them to learn the approach.
  WindowLens is MIT, so it can be reused as long as its copyright notice is kept.
- **Agents never push or open pull requests.** The maintainer does.
