# BetterTab

A macOS menu-bar utility. Release ⌘⇥ on an app with more than one window, and instead of
switching, the switcher stays open and lists that app's windows. Press A, S, D… to pick one.
The whole flow is built, including windows on other Spaces, and the self-test passes. See
`docs/handoff.md` for where testing stands.

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
- **The required check is a clean build of both schemes,** Debug and Release, with no warnings in
  our code. There are no automated tests; `docs/spec.md` § Acceptance tests are run by hand.
  ```
  for s in BetterTab Experiment; do for c in Debug Release; do xcodebuild -project BetterTab.xcodeproj -scheme $s -configuration $c -derivedDataPath build/DerivedData build | grep -E 'error|warning: |BUILD' ; done; done
  ```
- **The project is a plain Xcode project with synchronized folders.** Files added under
  `BetterTab/` or `Experiment/` join their target automatically, so `project.pbxproj` rarely
  needs editing. `Experiment` is the throwaway target for `docs/architecture.md` § The experiment.
- **Builds are signed with the maintainer's Apple Development certificate** (Personal Team
  `5KDU5HYH35`), so the Accessibility grant survives rebuilds. Only the maintainer can grant it;
  agents never change security settings. If signing ever fails for a new target or bundle ID, add
  `-allowProvisioningUpdates` once.
- **Debug builds have a self-test** that drives ⌘⇥ end to end with synthetic keys and writes a
  report without titles. Quit BetterTab first, then run
  `open -g build/DerivedData/Build/Products/Debug/BetterTab.app --args --self-test /abs/path/report.json`
  (`--long` adds the 15 s timeout test). It presses keys and switches Spaces for about two minutes,
  so only run it when the maintainer isn't using the Mac, and never with the screen locked.

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
