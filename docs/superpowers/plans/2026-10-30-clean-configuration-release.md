# Recorded configuration and compact panel release

**Goal:** Implement the approved `Finch-clean-config-design.html`, install locally, and publish GitHub v0.8.0 with matching source and checksums.

**Architecture:** A small configuration tracker consumes `thread_settings_applied` and `turn_context` records from the existing bounded reader. It keeps field provenance, ignores another thread's explicit settings, clears evidence after unread gaps, and never uses global defaults. Optional SQLite reasoning metadata is a compatibility fallback; it cannot prove Fast. SwiftUI shares one numeric column layout between the header and all rows.

**Tech stack:** Swift 5, Foundation, AppKit/SwiftUI, read-only SQLite, existing file events, GitHub CLI.

- [x] Run the existing eight suites as a baseline. Add a Store assertion requiring same-session `priority/high` settings to survive file parsing and snapshot encoding; observe it fail before implementing collection.
- [x] Add `SessionConfiguration.swift`, optional configuration/metadata effort on `SessionRecord`, and settings/context markers in `UsageAccumulator`. Pass expected session IDs through `TailReader`, resetting the tracker with replaced/truncated files and discarding configuration on skipped gaps.
- [x] Add Configuration tests for Fast/standard/unknown/other tiers, missing versus explicit null, old timestamps, foreign session IDs, model/effort transitions, partial lines, file replacement and head-only settings outside the bounded tail. Never infer service tier from throughput or global config.
- [x] Implement shared fixed-width numeric columns and a single header in `UsageViews.swift`. Title/status lead each row; model/effort/mode form the muted second line; token and last-round values align beneath. Remove repeated project activity labels and shorten footer copy; retain pending-new-session indication and stable ordering. Make quota windows two columns with snapshot/reset details accessible in help and accessibility labels; expired/stale states remain visible.
- [x] Extend fictional fixture generation with known Fast, standard and unknown examples. Preserve screenshots as synthetic, update README/architecture/release notes, and bump Info.plist to 0.8.0/build 9.
- [x] Run the full tests, native build and strict signature verification. Render/check dark, light and unknown states. Verify live numeric/config coverage without publishing private titles/paths. Capture a bounded static-idle measurement.
- [x] ZIP and verify the previous installed app, install the tested build, verify unchanged login-item state and one normal running process. Archive/unregister/remove staging `.app` bundles to avoid duplicate launcher icons.
- [ ] Commit and push the tested branch, create/merge a GitHub PR after CI passes, sync local main, package the exact merged source and tested app, and publish v0.8.0 as a preview release consistent with existing ad-hoc-signed distribution. Read back tag, release assets and SHA-256 digests; no force-push or overwriting older releases.
