# figma-fetcher

An auto-delegating Haiku sub-agent that offloads Figma MCP read calls out of the main conversation. Whenever a Figma design URL appears, the main agent hands it to `figma-fetcher`, which pulls the full design payload, caches it to disk, and returns only a small (~300-token) markdown digest — keeping the main context window clean. Read-only.

## Components

- **`figma-fetcher`** (agent, Haiku) — fetches `get_design_context`, `get_screenshot`, `get_metadata`, `get_variable_defs`, and `get_code_connect_map` for a node (in parallel), caches the consolidated payload + screenshot to `tmp/figma/`, and returns a markdown digest.

## Install

```
/plugin marketplace add ctrlShiftBryan/skills
/plugin install figma-fetcher@ctrlshiftbryan-skills
```

## Usage

The agent is marked **mandatory** for Figma reads: the main conversation delegates to it whenever a user message contains a `figma.com/design/...` URL (or it would otherwise call one of the Figma read tools), rather than calling those tools directly.

It parses the `fileKey` and `node-id` out of the URL, then:

- **Cache check** — builds the key `{fileKey}__{nodeId}` and, on a hit, reads the stored digest back from disk without touching the MCP server.
- **Fetch** (cache miss / force refresh) — calls the five Figma read tools in parallel.
- **Persist** — writes:
  - `tmp/figma/{fileKey}__{nodeId}.json` — consolidated payload (design context, metadata, variables, Code Connect map, source URL, timestamp, and the digest itself).
  - `tmp/figma/{fileKey}__{nodeId}.png` — the node screenshot.
- **Return** — only the markdown digest: frame name + dimensions, top-level structure, variables grouped by category, Code Connect mapping counts, and asset count. The large raw payloads stay on disk.

**Force refresh:** if the user says "re-fetch", "force fresh", "ignore cache", "update from Figma", "reload the design", or similar, the main agent appends `Force refresh.` to the invocation to bypass the cache.

## Notes / Requirements

- **Requires the official Figma MCP server** ([setup](https://help.figma.com/hc/en-us/articles/32132100833559)). Without it the agent stops and tells you to install it and restart Claude Code.
- **Read-only.** Write tools (`use_figma`, `create_new_file`, `generate_figma_design`, `generate_diagram`, `upload_assets`, `add_code_connect_map`, `send_code_connect_mappings`) stay in the main agent and are not routed here — they aren't even in this agent's tool allowlist.
- **FigJam not supported.** `figma.com/board/...` URLs are rejected; the main agent should call `get_figjam` directly.
- The agent never writes into your project — it only touches `tmp/figma/`. It does not retry failed MCP calls; errors are returned verbatim for the main agent to handle.
