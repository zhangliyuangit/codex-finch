# Official usage API research — 2026-10-12

The installed Codex CLI is 0.153.4. Its generated experimental JSON Schema includes `account/usage/read`, with an optional `threadId`. `GetAccountTokenUsageResponse.threadUsage` is nullable and described as estimated usage when the requested thread's billing route is available. It includes `estimatedUsageCreditsMicros`, nullable `estimatedUsageUsdMicros`, and model breakdown groups.

A read-only local app-server audit initialized successfully and called this method for the existing Finch-development conversation. The request succeeded but returned no thread usage. No turn was started, no model was called, and authentication was not changed. A null result means unavailable, not zero cost.

The [official app-server documentation](https://developers.openai.com/codex/app-server) documents account usage summaries and optional daily buckets. These fields can themselves be absent. Schema support does not guarantee an account's billing route is available.

Finch 0.6 therefore continues displaying local tokens and account quota snapshots, without inventing a per-thread bill. A future integration can be explicit and on-demand: call the locally installed app-server only after the user asks, show server-provided values as estimates, and show unavailable for null. This must remain separate from the offline file collector; no persistent app-server or background network polling is needed.
