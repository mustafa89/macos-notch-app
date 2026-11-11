#!/bin/bash
# Renders the README images into docs/ (or the folder given) with sample data: no window, no
# screen capture, no camera, and the real note file is never read.
set -euo pipefail
cd "$(dirname "$0")/.."
bin=$(mktemp -d)/render
sources=$(ls Sources/NotchSwitcher/*.swift | grep -v '/main.swift$')
# shellcheck disable=SC2086
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 $sources tools/render/main.swift -o "$bin"
mkdir -p "${1:-docs}"
"$bin" "${1:-docs}"
