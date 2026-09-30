# App icon

The app icon is `BetterTab/AppIcon.icon`, an Icon Composer document (`icon.json` plus one SVG per
layer). It's a home-row keycap labelled A, the key that picks a window: a white key with an indigo A
on an indigo gradient in light mode, a grey key with a white A on the system's dark background in
dark mode. The system derives the tinted and clear looks. (The first icon, a window in front of
another, looked too much like the Screen Mirroring icon.) Xcode compiles it into `Assets.car` and
`AppIcon.icns` because the BetterTab target sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
Don't edit the bundle by hand: change the numbers at the top of `make-icon.swift` (the keycap's
shapes, the letter, the brand colour) and regenerate it with `xcrun swift
design/icon/make-icon.swift` from the repo root. To preview it without opening any app, render it
with Icon Composer's command-line tool
(renditions `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`):

```
"$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool" \
  BetterTab/AppIcon.icon --export-image --output-file /tmp/AppIcon.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

`AppIcon.png` here is the `Default` rendition at 512 × 512, exported with the same command, for the
README and anywhere else outside the app. Export it again whenever the icon changes.

The menu-bar icon is the same keycap, drawn small in code by `BetterTab/App/StatusIcon.swift`: a
template image with the A cut out of a solid face and the key's front at 45% opacity. It copies the
shapes from `make-icon.swift` by hand, so change both together.
