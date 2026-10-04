#!/bin/bash
# Signs the release disk image for Sparkle and writes what Check for Updates… reads, after
# scripts/build-release.sh has built it:
#   build/release/appcast.xml  the feed, published beside the disk image
#   build/release/notes.md     the release notes in it, which the GitHub release uses too
#
#   scripts/make-appcast.sh <version> <build> [< private-key]
#
# The arguments can also come from VERSION and BUILD_NUMBER. On CI the EdDSA private key comes on
# stdin, so it's never on a command line or in a file; run by hand with nothing piped in, it's
# read from the login keychain, where Sparkle's generate_keys put it. The signature is checked
# against the public key in the built app before anything is written.
set -euo pipefail

version=${1:-${VERSION:-}}
build=${2:-${BUILD_NUMBER:-}}
[[ -n $version && -n $build ]] || { echo "usage: $0 <version> <build> [< private-key]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
derived=$root/build/release-DerivedData.noindex
info=$derived/Build/Products/Release/BetterTab.app/Contents/Info.plist
sparkle=$derived/SourcePackages/artifacts/sparkle/Sparkle/bin
out=$root/build/release
dmg=$out/BetterTab-$version.dmg

[[ -f $dmg ]] || { echo "error: there's no $dmg; run scripts/build-release.sh first" >&2; exit 1; }

if [[ -t 0 ]]; then
  signature=$("$sparkle/sign_update" -p "$dmg")
else
  signature=$("$sparkle/sign_update" --ed-key-file - -p "$dmg")
fi
xcrun swift "$root/scripts/check-update-signature.swift" "$dmg" "$signature" "$info"
length=$(stat -f %z "$dmg")

# The app's feed is the latest release's appcast.xml, so this release's files sit beside it.
feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info")
releases=${feed%/latest/download/appcast.xml}
[[ $releases != "$feed" ]] || { echo "error: SUFeedURL isn't a GitHub latest-release URL: $feed" >&2; exit 1; }
url=$releases/download/v$version/BetterTab-$version.dmg
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")

# The notes are the feat, fix and perf commits since the last release, without their prefixes.
previous=$(git -C "$root" describe --tags --abbrev=0 --match 'v*' HEAD 2> /dev/null || true)
notes=$(git -C "$root" log --no-merges --reverse --format=%s ${previous:+"$previous..HEAD"} \
  | sed -nE 's/^(feat|fix|perf)(\([^)]*\))?!?: //p' \
  | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) }')
[[ -n $notes ]] || notes="- Changes behind the scenes only."
notes=${notes//]]>/]] >} # the one string CDATA can't hold
printf '%s\n' "$notes" > "$out/notes.md"

cat > "$out/appcast.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BetterTab</title>
    <item>
      <title>BetterTab $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$notes
]]></description>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$out/appcast.xml"

echo "$out/appcast.xml"
