# BetterTab: releasing

Every push to `main` publishes a GitHub Release. If several pushes queue up while one is building,
only the newest of them runs. The workflow is `.github/workflows/release.yml`, and it builds with
`scripts/build-release.sh`. Written 2026-09-30.

## How a release happens

1. You merge `dev` into `main` and push.
2. GitHub Actions builds the Release configuration on the `xcode-27` runner, zips `BetterTab.app`
   and publishes it as `v<version>`, with the release notes GitHub generates.
3. If that version's tag already exists, the run does nothing. To run it again by hand, use
   Actions → Release → Run workflow, on `main`. It refuses any other branch.

Releases aren't notarized, so on first launch users click Open Anyway in System Settings →
Privacy & Security.

## Versions

A version is `MARKETING_VERSION` plus the number of commits on `main`: `0.1.87` means
`MARKETING_VERSION = 0.1` at the 87th commit. The build number (`CFBundleVersion`) is the commit
count alone. For a new minor, bump `MARKETING_VERSION` in the BetterTab target's Build Settings.
The last part is automatic and never resets.

To build a release zip locally: `scripts/build-release.sh 0.1.87 87`. That's ad-hoc; pass an
identity (`security find-identity -v -p codesigning` lists them) as a third argument to sign it.

## Signing with your certificate

Without the two secrets below, releases are signed ad-hoc. An ad-hoc build's designated
requirement is its cdhash, so every update loses the Accessibility grant, while a
certificate-signed one keeps it. To sign releases with your Apple Development certificate:
1. In Keychain Access → My Certificates, right-click **Apple Development: …** → Export. Save it as
   `cert.p12` (Personal Information Exchange) and set a password.
2. `base64 -i cert.p12 | pbcopy`, then `gh secret set SIGNING_CERT_P12` and paste.
3. `gh secret set SIGNING_CERT_PASSWORD` and type the password.
4. `rm cert.p12 && pbcopy < /dev/null`, which deletes the file and clears the clipboard.

The next release is signed. Each run's summary says whether it was signed or ad-hoc. When the
certificate expires and you renew it, repeat these steps.
