#!/usr/bin/env bash
# Builds a release and zips it for the platform this runs on.
# Linux → strathvision-linux-x64.zip, macOS → strathvision-macos.zip.
# (Windows: see docs/DISTRIBUTION.md for the PowerShell equivalent.)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
case "$(uname -s)" in
  Linux)
    flutter build linux --release
    (cd build/linux/x64/release/bundle && zip -qr "../../../../../dist/strathvision-linux-x64.zip" .)
    echo "dist/strathvision-linux-x64.zip" ;;
  Darwin)
    flutter build macos --release
    ditto -c -k --keepParent build/macos/Build/Products/Release/strathvision.app dist/strathvision-macos.zip
    echo "dist/strathvision-macos.zip" ;;
  *) echo "Run on Linux or macOS (Windows: see docs/DISTRIBUTION.md)"; exit 1 ;;
esac
