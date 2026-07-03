#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_FILE="$ROOT_DIR/config/packages.txt"
USB_DIR="$ROOT_DIR/usb/release-0.1"
REPO_DIR="$USB_DIR/repo"
META_DIR="$USB_DIR/metadata"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$REPO_DIR" "$META_DIR"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found"
  exit 1
fi

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  echo "dpkg-scanpackages not found. Install dpkg-dev."
  exit 1
fi

if ! command -v apt-rdepends >/dev/null 2>&1; then
  echo "apt-rdepends not found. Install apt-rdepends."
  exit 1
fi

mapfile -t packages < <(grep -vE '^\s*#|^\s*$' "$PKG_FILE" | sort -u)

{
  echo "Packages:"
  printf '%s\n' "${packages[@]}"
} > "$META_DIR/manifest.txt"

echo "Downloading packages..."
(
  cd "$TMP_DIR"
  apt-get update -y >/dev/null

  for pkg in "${packages[@]}"; do
    echo "  - $pkg"
    mapfile -t deps < <(
      apt-rdepends "$pkg" 2>/dev/null |
        awk '
          /^[[:alnum:]][[:alnum:]+.-]*$/ { print $1 }
        ' |
        sort -u
    )

    for dep in "${deps[@]}"; do
      if apt-cache show "$dep" >/dev/null 2>&1; then
        apt-get download "$dep" || true
      fi
    done

    if apt-cache show "$pkg" >/dev/null 2>&1; then
      apt-get download "$pkg" || true
    fi
  done
)

shopt -s nullglob
for deb in "$TMP_DIR"/*.deb; do
  cp -n "$deb" "$REPO_DIR/"
done

echo "Building repo metadata..."
(
  cd "$REPO_DIR"
  dpkg-scanpackages . /dev/null > Packages
  gzip -kf Packages
  {
    echo "Origin: usb-release-0.1"
    echo "Label: usb-release-0.1"
    echo "Suite: release-0.1"
    echo "Codename: release-0.1"
    echo "Architectures: amd64"
    echo "Components: main"
  } > Release
)

cp "$PKG_FILE" "$META_DIR/packages.txt"

echo "Done."
echo "Repo: $REPO_DIR"
echo "Metadata: $META_DIR"