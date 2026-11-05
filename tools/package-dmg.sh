#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:?Pass an absolute path for the output DMG}
if [[ -n $(git status --porcelain) ]]; then
    printf 'Commit source changes before packaging so the included source matches the app.\n' >&2
    exit 1
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
build_flags=(--configuration release --disable-sandbox
    -Xswiftc -gnone -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
    -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
    -Xcc "-fdebug-prefix-map=$PWD=." -Xcc "-ffile-prefix-map=$PWD=.")
swift build "${build_flags[@]}"
products=$(swift build "${build_flags[@]}" --show-bin-path)
app="$scratch/OpenDuet.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift tools/generate-app-icon.swift "$scratch/OpenDuet.iconset" "$app/Contents/Resources/OpenDuetMark.png"
iconutil -c icns "$scratch/OpenDuet.iconset" -o "$app/Contents/Resources/OpenDuet.icns"
rm -r "$scratch/OpenDuet.iconset"
cp GUIDE.md LICENSE ThirdParty/Duetbar-LICENSE.txt "$app/Contents/Resources/"
cp INSTALL-AND-TEST.md "$scratch/Read Me.md"
cp VENDOR-FREE-TEST.md GUIDE.md HARDWARE-VALIDATION.md BETA-SCOPE.md CHANGELOG.md RELEASE-CHECKLIST.md RELEASE-VERIFICATION.md LICENSE "$scratch/"
git archive --format=zip --output="$scratch/OpenDuet-Source.zip" HEAD
git rev-parse HEAD > "$app/Contents/Resources/SourceRevision.txt"
cp "$products/openduet" "$products/openduet-identify" "$app/Contents/MacOS/"
# Linker debug-map records can retain absolute object paths even with source maps.
xcrun strip -S "$app/Contents/MacOS/openduet"
xcrun strip -S "$app/Contents/MacOS/openduet-identify"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>openduet</string>
<key>CFBundleIdentifier</key><string>org.openduet.experimental</string>
<key>CFBundleIconFile</key><string>OpenDuet</string>
<key>CFBundleName</key><string>OpenDuet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.28</string>
<key>CFBundleVersion</key><string>68</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
python3 tools/privacy-audit.py "$app" "$scratch/OpenDuet-Source.zip"
codesign --force --sign - "$app/Contents/MacOS/openduet-identify"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$scratch/Applications"
hdiutil create -volname 'OpenDuet Beta' -srcfolder "$scratch" -format UDZO "$destination"
hdiutil verify "$destination"

python3 - "$destination" <<'PYHASH'
from pathlib import Path
import hashlib
import sys
path = Path(sys.argv[1])
digest = hashlib.sha256(path.read_bytes()).hexdigest()
path.with_suffix(path.suffix + '.sha256').write_text(f'{digest}  {path.name}\n')
print('SHA-256 checksum written alongside the disk image.')
PYHASH
