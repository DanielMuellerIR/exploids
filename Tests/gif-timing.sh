#!/bin/bash
# Den echten Encoder ohne SpriteKit unabhängig mit ImageIO zurücklesen.
set -euo pipefail
cd "$(dirname "$0")/.."
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
swiftc Sources/ExploidsMac/GIFEncoder.swift Tests/GIFTiming.swift -o "$probe/test"
"$probe/test" "$probe"
