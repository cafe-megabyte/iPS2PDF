#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
source_font="${1:?Usage: install_private_signature_font.sh /path/to/SignatureFont.otf}"
destination="$root/BundledResources/Signature/SignatureFont.otf"

"$root/Scripts/validate_signature_font.py" "$source_font"
/bin/mkdir -p "$(dirname "$destination")"
/usr/bin/install -m 0600 "$source_font" "$destination"
echo "Installed ignored private signature font at $destination"
