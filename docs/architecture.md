# Architecture

## Collector

`UsageStore.swift` reads `~/.codex/state_5.sqlite` through read-only SQLite connections. It monitors 24 recent unarchived, user-root conversations. Project IDs take precedence; otherwise `ProjectGrouping.swift` selects the longest saved root with directory-boundary checks. Shared roots prefer the primary root, then sidebar order and ID.

`UsageCore.swift` starts with a bounded 512 KiB rollout tail, then reads increments up to 1 MiB. Partial lines, inode changes, truncation, and skipped gaps are handled explicitly. Missing gaps invalidate activity evidence while retaining the last usage snapshot. SQLite/WAL and rollout changes arrive through vnode events coalesced over 1.5 seconds. Metadata changes do not reread unchanged rollouts.

`DailyUsage.swift` independently streams every local rollout path whose thread metadata was updated since local midnight, including archived conversations and subagents. A separate SQLite cache preserves offsets and counted usage. `token_usage_record.usage` is counted once per response ID; any turn with those records excludes that turn's legacy `token_count` snapshots. Legacy-only turns use valid cumulative deltas, with missing baselines marked incomplete. Calendar intervals support timezone changes and daylight-saving days.

Raw incomplete lines are not persisted: the cache saves their starting offset so the next read can recover them. Log history copies and file replacements retain the response-ID deduplication set. The upstream protocol describes per-response records as best-effort observed Responses API usage: [TokenUsageRecord](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs).

For compatibility with the earlier local prototype, the bundle ID remains `local.codexusage.menu` and the cache directory remains `~/Library/Application Support/CodexUsage`. Renaming the display name does not reset existing preferences or cached usage.

## UI, activity, notifications

`App.swift` owns an AppKit status item and transient popover. `UsageViews.swift` renders SwiftUI content only while the panel is open. `FinchBrand.swift` creates the static template mark once. Quota expiry, activity staleness, and midnight use one-shot deadlines, not periodic scans.

`Activity.swift` follows explicit lifecycle events and matching turns. Nonblocking `request_user_input_async` and queued user messages do not imply waiting/running. Stale running evidence becomes unknown after ten minutes.

`NoticePolicy.swift` and `LocalNotifications.swift` handle native notifications. Cold startup silently seeds a baseline. Last 200 keys are retained; old completion/attention events over five minutes and quota snapshots over fifteen minutes cannot notify. Notification categories and sound are independently configurable. Clicks validate the session UUID before opening `codex://threads/<UUID>`.

## Diagnostics

These options are for development; snapshot exports can contain local titles and paths. Use synthetic fixtures for public screenshots.

```sh
APP='build/Codex Finch.app/Contents/MacOS/CodexFinch'
python3 scripts/make-demo.py /tmp/finch-demo
"$APP" --data-root /tmp/finch-demo --daily-cache /tmp/finch-demo/cache.sqlite --metric tokens --render /tmp/finch-dark.png
"$APP" --data-root /tmp/finch-demo --daily-cache /tmp/finch-demo/cache.sqlite --render /tmp/finch-light.png --light
"$APP" --data-root /tmp/finch-demo --daily-cache /tmp/finch-demo/cache.sqlite --render /tmp/finch-settings.png --settings
"$APP" --data-root /tmp/finch-demo --daily-cache /tmp/finch-demo/cache.sqlite --dump /tmp/finch-snapshot.json
```

`--benchmark 30` runs the collector without a status item; `--diagnostics /path` saves snapshots; `--show` opens the panel; `--notification-status /path` reads native notification settings without requesting permission or scheduling a notice. `--metric` persists the selected metric.

## Validation

The five test suites cover parsing, deduplication, cumulative counter handling, project roots, file-driven updates, pause/resume, lifecycle matching, notification policy, archived/subagent daily coverage, restarts, file replacement, midnight, and DST. Version 0.5 has 102 passing assertions.

Native views are rendered in both appearances with synthetic records. Builds and ad-hoc signatures are checked on macOS 26 / Apple Silicon. UUID links and the installed URL handler are verified; visible click-to-conversation, permission prompt, notification banner, and notification-click end-to-end checks remain unverified.

Historical collector measurements from version 0.4: about 0.8% of one CPU core over a 30-second live sample, RSS 37–51 MiB with the panel closed. A static fixture recorded one refresh over 40 seconds without repeated reads. These are local samples, not universal guarantees. Initial daily backfill can read hundreds of MiB; the persistent index makes subsequent same-day reads incremental. RSS is not total memory footprint.

Version 0.5 live app, panel closed: a 30.06-second sample used 0.17 CPU seconds (0.57% of one core), with RSS 31.4–32.8 MiB over seven samples. This measurement follows a warm-cache launch and does not include cold daily backfill or an open panel.
