# Per-conversation response metrics

Approved design: `outputs/Finch-per-session-metrics-design.html` in the parent workspace.

Remove the recently updated conversation card. Each project conversation row shows its title and cumulative token count, current activity and model, then first-token latency, full-round duration and approximate average output throughput. Metrics remain neutral. Running/waiting rows explicitly identify the last completed round. Missing values are em dashes. The tooltip preserves cumulative input/output/cache details and explains that average throughput includes tool execution, waiting and reasoning output; it is not streaming decode speed.

Capture `task_complete.duration_ms` and `time_to_first_token_ms`. Match `token_usage_record.turn_token_usage.output_tokens` by the same local turn ID, excluding child/root mismatches. The cumulative per-turn snapshot avoids adding duplicate responses or summing an incomplete tail. Never use thread cumulative usage as the numerator or add reasoning output again. A reported duration must be positive for division. Invalid/missing timing remains unavailable. Newer completed rounds replace older results even if fields are missing. A separate last-completed record survives the next round starting.

Only metadata and numeric metrics are retained, with a bounded recent-turn cache. File gaps discard incomplete matching state; replacements/truncation already reset the parser. No new network requests, periodic timers or full history scan.

Freeze group membership and row order when the panel first receives records; update existing row values in place. New sessions appear on reopening, with an indicator while open. Counts and filters reflect the displayed records. On reopening, use current project grouping and recency. Expand projects with running/waiting work plus the first project initially. Keep the list scrollable with bounded height. A click continues through the existing Codex UUID deep-link callback.

Validate parsing, duplicate snapshots, interleaved turns, late records, invalid fields, partial tails, gaps, new-round retention, bounded state, integration through the existing file watcher, and stable presentation order. Render synthetic native light/dark/missing states, build/sign, then replace the local application with a backup while preserving bundle ID and startup preferences. Publishing GitHub/release is outside this turn.
