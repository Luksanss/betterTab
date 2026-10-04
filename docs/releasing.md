# BetterTab: releasing

Every push to `main` publishes a GitHub Release. If several pushes queue up while one is building,
only the newest of them runs. The workflow is `.github/workflows/release.yml`, and it builds with
`scripts/build-release.sh`. Written 2026-09-30.

## How a release happens

1. You merge `dev` into `main` and push.
2. GitHub Actions builds the Release configuration on the `xcode-27` runner, packs `BetterTab.app`
   into a disk image (§ The disk image), signs it for Sparkle and writes the appcast (§ Updates),
   and publishes both as `v<version>`. The release notes are the `feat`, `fix` and `perf` commits
   since the last release.
3. If that version's tag already exists, the run does nothing. To run it again by hand, use
   Actions → Release → Run workflow, on `main`. It refuses any other branch.

Releases aren't notarized, so on first launch users click Open Anyway in System Settings →
Privacy & Security. After that they update from the app's menu (§ Updates).

## Versions

A version is `MARKETING_VERSION` plus the number of commits on `main`: `0.1.87` means
`MARKETING_VERSION = 0.1` at the 87th commit. The build number (`CFBundleVersion`) is the commit
count alone. For a new minor, bump `MARKETING_VERSION` in the BetterTab target's Build Settings.
The last part is automatic and never resets.

To build a release disk image locally: `scripts/build-release.sh 0.1.87 87`. It lands in
`build/release/`. That's ad-hoc; pass an identity (`security find-identity -v -p codesigning`
lists them) as a third argument to sign it.

## The disk image

`BetterTab-<version>.dmg` opens to one window: the app, a link to Applications, and a background
that says what to do. The background is drawn by `design/dmg/make-background.swift`
(`design/dmg/README.md`); the layout is `scripts/dmg-settings.py`.

- **[dmgbuild](https://github.com/dmgbuild/dmgbuild)** (MIT) writes the window's `.DS_Store`
  directly, without Finder, so it runs on CI. The script installs it into `build/dmgbuild` from
  `scripts/dmgbuild-requirements.txt`, pinned by hash, and needs Python 3.10 or later; macOS's
  own `/usr/bin/python3` is 3.9, so the workflow sets up Python first.
- **Finder's window bounds include its 32 pt title bar,** and the background is pinned below it.
  So the window is the picture's full 640 × 400 pt and its last 32 pt never show. Measured on a
  third-party installer on 2026-10-04.
- **Don't hide the `.app` extension in the image** (dmgbuild's `hide_extensions`). It sets a
  Finder flag on the bundle, and `codesign --verify --strict` then rejects the app. Finder hides
  it anyway.
- **macOS 27 says `hdiutil`'s `create`, `attach` and `convert` are deprecated** in favour of
  `diskutil image`. Those warnings come from dmgbuild and don't fail the build.
- **The image isn't signed or notarized,** like the app, so the first launch still needs Open
  Anyway. The image only changes how installing looks.

## Signing with your certificate

The workflow refuses to release without the two secrets below. An ad-hoc build's designated
requirement is its cdhash, so every update would lose the Accessibility grant, while a
certificate-signed one keeps it.

The exported certificate carries its private key, and whoever holds that key can sign an app that
Macs accept as BetterTab, Accessibility grant included. So it's kept where only the release job
can read it, and so is Sparkle's key (§ Updates):
- **The secrets live in the `release` environment,** which only `main` can use. Repository
  secrets would be readable by a workflow pushed to any branch. The job names the environment.
- **Actions are pinned by commit,** not by tag, because the key sits unlocked in the job's
  keychain while later steps run. dmgbuild is pinned by hash for the same reason.
- **The GitHub account has two-factor sign-in,** since anyone who can push can change the workflow.

To sign releases with your Apple Development certificate:
1. Once: on GitHub, Settings → Environments → New environment, named `release`. Under Deployment
   branches and tags choose Selected branches and tags, and add `main`.
2. In Keychain Access → My Certificates, right-click **Apple Development: …** → Export. Save it as
   `cert.p12` (Personal Information Exchange) with a long random password.
3. `base64 -i cert.p12 | gh secret set SIGNING_CERT_P12 --env release`. It goes in through the
   pipe, without the clipboard.
4. `gh secret set SIGNING_CERT_PASSWORD --env release`, and type the password when asked.
5. `rm cert.p12`.

The next release is signed. Each run's summary says whether it was signed or ad-hoc. When the
certificate expires (the current one on 2027-09-29) and you renew it, repeat steps 2–5.

## Updates

Check for Updates… in the app's menu installs the latest release through Sparkle
(`docs/spec.md` § Updates, `docs/architecture.md` § Updates). For that, every release carries:
- **The disk image, signed with Sparkle's EdDSA key.** The app holds the public half
  (`SUPublicEDKey` in `BetterTab/Info.plist`) and won't unpack an update without a matching
  signature. `scripts/make-appcast.sh` signs it with Sparkle's `sign_update`, then checks the
  signature against the public key in the app it just built (`scripts/check-update-signature.swift`),
  so a secret that doesn't match the app fails the release instead of every update.
- **`appcast.xml`,** the feed the app reads from the latest release: one item with the version,
  its notes in Markdown, the disk image's URL, length and signature, and macOS 27 as the minimum.
  `gh release create` uploads it with the disk image before the release goes live.

Sparkle's key is set up once, like the certificate. Sparkle's tools come with the package, under
`build/DerivedData.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/` after a build:
1. `generate_keys` creates the key in your login keychain and prints the public key, which goes in
   `SUPublicEDKey`. It isn't secret.
2. `generate_keys -x sparkle-key.txt`, then `gh secret set SPARKLE_ED_PRIVATE_KEY --env release <
   sparkle-key.txt`.
3. Keep a copy of `sparkle-key.txt` in a password manager, then `rm sparkle-key.txt`. A lost key
   can't be replaced: the apps in use only accept updates signed with it, so everyone would have
   to reinstall by hand once.

The workflow refuses to release without `SPARKLE_ED_PRIVATE_KEY`. Locally, after
`scripts/build-release.sh`, `scripts/make-appcast.sh <version> <build>` signs with the key in your
keychain and writes `build/release/appcast.xml` and `notes.md`.
