# BetterTab

A ⌘⇥ for macOS that knows about windows.

On a Mac, ⌘⇥ switches between apps. If you have two Chrome windows open, it always takes you to
the one you used last, and there's no quick way to reach the other. BetterTab keeps the switcher
you already know. When you release ⌘ on an app with more than one window, the switcher stays open
and lists that app's windows. Press A, S, D… to go straight to the one you want.

**Status:** the idea has been validated and the design is being drafted. There's no code yet.
For personal use.

## Docs

- [`docs/spec.md`](docs/spec.md): exactly what BetterTab does, which keys do what, what's out
  of scope, and the acceptance tests.
- [`docs/product.md`](docs/product.md): the problem, the existing tools, and why this one is
  worth building.
- [`docs/architecture.md`](docs/architecture.md): how this has to work on macOS, which APIs and
  permissions it needs, the risks, and the spike that proves it can be built.
- [`docs/handoff.md`](docs/handoff.md): the current state and the next action, for whoever
  picks up the work next.

## Requirements (planned)

- macOS 27, Apple Silicon (the dev machine).
- Accessibility permission, which lets it read other apps' window titles and bring a chosen
  window to the front.
