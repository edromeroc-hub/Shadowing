#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

npm run ios:sync

timestamp="$(date +%Y%m%d-%H%M%S)"
build_root="$project_root/build/altstore-$timestamp"
ipa_root="$build_root/ipa"

mkdir -p "$build_root/derived" "$ipa_root/Payload" "$project_root/releases"

xcodebuild \
  -project ios/App/App.xcodeproj \
  -scheme App \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_root/derived" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build | tee "$build_root/build.log"

cp -R "$build_root/derived/Build/Products/Release-iphoneos/App.app" "$ipa_root/Payload/ShadowingAI.app"
app_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ipa_root/Payload/ShadowingAI.app/Info.plist")"
ipa_path="$project_root/releases/ShadowingAI-$app_version-altstore-$timestamp.ipa"
(cd "$ipa_root" && /usr/bin/zip -qry "$ipa_path" Payload)

echo "$ipa_path"
