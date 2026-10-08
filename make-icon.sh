#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
icon_dir=$(mktemp -d /tmp/codex-finch-icon.XXXXXX)
trap 'rm -rf "$icon_dir"' EXIT
mkdir -p "$icon_dir/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$project_dir/Assets/AppIcon.png" --out "$icon_dir/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$project_dir/Assets/AppIcon.png" --out "$icon_dir/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_dir/AppIcon.iconset" -o "$project_dir/Assets/AppIcon.icns"
