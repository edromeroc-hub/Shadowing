#!/bin/zsh
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/shadowing-recommendations.XXXXXX")"
trap 'rm -rf "$AUDIT_BUILD"' EXIT
cd "$NATIVE_ROOT"
xcrun swiftc -module-cache-path "$AUDIT_BUILD/module-cache" -parse-as-library -swift-version 6 \
 ShadowingNative/Models/LearningProfile.swift \
 ShadowingNative/Models/VideoSuggestion.swift \
 ShadowingNative/Models/YouTubeShortItem.swift \
 ShadowingNative/Models/YouTubeTranscript.swift \
 ShadowingNative/Models/ShadowingPhrase.swift \
 ShadowingNative/Services/StudyProgressStore.swift \
 ShadowingNative/App/AppModel.swift \
 ShadowingNative/Services/ShadowingLessonBuilder.swift \
 ShadowingNative/Services/ShortDifficultyEstimator.swift \
 ShadowingNative/Services/ShortsRecommendationEngine.swift \
 ShadowingNative/Services/ShortsDiscoveryService.swift \
 ShadowingNative/Services/YouTubeTranscriptService.swift \
 ShadowingNative/Services/TranscriptJSONParser.swift \
 Audits/RecommendationAudit.swift -o "$AUDIT_BUILD/audit"
"$AUDIT_BUILD/audit" "$@"

