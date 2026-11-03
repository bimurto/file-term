#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project FileTerm.xcodeproj -scheme FileTerm -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/release -quiet build

rm -rf .build/dmg
mkdir .build/dmg
cp -R .build/release/Build/Products/Release/FileTerm.app .build/dmg/
ln -s /Applications .build/dmg/Applications

# hdiutil sometimes fails with "Resource busy" on build machines; a retry is enough.
for attempt in 1 2 3; do
  if hdiutil create -volname FileTerm -srcfolder .build/dmg -ov -format UDZO -quiet .build/FileTerm.dmg; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    exit 1
  fi
  sleep 5
done
rm -rf .build/dmg
printf 'Created .build/FileTerm.dmg\n'
