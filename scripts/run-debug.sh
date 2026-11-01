#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project FileTerm.xcodeproj -scheme FileTerm -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build -quiet
open .build/xcode/Build/Products/Debug/FileTerm.app
