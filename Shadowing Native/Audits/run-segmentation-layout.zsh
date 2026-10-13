#!/bin/zsh
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/shadowing-layout.XXXXXX")"
trap 'rm -rf "$AUDIT_BUILD"' EXIT
cd "$NATIVE_ROOT"
xcrun swiftc -module-cache-path "$AUDIT_BUILD/module-cache" -parse-as-library -swift-version 6 \
 ShadowingNative/Models/LearningProfile.swift \
 ShadowingNative/Models/YouTubeTranscript.swift \
 ShadowingNative/Models/ShadowingPhrase.swift \
 ShadowingNative/Services/ShadowingLessonBuilder.swift \
 Audits/SegmentationLayoutAudit.swift -o "$AUDIT_BUILD/audit"
"$AUDIT_BUILD/audit"
