# Per-conversation response metrics implementation plan

> Execute inline using executing-plans; the user approved the illustrated design and implementation. No additional design approval is needed.

**Goal:** Show trustworthy last-round metrics on each conversation without moving rows during concurrent work.

**Architecture:** A bounded `TurnPerformanceTracker` stores completion metadata and matching cumulative per-turn output snapshots. `UsageAccumulator` feeds it alongside activity, and `UsageStore` publishes `SessionRecord.performance`. A frozen `SessionListOrder` projects fresh records into the panel's initial group/row order. SwiftUI rows render three metrics using this snapshot.

**Tech Stack:** Swift 5, Foundation, SwiftUI/AppKit, read-only SQLite, existing vnode watcher.

## Tasks

- [x] Baseline: run `zsh test.sh` in this sibling worktree; expect all seven suites to pass.
- [x] Add a failing Store integration assertion: append same-turn `token_usage_record` with `turn_token_usage.output_tokens=420`, followed by `task_complete(duration_ms=26000,time_to_first_token_ms=1800)`; encode snapshot and require the row's `performance.outputTokens=420`. Existing code must fail this assertion while old checks pass.
- [x] Create `Sources/TurnPerformance.swift`: Codable/Equatable completion model, validation/format helpers and bounded tracker. Feed only numeric per-turn snapshots and matching completion events from `UsageCore.swift`. Add optional performance to `SessionRecord` and copy it during reload. Include the file in `test.sh`.
- [x] Add `Tests/PerformanceTests.swift`: same-turn cumulative snapshots are replaced, never summed; child IDs are excluded; current-round usage cannot overwrite completed-round metrics; late matching usage updates its round; invalid/zero/missing data cannot fabricate a rate; gaps lose incomplete matching data. Run the targeted suite and integration checks.
- [x] Add `SessionListOrder` in `ProjectGrouping.swift`, with tests proving changed timestamps/project membership/new arrivals do not move existing rows, refreshed values remain current, and rebuilding order on reopening reflects new records.
- [x] Update `UsageViews.swift`: remove recent card, freeze order for panel lifetime, enlarge bounded list viewport, replace two-line row with the approved three-line layout. Preserve link action and cumulative token details in help. Show pending-new-session count and metric semantics beneath the list.
- [x] Extend `scripts/make-demo.py` to emit fictional timing/turn usage fixtures. Update READMEs and `docs/architecture.md` with metric semantics. Bump local build to 0.7.0/build 8.
- [x] Run `zsh test.sh`, `zsh build.sh /absolute/path/finch-performance.noindex`, and `codesign --verify --deep --strict` against the resulting app. Render both appearances and a missing-data fixture with existing `--render`, inspect once and fix issues in one batch if necessary.
- [x] Install with a verified ZIP backup of the current `/Applications/Codex Finch.app`, preserve bundle ID/preferences/login state, restart normal app, verify one running no-argument process. Unregister/remove the staging app to avoid duplicate launcher icons. Save validation evidence and commit the tested local branch; do not push or publish a release without a request.
