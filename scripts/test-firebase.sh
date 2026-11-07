#!/bin/zsh
# Runs the Cloud Functions tests: unit tests, then the whole API and the security rules against the
# Firestore emulator. Needs Node 22+ and Java 11+ (brew install node openjdk). No Firebase project needed.
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT/firebase/functions"

if ! /usr/libexec/java_home >/dev/null 2>&1 && [[ -d "$(brew --prefix openjdk 2>/dev/null)" ]]; then
  export JAVA_HOME="$(brew --prefix openjdk)/libexec/openjdk.jdk/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

[[ -d node_modules ]] || npm ci --no-fund --no-audit
npx tsc -p tsconfig.test.json --noEmit
npx firebase emulators:exec --non-interactive --project demo-barte --only firestore "npx vitest run"
