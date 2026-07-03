#!/bin/sh
# Compiles the app's pure logic files + golden tests with swiftc and runs them.
# Used locally and by CI; a failing check exits nonzero.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
xcrun swiftc -O \
  BallStrikeCamera/Analysis/FlightArcModel.swift \
  BallStrikeCamera/Models/TrackedShotModels.swift \
  BallStrikeCamera/Models/CourseModels.swift \
  BallStrikeCamera/Services/Golf/ClubAnalyticsService.swift \
  BallStrikeCamera/Analysis/DistanceEstimator.swift \
  BallStrikeCamera/Analysis/FlightModelPredictor.swift \
  BallStrikeCamera/Analysis/ModelResourceLoader.swift \
  tools/ios-logic-tests/main.swift \
  -o "$OUT/logic-tests"
"$OUT/logic-tests"
