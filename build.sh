#!/usr/bin/env bash

set -euo pipefail

cd -- "$(dirname "$0")"
REPO_ROOT="$(pwd -P)"
DART='dart'
ENGINE="$(realpath "$REPO_ROOT"../engine/src/flutter)"

if [ ! -d "$ENGINE" ]; then
  echo "Expected an engine checkout to exist at $ENGINE"
  exit 1
fi

cd "$REPO_ROOT"

set -x

"$DART" pub get
mkdir --parents ./out
"$DART" compile exe ./bin/fer.dart -o ./out/fer
