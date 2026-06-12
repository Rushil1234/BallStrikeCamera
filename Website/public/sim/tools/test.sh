#!/bin/sh
# Headless physics/course regression using macOS JavaScriptCore.
cd "$(dirname "$0")/.."
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc
sed -E "s/^import [^;]*;?$//; s/^export (const|function|let|class|var)/\1/; s/^export \{[^}]*\};?$//" \
  js/noise.js js/physics.js js/clubs.js js/holes.js js/terrain.js > /tmp/tcsim-core.js
cat tools/three-stub.js /tmp/tcsim-core.js tools/bot-test.js > /tmp/tcsim-test.js
exec "$JSC" /tmp/tcsim-test.js
