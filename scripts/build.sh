#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for arch in arm64 x86_64; do
    release="$work/$arch"
    app="$release/WarpScout.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    swiftc -O -swift-version 5 -parse-as-library -module-cache-path "${TMPDIR:-/tmp}/warpscout-swift-cache" -target "$arch-apple-macosx26.0" Sources/*.swift -o "$app/Contents/MacOS/WarpScout"
    test "$(lipo -archs "$app/Contents/MacOS/WarpScout")" = "$arch"
    cp Resources/Info.plist "$app/Contents/"
    cp -R Resources/FirstLaunch.html Resources/UpdatePublicKey Resources/GitHubMark.png Resources/WarpScout.icns Resources/*.lproj Resources/GUI-LICENSE "$app/Contents/Resources/"
    codesign -fs - "$app"
    codesign --verify --strict --deep "$app"
    cp Resources/FirstLaunch.html "$release/Первый запуск — Start Here.html"
    zip="$work/WarpScout-macOS-$arch.zip"
    ditto --norsrc --noextattr --noacl -c -k "$release" "$zip"
    if [[ -n "${WARPSCOUT_SIGNING_KEY:-}" ]]; then
        swift -module-cache-path "${TMPDIR:-/tmp}/warpscout-swift-cache" tools/release-sign.swift sign "$WARPSCOUT_SIGNING_KEY" "$zip"
    fi
done

rm -f dist/WarpScout-macOS{,-arm64,-x86_64}.zip.sig dist/WarpScout-macOS.zip
mv "$work"/WarpScout-macOS-*.zip dist/
if [[ -n "${WARPSCOUT_SIGNING_KEY:-}" ]]; then mv "$work"/WarpScout-macOS-*.zip.sig dist/; fi
# Keep the normal local launch path for the build machine.
rm -rf dist/WarpScout.app
mv "$work/$(uname -m)/WarpScout.app" dist/
