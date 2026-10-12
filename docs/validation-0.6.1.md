# Version 0.6.1 validation — 2026-10-12

The native panel removes search, puts today's local total first, compacts shared account quota, and makes the recent-conversation summary clickable. Settings moves to the footer. Project groups, running/waiting filters, monitoring preferences, statistics and the existing Codex link handler remain available. Light appearance uses darker semantic accents for readable small status labels.

Seven existing suites pass 129 assertions with zero failures. State-filter assertions were updated after query matching was removed. The optimized macOS 14-targeted build and ad-hoc signature verification pass. The UI detector reports no findings; native rendering and interaction provide the visual and functional evidence.

Synthetic native renders were checked in dark and light appearances, including long conversation/project titles, missing quota and no conversations. The installed application was exercised with synthetic records in a temporary validation window: waiting/running/all filters, project expansion, footer settings entry, return navigation and the statistics entry worked. Accessibility exposed the controls and their labels. The existing link callback remains in use; no synthetic conversation was sent to Codex. Prior real-conversation navigation was human-confirmed in the 0.6 validation.

Version 0.6.1 is installed in Applications. System login-item status is enabled. After validation the application was restarted with no diagnostic arguments and real local data. LaunchServices lists one Finch bundle; Spotlight returns only the installed copy. The staging app is preserved in the release ZIP and its temporary registration removed. The previous installed version is backed up as a ZIP.

No collector, notification policy, timer or network behavior was changed. This pass adds no background polling, animation or dependency. No new performance measurement is claimed; see the bounded 0.6 sample in the previous validation. Notification-banner verification remains deferred at the user's request. Cloud billing integration remains unavailable.
