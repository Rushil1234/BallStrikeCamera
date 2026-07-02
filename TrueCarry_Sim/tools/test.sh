#!/bin/sh
# Headless physics/course regression using macOS JavaScriptCore.
cd "$(dirname "$0")/.."
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc
sed -E "s/^import [^;]*;?$//; s/^export (const|function|let|class|var)/\1/; s/^export \{[^}]*\};?$//" \
  js/noise.js js/physics.js js/clubs.js js/holes.js js/pebble-private.js js/pebble-osm.js \
  js/pebble-world-data.js js/pebble-elevation.js js/augusta-private.js js/augusta-osm.js \
  js/augusta-elevation.js js/augusta-world-data.js js/world.js js/terrain.js > /tmp/gspro-core.js
cat tools/three-stub.js /tmp/gspro-core.js tools/bot-test.js > /tmp/gspro-test.js
exec "$JSC" /tmp/gspro-test.js
