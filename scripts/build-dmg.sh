#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'DMG packaging requires macOS and Xcode Command Line Tools.' >&2
  exit 1
fi
arch="$(uname -m)"
case "$arch" in
  arm64) node_arch=arm64 ;;
  x86_64) node_arch=x64 ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
version="$(node -p 'require("./package.json").version')"
node_version=24.22.1
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
archive="node-v${node_version}-darwin-${node_arch}.tar.gz"
curl -fSL --retry 3 "https://nodejs.org/dist/v${node_version}/${archive}" -o "$temp_dir/$archive"
curl -fSL --retry 3 "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt" -o "$temp_dir/SHASUMS256.txt"
(cd "$temp_dir"; awk -v name="$archive" '$2 == name' SHASUMS256.txt > selected.sha256; test -s selected.sha256; shasum -a 256 -c selected.sha256)
tar -xzf "$temp_dir/$archive" -C "$temp_dir"
export PATH="$temp_dir/node-v${node_version}-darwin-${node_arch}/bin:$PATH"
npm ci
PERKRADAR_DESKTOP=1 DISABLE_SCHEDULER=1 npm run build
app="$temp_dir/image/PerkRadar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/server" dist
cp -R .next/standalone/. "$app/Contents/Resources/server/"
mkdir -p "$app/Contents/Resources/server/.next"
cp -R .next/static "$app/Contents/Resources/server/.next/static"
cp -R public "$app/Contents/Resources/server/public"
mv "$temp_dir/node-v${node_version}-darwin-${node_arch}" "$app/Contents/Resources/node"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PerkRadar</string>
<key>CFBundleIdentifier</key><string>com.perkradar.desktop</string>
<key>CFBundleName</key><string>PerkRadar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.5</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
MACOSX_DEPLOYMENT_TARGET=13.5 xcrun swiftc desktop/main.swift -o "$app/Contents/MacOS/PerkRadar" -framework AppKit -framework WebKit
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app/Contents/Resources/node/bin/node"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$temp_dir/image/Applications"
dmg="dist/PerkRadar-${version}-${arch}.dmg"
hdiutil create -volname PerkRadar -srcfolder "$temp_dir/image" -ov -format UDZO "$dmg"
hdiutil verify "$dmg"
shasum -a 256 "$dmg" > "$dmg.sha256"
echo "Built $dmg"
