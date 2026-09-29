# BetterTab

A ⌘⇥ for macOS that knows about windows.

On a Mac, ⌘⇥ switches between apps. If you have two Chrome windows open, it always takes you to
the one you used last, and there's no quick way to reach the other. BetterTab keeps the switcher
you already know. When you release ⌘ on an app with more than one window, the switcher stays open
and lists that app's windows. Press A, S, D… to go straight to the one you want.

**Status:** it works, on one Mac. The first live run was on 2026-09-29. The self-test and the
hand-run acceptance tests in [`docs/spec.md`](docs/spec.md) are still to do. It's a personal
project with no releases, so you build it yourself.

## Using it

- Hold ⌘ and press Tab as usual. Apps with more than one window show a dot per window under their
  icon, up to 4.
- Release on an app with one window, and it switches natively. BetterTab stays out of it.
- Release on an app with more than one window, and the switcher stays. A list of that app's
  windows opens above its icon, labelled A S D F G H J K L. Windows on other Spaces and
  full-screen windows are listed too.

| Key | What happens |
|---|---|
| **A, S, D…** | Opens that window. |
| **↑ / ↓**, **Return** | Moves the highlight, and opens the highlighted window. |
| **Esc** | Cancels. You stay where you were. |
| **⌘⇥** | Closes the list and goes back to cycling. |
| **⌘** pressed and released | Cancels. It's also the way out if anything ever seems stuck. |

A click anywhere ends the switch, and after 15 s with no key pressed it cancels by itself. Letters
follow the physical keys, and each badge shows what your keyboard layout prints on that key.

The menu-bar item shows whether BetterTab is active, and has **Grant Accessibility…**, **Launch at
Login** and **Quit**. There's no settings window.

## Requirements

- macOS 27. It has only been tested on Apple Silicon.
- Xcode 27 to build it.
- Accessibility permission, which lets it read other apps' window titles and bring a chosen
  window to the front. It's the only permission BetterTab asks for: no Screen Recording, no Input
  Monitoring.

## Building

1. Open `BetterTab.xcodeproj`.
2. In the BetterTab target's Signing & Capabilities, choose your own team. A free Personal Team
   works. If Xcode says the bundle identifier isn't available, change that too.
3. Build the BetterTab scheme, open the app, and grant Accessibility from its menu.

From the command line:

```bash
xcodebuild -project BetterTab.xcodeproj -scheme BetterTab -configuration Release -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=<your team ID> -allowProvisioningUpdates build
```

```bash
open build/DerivedData/Build/Products/Release/BetterTab.app
```

Sign with a real certificate, not "Sign to Run Locally". An ad-hoc build's identity changes with
every rebuild, so macOS forgets the Accessibility grant each time.

## How it works

BetterTab doesn't replace the native switcher. When you release ⌘ on an app with more than one
window, it hides that release from macOS, so the switcher stays on screen. It reads the switcher
through Accessibility and draws its list on top. Every way out (a pick, a cancel, the timeout,
quitting) posts the ⌘ release it held back. It never turns native ⌘⇥ off.

Listing windows on every Space and focusing one specific window both need private macOS APIs, so
a macOS update can break them. The details are in [`docs/architecture.md`](docs/architecture.md).

## Privacy

BetterTab has no network code, analytics or crash reporting. It saves nothing apart from the
Launch at Login setting. Window titles are held in memory only while the switcher is open, and are
never logged.

## Docs

- [`docs/spec.md`](docs/spec.md): exactly what BetterTab does, which keys do what, what's out
  of scope, and the acceptance tests.
- [`docs/product.md`](docs/product.md): the problem, the existing tools, and why this one is
  worth building.
- [`docs/architecture.md`](docs/architecture.md): how it works on macOS, which APIs and
  permissions it needs, and the risks.
- [`docs/experiment.md`](docs/experiment.md): test 0, which proved the native switcher can be
  held open.
- [`docs/handoff.md`](docs/handoff.md): the current state and the next action, for whoever
  picks up the work next.

## Credits

The window filter and the event that makes a window key follow
[yabai](https://github.com/koekeishiya/yabai) (MIT). Its notice is kept in the files that use
them. [AltTab](https://github.com/lwouis/alt-tab-macos),
[DockDoor](https://github.com/ejbills/DockDoor) and
[WindowLens](https://github.com/FornaxChemica/WindowLens) were read to learn the approach; no code
comes from them.
