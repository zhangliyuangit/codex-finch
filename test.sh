#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
mkdir -p "$project_dir/build"
test_dir=$(mktemp -d "$project_dir/build/tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
suites=(Usage Performance Configuration Project Store Activity Daily Login Support)
if (( $# )); then suites=("$@"); fi
for suite in "${suites[@]}"; do
  xcrun swiftc -swift-version 5 -O \
    "$project_dir/Sources/ReleaseCheck.swift" "$project_dir/Sources/LoginItemPolicy.swift" "$project_dir/Sources/SessionFilter.swift" "$project_dir/Sources/UsageCore.swift" "$project_dir/Sources/Activity.swift" "$project_dir/Sources/TurnPerformance.swift" "$project_dir/Sources/SessionConfiguration.swift" \
    "$project_dir/Sources/NoticePolicy.swift" "$project_dir/Sources/UsageStore.swift" \
    "$project_dir/Sources/ProjectGrouping.swift" "$project_dir/Sources/DailyUsage.swift" "$project_dir/Tests/${suite}Tests.swift" \
    -lsqlite3 -o "$test_dir/${suite}-tests"
  "$test_dir/${suite}-tests"
done
