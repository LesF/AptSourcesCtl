#!/bin/sh
# Build a binary .deb into the parent directory, then lint it.
set -eu
cd "$(dirname "$0")/.."
dpkg-buildpackage -us -uc -b "$@"
deb=$(ls -t ../aptsourcesctl_*.deb | head -1)
echo "Built: $deb"
if command -v lintian >/dev/null; then lintian -I "$deb" || true; fi
