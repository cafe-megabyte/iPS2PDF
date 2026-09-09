#!/bin/bash

set -euo pipefail

root="${SRCROOT:?SRCROOT is required}"
destination="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?resource path is required}/SignatureFont.otf"
public_font="$root/BundledResources/Signature/SignatureFont-Dummy.otf"
private_font="$root/BundledResources/Signature/SignatureFont.otf"

"$root/Scripts/validate_signature_font.py" --public-dummy "$public_font"

if [[ -s "$private_font" ]]; then
    "$root/Scripts/validate_signature_font.py" "$private_font"
    source_font="$private_font"
else
    source_font="$public_font"
fi

/usr/bin/install -m 0644 "$source_font" "$destination"
/usr/bin/xattr -c "$destination" 2>/dev/null || true
