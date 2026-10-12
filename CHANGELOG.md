# Changelog

## 0.6.0 — 2026-10-12

- System-backed launch-at-login settings and safe migration of the existing owned startup agent.
- Today’s project/model breakdown and 30-day retained local usage history, with 7/30-day views.
- Session search, running/waiting filters, and configurable monitoring range.
- Sanitized diagnostics, actionable notification settings, and explicit release checks.
- Fix activity detection when large progress events place their event type after command output.
- macOS CI, checked archive packaging and additional migration/attribution/retention coverage.

Builds remain ad-hoc signed, without notarization.

## 0.5.0 — 2026-10-08

First public preview of Codex Finch.

- Codex Finch name, finch app icon with Codex corner badge, and native template menu mark.
- Configurable menu metric with today's recorded local token total.
- Project-grouped sessions and conversation links.
- Explicit activity states and optional native notifications.
- Incremental file-event collection and persistent daily usage cache.
- Synthetic public screenshots, English/Chinese documentation, MIT code license, and 102 passing assertions.

Builds target macOS 14+ and are ad-hoc signed, without notarization. Initial downloads target Apple Silicon. Notification delivery and conversation-click end-to-end verification remain pending.
