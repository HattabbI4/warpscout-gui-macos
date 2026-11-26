#!/bin/bash
set -euo pipefail

previous=$(gh release list --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName // empty')
if [[ -z "$previous" ]]; then
    echo "First stable release. The distribution tests verified the initial key."
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for arch in arm64 x86_64; do
    zip="WarpScout-macOS-$arch.zip"
    echo "Checking $zip with the key shipped in $previous for $arch"
    gh release download "$previous" --pattern "$zip" --output "$work/$zip"
    # OpenSSL reads an Ed25519 SubjectPublicKeyInfo (RFC 8410). The app stores its raw 32-byte key.
    printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00' > "$work/public.der"
    unzip -p "$work/$zip" WarpScout.app/Contents/Resources/UpdatePublicKey >> "$work/public.der"
    test "$(wc -c < "$work/public.der")" -eq 44
    openssl pkeyutl -verify -pubin -keyform DER -inkey "$work/public.der" -rawin \
        -in "dist/$zip" -sigfile "dist/$zip.sig"
done
