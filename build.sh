#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
target_dir=${1:-"$project_dir/build"}
app_dir="$target_dir/Codex Finch.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
zsh "$project_dir/make-icon.sh"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -O "$project_dir"/Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3 \
  -o "$app_dir/Contents/MacOS/CodexFinch"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
print -r -- "$app_dir"
