#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
app_path=${1:-"$project_dir/build/Codex Finch.app"}
[[ -d "$app_path" ]] || { print -u2 'Run zsh build.sh first.'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
architecture=$(uname -m)
codesign --verify --deep --strict "$app_path"
release_dir="$project_dir/build/release"
mkdir -p "$release_dir"
archive="Codex-Finch-$version-macOS-$architecture.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_dir/$archive"
(cd "$release_dir" && shasum -a 256 "$archive" > SHA256SUMS.txt)
print -r -- "$release_dir/$archive"
