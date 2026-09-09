#!/bin/bash

set -euo pipefail

source_root="$1"
destination="$2"

mkdir -p "$destination"
install -m 0644 \
    "$source_root/Sources/Targets/MacOSGhostscriptRuntime/GhostscriptRuntime.h" \
    "$source_root/Sources/Targets/MacOSGhostscriptRuntime/GhostscriptRuntimeBundleMarker.h" \
    "$source_root/Sources/Shared/GhostscriptRuntime/GhostscriptBridge/GhostscriptBridge.h" \
    "$destination"
