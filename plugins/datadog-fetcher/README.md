# datadog-fetcher

An auto-delegating Haiku sub-agent that offloads Datadog MCP read calls out of the main conversation. Whenever the main agent would query Datadog (logs, metrics, monitors, traces, events, hosts, services, dashboards, incidents, RUM, notebooks), it hands the task to `datadog-fetcher`, which runs the queries, saves the full raw payloads to disk, and returns only a capped (~500-token) markdown summary. Read-only.

Why: Datadog MCP responses are huge. Running them through a Haiku sub-agent keeps the expensive main model's context small and cuts token cost.

## Components

- **`datadog-fetcher`** (agent, Haiku) — plans the minimum set of read queries, runs them (in parallel where possible), narrows once or twice if the first results point somewhere, writes everything to `tmp/datadog/<timestamp>-<slug>.json`, and returns a short summary with numbers, timestamps, example IDs, caveats, and a suggested follow-up.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install datadog-fetcher@ctrlshiftbryan-skills
```

## Usage

The agent is marked **mandatory** for Datadog reads. The main agent delegates whenever the user asks about production/staging health, errors, latency, alerts, traces, or any other Datadog data, instead of calling the MCP tools directly.

Give it a self-contained task: what to find, service/env/tags, time range, and the shape of answer you want. Example:

> Investigate 5xx errors for service:api env:prod over the last 4 hours. Find the top error messages with counts, when they started, and 1-2 example trace IDs. Check whether any monitors on that service are alerting.

It returns something like:

```
Saved: tmp/datadog/20260902-201500-api-prod-5xx.json
Queried: analyze_datadog_logs, search_datadog_spans, search_datadog_monitors, 16:00 → 20:00 UTC, filters: service:api env:prod status:error

Findings:
- 1,842 5xx responses; 91% are `TimeoutError: upstream payments`
- Started 18:42 UTC, still ongoing

Top items (4 total):
  1. TimeoutError: upstream payments — 1,676
  2. ECONNRESET redis — 112
  ...
Examples: trace 7f3a…, 9c21…
Caveats: none
Suggested follow-up: pull spans for service:payments env:prod 18:30-19:00
```

If the main agent needs more, it reads the JSON file or sends a narrower follow-up task.

## Defaults and limits

- Time range defaults to the last 1h (24h for monitors/incidents/dashboards) when not given.
- Max 100 items per call, max 3 pages, max 2 narrowing follow-ups per task.
- Empty results: widens the range once (2x) or drops the most specific filter once, then stops and says so.
- Uses the MCP server's own skills (`list_datadog_skills` / `load_datadog_skill`) at most once per task when unsure of query syntax.

## Notes / Requirements

- **Requires the official `datadog` plugin** from `claude-plugins-official` with its MCP server set up (`/ddsetup`) and authenticated (`/mcp`). If the server is missing or not authenticated the agent stops and tells you which command to run in the main session.
- **Read-only.** Write tools (`create_datadog_notebook`, `edit_datadog_notebook`, `upsert_datadog_dashboard`, `submit_mcp_feedback`) and auth/setup flows stay in the main agent and are not in this agent's tool allowlist.
- The agent never writes into your project; it only touches `tmp/datadog/`. Add `tmp/` to `.gitignore`.
- It does not retry on network errors. Errors are returned verbatim for the main agent to handle.
