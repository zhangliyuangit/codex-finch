# Version 0.6 validation — 2026-10-12

## Automated and build checks

Seven suites pass 129 assertions on the local Apple Silicon Mac. Coverage includes precise/legacy counts, copied responses, original-thread ownership, project renaming without rereads, cached restarts, file replacement, midnight/DST, retained historical lower bounds, lifecycle field order, notification deduplication, safe legacy startup recognition, session filtering and sanitized diagnostics. App builds, bundle plist and ad-hoc signatures are checked separately.

The CI workflow builds and runs these suites on macOS 14. This is not a signing or notarization pipeline; archive packaging validates the current local build and writes SHA256SUMS.

## Installed application and native UI

- Installed version: 0.6.0 in the Applications directory.
- SMAppService reported enabled after migrating the existing known startup agent. The agent was backed up before removal.
- The login switch was actually turned off and back on through the native UI. The app kept running and the final state is on.
- Project/model totals, 7/30-day history and conversation search were exercised with actual local records.
- Clicking the searched Finch-development conversation was performed through the native UI. The user confirmed that Codex opened the correct chat. Automated inspection of the destination Codex window was refused by the computer-use tool, so this evidence is explicitly a human confirmation.
- Native notification permission is authorized. Test submission succeeded, and Notification Center reported test notifications. The user did not see a banner, including a second test with persistent alert style, and explicitly deprioritized further banner investigation. Visible banner/notification-click verification therefore remains incomplete.

Public preview images are rendered from synthetic data. No live titles, workspace paths or account identities are included in them.

## Performance sample

A 30.10-second sample of the installed 0.6 app with a warm cache and closed panel used 0.35 CPU seconds (1.16% of one CPU core). RSS ranged from 34.9 to 35.3 MiB. Codex was actively writing records during the sample. This is a local observation, not a universal bound; it excludes initial migration/backfill and an open native validation window. Normal launch uses only the menu bar; the diagnostic window is not opened automatically.

## Remaining limits

History shows retained indexed lower bounds, not a complete account bill. The installed official app-server supports an estimated per-thread usage field, but the read-only audit returned null for the development conversation. See [official usage research](official-usage-research.md). No fabricated fee conversion is included. Builds remain ad-hoc signed and unnotarized; Intel distribution has not been tested.
