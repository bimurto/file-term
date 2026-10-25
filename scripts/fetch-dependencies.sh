#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .build/tools .build/vendor

if [ ! -f .build/tools/xcodegen/bin/xcodegen ]; then
  curl --fail --location --retry 2 \
    https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip \
    --output .build/tools/xcodegen-2.44.1.zip
  printf '%s  %s\n' \
    a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73 \
    .build/tools/xcodegen-2.44.1.zip | shasum -a 256 --check
  unzip -q -o .build/tools/xcodegen-2.44.1.zip -d .build/tools
fi

if [ ! -f .build/vendor/Defaults/Package.swift ]; then
  git clone --depth 1 --branch v8.2.0 \
    https://github.com/sindresorhus/Defaults.git .build/vendor/Defaults
fi

if [ ! -f .build/vendor/Settings/Package.swift ]; then
  git clone --depth 1 --branch 3.1.1 \
    https://github.com/sindresorhus/Settings.git .build/vendor/Settings
fi

if [ ! -f .build/vendor/SwiftTerm/Package.swift ]; then
  git clone --depth 1 --branch v1.20.0 \
    https://github.com/migueldeicaza/SwiftTerm.git .build/vendor/SwiftTerm
fi

printf '\nDependencies ready. All downloaded files are inside this project’s .build folder.\n'
