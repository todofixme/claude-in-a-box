# The Code Graph server is registered per Box through `--mcp-config`

A Box can serve Claude a Code Graph of the Workspace instead of making it search hundreds of files with `rg`: the Image carries the `codebase-memory-mcp` binary at a pinned version, and `claude-box --code-graph` registers it for that one Box by passing `--mcp-config` to Claude, mounts a Box Cache of the Workspace on `~/.cache/codebase-memory-mcp` for the graph, and sets `CBM_ALLOWED_ROOT` to the Workspace so indexing cannot reach anything else. Without the flag a Box is exactly what it was before: no `--mcp-config`, no `CBM_` variable, no volume on the Host. The server contributes 17 tool descriptions to every context it is in, and a Workspace that does not want a graph should not pay for them.

## Considered Options

Claude Code offers two surfaces the Image could have owned instead of the CLI, and neither can carry this server.

- **`managedMcpServers` in `/etc/claude-code/managed-settings.json`**: accepts only `http` and `sse` entries. A `command` entry is dropped silently — with one of each configured, `claude mcp list` shows the `http` server and never mentions the stdio one. `codebase-memory-mcp` is a stdio server, so this surface cannot register it at all.
- **`/etc/claude-code/managed-mcp.json`**: does carry a stdio server, and takes exclusive control of MCP while it exists. In a Workspace holding a `.mcp.json` of its own, `claude mcp list` shows only the managed server; remove the file and the Workspace's own server appears. Baking it into the Image would therefore stop every Workspace's `.mcp.json`, every plugin server and Claude in Chrome from loading in every Box, to add one server some Workspaces want.

`--mcp-config` has neither problem: it adds servers rather than replacing them, so a Workspace's own MCP configuration keeps working, and it is per start, which is what makes `--code-graph` a flag rather than a property of the Image. `--strict-mcp-config` is deliberately not passed, for the same reason. It takes several values, so `claude-box` puts it behind whatever the developer passed rather than in front: `claude-box --code-graph "find the dead code"` with the flag first would have Claude read the prompt as a second config file and fail.

## Consequences

Registration lives in `bin/claude-box`, so this is also how any later MCP server reaches a Box: an argument the CLI assembles, visible in `--dry-run`, not a file in the Image.

Two things a `--code-graph` Box needs cannot be baked into the Image, because `codebase-memory-mcp` persists its configuration under the same root as the graph and the Box Cache mounted there would hide anything the build wrote. The entrypoint therefore sets both on each start of such a Box, where they are idempotent and land in that Workspace's own Box Cache: `auto_index`, so the first MCP connection indexes the Workspace and neither the developer nor Claude has an indexing step to remember, and `ui_enabled`, which is on by default and would otherwise leave the graph's HTTP UI listening inside the Box for nothing — no Box publishes a port for it.

`CBM_ALLOWED_ROOT` is what confines indexing, and the server refuses any path outside it. It is not a wall: the server's own `allow-root` command can record another root in the Box Cache and overrides the variable. That is accepted, because inside a Box Claude already has `sudo` and can read the whole filesystem — the Box is the wall (ADR-0001), and this setting is what keeps indexing to the Workspace rather than wandering into `$HOME` and the Box Caches.

The graph can lag the working tree. The server's file watcher is left at its default, but a graph is still a snapshot, which is why `--help` and the README say so and why `git diff` and reading files stay the answer to "what did I just change".
