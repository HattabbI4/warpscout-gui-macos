#!/bin/bash
# Requires a GUI session and an already signed release ZIP. Only the temporary host is replaced.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
app="$work/UpdateTest.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$work/test-home"
cleanup() {
    while IFS= read -r pid; do
        kill "$pid" 2>/dev/null || true
    done < <(ps -axo pid=,command= | awk -v exe="$app/Contents/MacOS/WarpScout" 'index($0,exe) && substr($0,index($0,exe)) == exe {print $1}')
    rm -rf "$work"
}
trap cleanup EXIT
for arch in arm64 x86_64; do
    zip="dist/WarpScout-macOS-$arch.zip"
    unpacked="$work/$arch"
    ditto -x -k "$zip" "$unpacked"
    cmp Resources/FirstLaunch.html "$unpacked/Первый запуск — Start Here.html"
    cmp Resources/FirstLaunch.html "$unpacked/WarpScout.app/Contents/Resources/FirstLaunch.html"
    cmp Resources/GUI-LICENSE "$unpacked/WarpScout.app/Contents/Resources/GUI-LICENSE"
    cmp Resources/UpdatePublicKey "$unpacked/WarpScout.app/Contents/Resources/UpdatePublicKey"
    bin="$unpacked/WarpScout.app/Contents/MacOS"
    test "$(find "$bin" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1
    test "$(lipo -archs "$bin/WarpScout")" = "$arch"
    codesign --verify --deep --strict "$unpacked/WarpScout.app"
    test -s "$zip.sig"
done
host_arch=$(uname -m)
native_zip="dist/WarpScout-macOS-$host_arch.zip"
echo "PASS both platform ZIPs, guides, code signatures and architecture slices"
managed="$work/test-home/Library/Application Support/WarpScout/warpscout"
if [[ "${WARPSCOUT_TEST_FIRST_LAUNCH:-0}" != 1 ]]; then
    mkdir -p "$(dirname "$managed")"
    printf '#!/bin/sh\necho 0.17.0\n' > "$managed"
    chmod +x "$managed"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
/usr/libexec/PlistBuddy -c 'Set CFBundleShortVersionString 0.0.0' "$app/Contents/Info.plist"
cp Resources/UpdatePublicKey "$app/Contents/Resources/"
swiftc -parse-as-library -module-cache-path "${TMPDIR:-/tmp}/warpscout-swift-cache" -target "$(uname -m)-apple-macosx26.0" Sources/Core.swift Sources/Updates.swift Tests/DistributionUpdate.swift -o "$work/distribution-test"
cp "$work/distribution-test" "$app/Contents/MacOS/WarpScout"
codesign -fs - "$app"
CFFIXED_USER_HOME="$work/test-home" "$app/Contents/MacOS/WarpScout" "$work/data" "$PWD/$native_zip" "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"
cmp "$app/Contents/MacOS/WarpScout" "$work/$host_arch/WarpScout.app/Contents/MacOS/WarpScout"
codesign --verify --deep --strict "$app"
swift -module-cache-path "${TMPDIR:-/tmp}/warpscout-swift-cache" - "$app" <<'SWIFT'
import AppKit
let url = URL(fileURLWithPath:CommandLine.arguments[1]).resolvingSymlinksInPath()
let end = Date().addingTimeInterval(15)
repeat {
    let app = NSRunningApplication.runningApplications(withBundleIdentifier:"local.warpscout.mac").first {
        $0.bundleURL?.resolvingSymlinksInPath().path == url.path
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
    if let app, app.isFinishedLaunching, windows.contains(where:{
        $0[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0
    }) { print("PASS installed WarpScout window is visible"); exit(0) }
    Thread.sleep(forTimeInterval:0.1)
} while Date() < end
exit(1)
SWIFT
if [[ "${WARPSCOUT_TEST_FIRST_LAUNCH:-0}" == 1 ]]; then
    for ((i=0; i<120; i++)); do
        [[ -x "$managed" ]] && break
        sleep 1
    done
    lipo "$managed" -verify_arch "$host_arch"
fi
core_version=$("$work/distribution-test" --core-version "$managed")
echo "PASS signed GUI installed and relaunched on $host_arch; managed core $core_version"
