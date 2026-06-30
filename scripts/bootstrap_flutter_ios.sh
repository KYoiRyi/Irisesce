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

if [ -d "$BACKUP_DIR/ios/Runner" ]; then
  cp -R "$BACKUP_DIR/ios/Runner/." "$ROOT_DIR/ios/Runner/"
fi

rm -rf "$BACKUP_DIR"
