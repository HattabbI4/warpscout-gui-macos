#!/bin/bash
# CI and local contributors use an isolated signing key and never touch the release ZIP.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/source"
cp -R Sources Resources scripts Tests tools "$work/source/"
cd "$work/source"
cache="${TMPDIR:-/tmp}/warpscout-swift-cache"
rm Resources/UpdatePublicKey
swift -module-cache-path "$cache" tools/release-sign.swift init "$work/ci.key" Resources/UpdatePublicKey
WARPSCOUT_SIGNING_KEY="$work/ci.key" ./scripts/build.sh

compile() {
    swiftc -parse-as-library -target "$(uname -m)-apple-macosx26.0" -module-cache-path "$cache" "$@"
}
compile Sources/Core.swift Tests/ScanActions.swift -o "$work/scan-tests"
"$work/scan-tests"
mkdir "$work/core"
printf '#!/bin/sh\nprintf "0.17.0\\n"\n' > "$work/core/warpscout"
chmod +x "$work/core/warpscout"
tar -czf "$work/core.tar.gz" -C "$work/core" warpscout
compile Sources/{Core,Updates}.swift Tests/CoreUpdate.swift -o "$work/update-tests"
"$work/update-tests" "$work/core.tar.gz"
compile Sources/{Core,Updates}.swift Tests/Integration.swift -o "$work/integration"
if [[ "${WARPSCOUT_LIVE_TEST:-0}" == 1 ]]; then
    mkdir -m 700 "$work/live"
    for proto in awg31 awg wg masque masque-h2; do
        "$work/integration" --download "$work/live" "$proto"
    done
fi
./scripts/test-distribution.sh
