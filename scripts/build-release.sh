#!/bin/bash
# Builds BetterTab (Release) and zips it into build/release/BetterTab-<version>.zip.
#
#   scripts/build-release.sh <version> <build> [signing identity]
#
# The arguments can also come from VERSION, BUILD_NUMBER and SIGNING_IDENTITY.
# With an identity, the app is signed with it for team 5KDU5HYH35. Without one, it's ad-hoc.
set -euo pipefail

version=${1:-${VERSION:-}}
build=${2:-${BUILD_NUMBER:-}}
identity=${3:-${SIGNING_IDENTITY:-}}
[[ -n $version && -n $build ]] || { echo "usage: $0 <version> <build> [signing identity]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
derived=$root/build/release-DerivedData
out=$root/build/release
app=$derived/Build/Products/Release/BetterTab.app
zip=$out/BetterTab-$version.zip
log=$out/build.log

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
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

echo "$zip"
shasum -a 256 "$zip" | cut -d ' ' -f 1
