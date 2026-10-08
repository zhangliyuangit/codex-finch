#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
test_dir=$(mktemp -d /tmp/codex-usage-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
for suite in Usage Project Store Activity Daily; do
  xcrun swiftc -swift-version 5 -O \
    "$project_dir/Sources/UsageCore.swift" "$project_dir/Sources/Activity.swift" \
    "$project_dir/Sources/NoticePolicy.swift" "$project_dir/Sources/UsageStore.swift" \
    "$project_dir/Sources/ProjectGrouping.swift" "$project_dir/Sources/DailyUsage.swift" "$project_dir/Tests/${suite}Tests.swift" \
    -lsqlite3 -o "$test_dir/${suite}-tests"
  "$test_dir/${suite}-tests"
done
