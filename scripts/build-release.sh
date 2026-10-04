#!/bin/bash
# Builds BetterTab (Release) into a disk image, build/release/BetterTab-<version>.dmg: the app, a
# link to Applications, and the background from design/dmg/.
#
#   scripts/build-release.sh <version> <build> [signing identity]
#
# The arguments can also come from VERSION, BUILD_NUMBER and SIGNING_IDENTITY.
# With an identity, the app is signed with it for team 5KDU5HYH35. Without one, it's ad-hoc.
# Either way Xcode signs it, then this script signs the app again without get-task-allow (below).
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

# Xcode adds com.apple.security.get-task-allow to every build it signs with a development identity
# or ad hoc, Release included. It would let any process of the user's attach a debugger to BetterTab
# and act with its Accessibility grant, so the app is signed again with the same identity, the
# entitlements Xcode derived for it minus that one, and the hardened runtime.
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO would drop the other derived entitlements too.
#
# Inside out, but only the app needs it. The code nested in it is Sparkle's: the framework, which
# Xcode signed with the same identity, and the helpers inside it, which keep Sparkle's own
# signatures, as in every release so far. None of it has get-task-allow, which the check below
# makes sure of. Never --deep, which would sign Sparkle's helpers again with the app's entitlements.
# --timestamp=none, like Xcode's own signing with a development certificate: no trip to Apple.
entitlements=$out/BetterTab.entitlements
codesign -d --entitlements "$entitlements" --xml "$app" 2> /dev/null
options=(--force --sign "${identity:--}" --options runtime --timestamp=none)
if [[ -s $entitlements ]]; then
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$entitlements" > /dev/null 2>&1 || true
  [[ $(plutil -convert json -o - "$entitlements") == '{}' ]] || options+=(--entitlements "$entitlements")
fi
requirement=$(codesign -d -r- "$app" 2> /dev/null)
codesign "${options[@]}" "$app"
rm -f "$entitlements"

# The Accessibility grant follows the designated requirement, so every user would lose it if this
# changed it. An ad hoc one is the cdhash, which changes with any signature.
if [[ -n $identity && $(codesign -d -r- "$app" 2> /dev/null) != "$requirement" ]]; then
  echo "error: signing the app again changed its designated requirement" >&2
  exit 1
fi

codesign --verify --deep --strict "$app"

# What each piece of code in the app is signed with, and none may keep get-task-allow. Not the
# certificate's name: it holds an email address, and the workflow's logs are public.
while IFS= read -r -d '' code; do
  [[ $(file -b --mime-type "$code") == application/x-mach-binary* ]] || continue
  details=$(codesign -dv "$code" 2>&1)
  flags=$(sed -nE 's/^CodeDirectory .*flags=0x[0-9a-f]+\(([^)]*)\).*/\1/p' <<< "$details")
  echo "${code#"$app/"}"
  echo "  $(grep -E '^Identifier=' <<< "$details"), $(grep -E '^TeamIdentifier=' <<< "$details"), flags: $flags"
  granted=$(codesign -d --entitlements - --xml "$code" 2> /dev/null || true)
  if grep -qF '<key>com.apple.security.get-task-allow</key>' <<< "$granted"; then
    echo "error: ${code#"$app/"} still has get-task-allow" >&2
    exit 1
  fi
  if [[ $(plutil -convert json -o - - <<< "$granted" 2> /dev/null || echo '{}') == '{}' ]]; then
    echo "  entitlements: none"
  else
    echo "  entitlements:"
    plutil -p - <<< "$granted" | sed 's/^/    /'
  fi
done < <(find "$app" -type f -print0 | sort -z)

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
