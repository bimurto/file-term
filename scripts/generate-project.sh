#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

generator=.build/tools/xcodegen/bin/xcodegen
if [ ! -x "$generator" ] || [ ! -f .build/vendor/Defaults/Package.swift ] || [ ! -f .build/vendor/Settings/Package.swift ]; then
  printf 'Run bash scripts/fetch-dependencies.sh first.\n' >&2
  exit 1
fi

[ "$("$generator" --version)" = 'Version: 2.44.1' ]
[ "$(git -C .build/vendor/Defaults rev-parse HEAD)" = 38925e3cfacf3fb89a81a35b1cd44fd5a5b7e0fa ]
[ "$(git -C .build/vendor/Settings rev-parse HEAD)" = 879ea83a7bbc6dbebf62bed8c547f090146372a6 ]
"$generator" generate
