#!/usr/bin/env bash
# Packages the built Linux bundle into a .deb and an AppImage.
# Run from the repo root after: flutter build linux --release
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(grep -oP '^version: \K[0-9]+\.[0-9]+\.[0-9]+' pubspec.yaml)"
fi
BUNDLE="build/linux/x64/release/bundle"
DIST="dist/linux"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

mkdir -p "$DIST"
rm -rf "$DIST/deb" "$DIST/AppDir"

# ---------------------------------------------------------------- .deb ----
DEB="$DIST/deb"
mkdir -p "$DEB/opt/mise" "$DEB/usr/bin" \
  "$DEB/usr/share/applications" \
  "$DEB/usr/share/icons/hicolor/256x256/apps" \
  "$DEB/usr/share/icons/hicolor/512x512/apps" \
  "$DEB/DEBIAN"

cp -r "$BUNDLE"/. "$DEB/opt/mise/"

cat > "$DEB/usr/bin/mise" <<'EOF'
#!/bin/sh
exec /opt/mise/file_organizer "$@"
EOF
chmod +x "$DEB/usr/bin/mise"

cat > "$DEB/usr/share/applications/mise.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Mise
Comment=Sort files into folders by type, size, or date
Exec=/usr/bin/mise %F
Icon=mise
Terminal=false
Categories=Utility;FileTools;
EOF

cp assets/icon/app_icon.png "$DEB/usr/share/icons/hicolor/256x256/apps/mise.png"
cp assets/icon/app_icon.png "$DEB/usr/share/icons/hicolor/512x512/apps/mise.png"

cat > "$DEB/DEBIAN/control" <<EOF
Package: mise
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Bezaleel Paul <bezaleel@users.noreply.github.com>
Depends: libgtk-3-0, libayatana-appindicator3-1, libnotify4
Description: Sort files into folders by type, size, or date.
 A cross-platform file organizer that sorts files into categorized
 subfolders by type, size, or date, with undo history and watch folders.
EOF

dpkg-deb --build --root-owner-group "$DEB" "$DIST/mise_${VERSION}_${ARCH}.deb"
echo "built $DIST/mise_${VERSION}_${ARCH}.deb"

# ------------------------------------------------------------ AppImage ----
APPIMAGE_DIR="$DIST/AppDir"
mkdir -p "$APPIMAGE_DIR/usr/bin"

cp -r "$BUNDLE"/. "$APPIMAGE_DIR/usr/bin/"

cat > "$APPIMAGE_DIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/file_organizer" "$@"
EOF
chmod +x "$APPIMAGE_DIR/AppRun"

cat > "$APPIMAGE_DIR/mise.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Mise
Comment=Sort files into folders by type, size, or date
Exec=mise
Icon=mise
Terminal=false
Categories=Utility;FileTools;
EOF
cp assets/icon/app_icon.png "$APPIMAGE_DIR/mise.png"

TOOL="$DIST/appimagetool-x86_64.AppImage"
if [ ! -f "$TOOL" ]; then
  curl -L -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
  chmod +x "$TOOL"
fi

ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPIMAGE_DIR" \
  "$DIST/Mise-${VERSION}-x86_64.AppImage"
echo "built $DIST/Mise-${VERSION}-x86_64.AppImage"
