<img src="design/icon/AppIcon.png" width="128" alt="BetterTab's icon: a keycap labelled A">

# BetterTab

A ⌘⇥ for macOS that knows about windows.

⌘⇥ switches between apps, so with two Chrome windows open it always takes you to the one you used
last. BetterTab keeps the native switcher. Release ⌘ on an app with more than one window, and the
switcher stays open with a list of that app's windows. Press A, S, D… to go straight to one.

## Install

1. Download the zip from [the latest release](https://github.com/Luksanss/betterTab/releases/latest),
   unzip it, and move `BetterTab.app` to Applications.
2. Open it. The first time, macOS blocks it because it isn't notarized: go to System Settings →
   Privacy & Security and click Open Anyway.
3. When macOS asks, switch BetterTab on under Accessibility. It's the only permission it needs.

It needs macOS 27.

## Use

Hold ⌘ and press Tab as usual. Apps with more than one window show the edges of more windows
stacked behind their icon. Single-window apps switch natively.

| Key | What happens |
|---|---|
| **A, S, D…** | Opens that window |
| **↑ / ↓**, **Return** | Moves the highlight, and opens the highlighted window |
| **Esc**, or **⌘** pressed and released | Cancels |
| **⌘⇥** | Goes back to cycling |

The menu-bar item shows whether BetterTab is active and which version it is, and has Launch at
Login and Quit. There are no settings.

## Build

Open `BetterTab.xcodeproj`, choose your own team under Signing & Capabilities (a free Personal
Team works), and build the BetterTab scheme. Don't use "Sign to Run Locally": macOS would forget
the Accessibility grant on every rebuild.

## Privacy

No network code, analytics or crash reporting. Window titles stay in memory only while the
switcher is open, and are never logged.

## More

How it works, the spec and the tests are in [`docs/`](docs/). The window filter and the make-key
event follow [yabai](https://github.com/koekeishiya/yabai) (MIT). AltTab, DockDoor and WindowLens
were read to learn the approach; no code comes from them.
