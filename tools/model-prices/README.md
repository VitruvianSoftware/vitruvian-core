# `//tools/model-prices:update`

Refreshes [`packages/orchestrator-core/src/prices.mjs`](../../packages/orchestrator-core/src/prices.mjs) from [`tools/model-prices/models.tsv`](models.tsv) and OpenRouter's public [`https://openrouter.ai/api/v1/models`](https://openrouter.ai/api/v1/models) endpoint (no API key required).

> **Estimates, not a bill.** Prices come from OpenRouter's public model list (`https://openrouter.ai/api/v1/models`), which can differ from a vendor's own price page, because OpenRouter may add its own margin. Treat a price that looks off as a reason to check the vendor's page. The orchestrator panel uses `prices.mjs` only as rough per-million-token USD spend estimates, never as a bill.

## How it works

1. Reads `tools/model-prices/models.tsv` in output order (`first match wins` in `PRICES`, so more specific regexes such as `opus-5-5` and `haiku-5-5` must precede catch-all patterns `opus` and `haiku`).
2. Fetches `https://openrouter.ai/api/v1/models` (or reads `--offline <file>`), converting `pricing.prompt`, `pricing.completion`, `pricing.input_cache_read`, and `pricing.input_cache_write` from USD-per-token strings to USD-per-million-tokens (exact decimal arithmetic rounded half-up at 6 fractional digits). Refuses empty upstream model lists rather than silently writing all fallbacks.
3. Resolves each row:
   - When `openrouter_id` is found in the upstream response, uses OpenRouter's prompt/completion rates (`source: "openrouter"`). If OpenRouter omits `input_cache_read` or `input_cache_write` on that model, falls back per field to `fallback_cache_read` / `fallback_cache_write`.
   - When `openrouter_id` is `-` or absent from OpenRouter's response, keeps all four fallback rates from `models.tsv` (`source: "fallback"`).
4. Prints a compact `old -> new` table per row and lists any rows that fell back.
5. Writes `packages/orchestrator-core/src/prices.mjs` deterministically when anything changes, advancing `PRICES_UPDATED` to today's UTC date (`YYYY-MM-DD`) **only** when a price, `source`, or row entry changed.

## Syncing vendored plugin copies

`//tools/model-prices:update` writes only the canonical `packages/orchestrator-core/src/prices.mjs` (avoiding nested `bazel run` lock contention). Always follow a write run with `agent-roster` (or `//:tidy`) so the three vendored plugin copies stay byte-identical:

```sh
bazel run //tools/model-prices:update
bazel run //tools/agent-roster -- --write
```

`bazel run //tools/agent-roster -- --check` (run in `tidy-check`) fails if the vendored copies drift.

## Flags

| Flag | Description |
|---|---|
| `--check` | Fetch and compare without writing anything. Prints the `old -> new` table and exits `1` if any price differs from `prices.mjs` (`0` when current). |
| `--offline <file>` | Read the OpenRouter `/api/v1/models` JSON payload from `<file>` instead of making a network request (used by unit tests and offline dry runs). |
| `--max-change <percent>` | Safety rail against malformed upstream data (default: `50`). Refuses to write and exits `1` if any existing non-zero price moves by more than `<percent>%` (populating a previously `0` cache rate is allowed; dropping a non-zero price to `0` counts as `100%` and is refused). |
| `--markdown-out <file>` | Write a GitHub-Flavored Markdown `old → new` summary table (with pipe characters escaped) to `<file>` for pull request descriptions. |
| `-h`, `--help` | Print CLI usage and exit `0`. |

## Weekly workflow

[`.github/workflows/model-prices.yaml`](../../.github/workflows/model-prices.yaml) runs Mondays at `13:41 UTC` (and via `workflow_dispatch`), executes `//tools/model-prices:update` followed by `//tools/agent-roster -- --write`, and opens or updates a pull request titled `chore(agents): refresh model prices` on branch `chore/model-prices` when prices change.
