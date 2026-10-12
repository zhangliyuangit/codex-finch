# Finch panel refinement

The requested change removes conversation search and refines the existing native panel. Keep the accepted Finch identity, project groups, state filters, settings, statistics and Codex links. Today’s total is the primary reading; account quota remains explicitly a shared, timestamped snapshot. This is a refinement of the current surface, not a new visual direction.

## Implementation

- Remove the search field and query matching; preserve running/waiting filtering and stale-activity handling.
- Lead with today’s total. Use compact quota rows, a clickable recent-conversation summary, consistent row alignment and restrained hover feedback. Put settings in the footer and keep navigation accessible by keyboard and VoiceOver.
- Apply the same spacing and accent to statistics and settings. Keep normal collection offline and event-driven; add no timers, dependencies or animation.
- Build 0.6.1 in an excluded staging directory. Run existing tests and inspect synthetic native previews in both appearances, including missing data and long titles. Install over the existing Applications copy, check login state, and archive staging bundles to avoid duplicate launcher entries.

## Verification

Rendered previews prove composition and absence of search. Native UI checks cover settings/statistics navigation, project expansion and state filters. Existing parser, collector, startup and link policies must still pass. Synthetic public previews contain no personal metadata.
