#!/bin/bash
set -e

# Dependencies required by Longhorn
DEPENDENCIES=(bash curl findmnt grep awk blkid lsblk)

echo "=== Checking and installing Longhorn dependencies ==="

# Install packages that provide the required tools
apt-get update -q
apt-get install -y \
  curl \
  util-linux \
  gawk \
  grep

echo ""
echo "=== Verifying all dependencies are present ==="

ALL_OK=true
for dep in "${DEPENDENCIES[@]}"; do
  if command -v "$dep" &>/dev/null; then
    echo "  [OK]  $dep"
  else
    echo "  [MISSING]  $dep"
    ALL_OK=false
  fi
done

echo ""
if [ "$ALL_OK" = true ]; then
  echo "All dependencies are installed and ready."
else
  echo "One or more dependencies are missing. Check the output above."
  exit 1
fi