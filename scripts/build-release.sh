#!/bin/bash
# Builds BetterTab (Release) into a disk image, build/release/BetterTab-<version>.dmg: the app, a
# link to Applications, and the background from design/dmg/.
#
#   scripts/build-release.sh <version> <build> [signing identity]
#
# The arguments can also come from VERSION, BUILD_NUMBER and SIGNING_IDENTITY.
# With an identity, the app is signed with it for team 5KDU5HYH35. Without one, it's ad-hoc.
# dmgbuild lays out the image's window; it's installed by hash into build/dmgbuild, with
# Python 3.10 or later.
set -euo pipefail

version=${1:-${VERSION:-}}
build=${2:-${BUILD_NUMBER:-}}
identity=${3:-${SIGNING_IDENTITY:-}}
[[ -n $version && -n $build ]] || { echo "usage: $0 <version> <build> [signing identity]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
derived=$root/build/release-DerivedData.noindex # .noindex keeps Spotlight from listing it
out=$root/build/release
app=$derived/Build/Products/Release/BetterTab.app
dmg=$out/BetterTab-$version.dmg
log=$out/build.log
venv=$root/build/dmgbuild
requirements=$root/scripts/dmgbuild-requirements.txt

if [[ -n $identity ]]; then
  signing=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" DEVELOPMENT_TEAM=5KDU5HYH35)
else
  signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

# Start clean, so every file compiles and every warning shows up.
rm -rf "$derived" "$out"
mkdir -p "$out"

xcodebuild -quiet -project "$root/BetterTab.xcodeproj" -scheme BetterTab -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  "${signing[@]}" PROVISIONING_PROFILE_SPECIFIER= \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build" \
  build 2>&1 | tee "$log"

# A warning in a file under the repo is ours, and a release doesn't ship with one.
if grep -F ': warning: ' "$log" | grep -F "$root/"; then
  echo "error: the build has warnings in our code (above)" >&2
  exit 1
fi

codesign --verify --deep --strict "$app"

# The venv outlives the clean above, and is rebuilt when the pinned requirements change.
if ! cmp -s "$requirements" "$venv/requirements.txt"; then
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
    || { echo "error: dmgbuild needs Python 3.10 or later, and python3 is $(python3 --version)" >&2; exit 1; }
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes -r "$requirements"
  cp "$requirements" "$venv/requirements.txt"
fi
"$venv/bin/dmgbuild" -s "$root/scripts/dmg-settings.py" \
  -D "app=$app" -D "background=$root/design/dmg/background.png" BetterTab "$dmg"

echo "$dmg"
shasum -a 256 "$dmg" | cut -d ' ' -f 1
