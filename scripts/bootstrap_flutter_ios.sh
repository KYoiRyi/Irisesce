#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$(mktemp -d)"

mkdir -p "$BACKUP_DIR/ios"
if [ -d "$ROOT_DIR/ios/Runner" ]; then
  cp -R "$ROOT_DIR/ios/Runner" "$BACKUP_DIR/ios/Runner"
fi

if [ ! -d "$ROOT_DIR/ios/Runner.xcodeproj" ]; then
  flutter create --platforms=ios --project-name irisesce "$ROOT_DIR"
fi

if [ -f "$ROOT_DIR/ios/Podfile" ]; then
  if grep -q "^# platform :ios" "$ROOT_DIR/ios/Podfile"; then
    perl -0pi -e "s/^# platform :ios, '[^']+'/platform :ios, '15.0'/m" "$ROOT_DIR/ios/Podfile"
  elif grep -q "^platform :ios" "$ROOT_DIR/ios/Podfile"; then
    perl -0pi -e "s/^platform :ios, '[^']+'/platform :ios, '15.0'/m" "$ROOT_DIR/ios/Podfile"
  else
    printf "platform :ios, '15.0'\n" | cat - "$ROOT_DIR/ios/Podfile" > "$ROOT_DIR/ios/Podfile.tmp"
    mv "$ROOT_DIR/ios/Podfile.tmp" "$ROOT_DIR/ios/Podfile"
  fi
fi

if [ -d "$BACKUP_DIR/ios/Runner" ]; then
  cp -R "$BACKUP_DIR/ios/Runner/." "$ROOT_DIR/ios/Runner/"
fi

if [ -f "$ROOT_DIR/ios/Runner/Info.plist" ]; then
  /usr/libexec/PlistBuddy -c "Add :UIFileSharingEnabled bool true" "$ROOT_DIR/ios/Runner/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :UIFileSharingEnabled true" "$ROOT_DIR/ios/Runner/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$ROOT_DIR/ios/Runner/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :LSSupportsOpeningDocumentsInPlace true" "$ROOT_DIR/ios/Runner/Info.plist"
fi

rm -rf "$BACKUP_DIR"
