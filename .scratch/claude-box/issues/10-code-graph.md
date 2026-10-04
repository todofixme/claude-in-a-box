# 10: Code Graph via codebase-memory-mcp

**What to build:** Claude in a Box can ask a Code Graph of the Workspace
instead of searching hundreds of files with `rg`. The Image carries the
`codebase-memory-mcp` binary at a pinned version and everything the server
needs, but no Box uses it unless it is asked to: `claude-box --code-graph`
(or `CLAUDE_BOX_CODE_GRAPH`) registers the server for that Box through
`--mcp-config`, mounts a Box Cache of the Workspace for the graph, and
confines indexing to the Workspace. Without the flag a Box is exactly what it
is today, down to leaving no volume on the Host — the server contributes 17
tool descriptions to every context, which a Workspace that does not want a
graph should not pay for. A Workspace that does want one pays nothing beyond
the flag: the first MCP connection indexes the Workspace itself, so there is
no indexing step for the developer or for Claude to remember.

Registration goes through `--mcp-config` because the two managed surfaces
cannot carry this server: `managedMcpServers` in managed settings accepts
only `http` and `sse` entries and drops anything with a `command`, and
`/etc/claude-code/managed-mcp.json`, which can carry a stdio server, takes
exclusive control of MCP — a Workspace's own `.mcp.json`, plugin servers and
Claude in Chrome would all stop loading in every Box. ADR-0005 records that,
since it also decides how any later MCP server reaches a Box.

**Blocked by:** 09

**Model:** opus

**Status:** resolved

- [x] `codebase-memory-mcp` is on the `PATH` in a Box and reports the version the Image pins, pinned in one place in the Image definition and verified against `checksums.txt` at build time
- [x] `claude-box --code-graph` starts Claude with the `code-graph` MCP server; `CLAUDE_BOX_CODE_GRAPH=1 claude-box` does the same
- [x] A Box started without either has no `--mcp-config`, no graph mount and leaves no volume on the Host
- [x] A query in a `--code-graph` Box is answered from a graph nobody indexed by hand
- [x] The Code Graph of a Workspace is found again by the next Box on it; another Workspace has its own
- [x] Indexing cannot reach outside the Workspace
- [x] No port is published and the graph UI never starts
- [x] `--help`, the README and the GLOSSARY match: the flag, the environment variable, the pinned package, and that the graph can lag the working tree
- [x] ADR-0005 records why registration is `--mcp-config` and not a managed surface
- [x] Renovate offers the binary in the weekly maintenance group without automerge

## Comments

### Notes

- Established before writing anything, against the upstream repository and
  the Claude Code documentation:
  - Release v0.11.0 ships `codebase-memory-mcp-linux-arm64.tar.gz` with
    `checksums.txt` and an `sbom.json`. The Image only targets arm64, so that
    is the only asset needed. `datasource=github-releases` with
    `depName=DeusData/codebase-memory-mcp` fits the `customManager` already in
    `renovate.json`; only a `packageRule` for the weekly group is new.
  - The binary is self-contained, needs no runtime, no API key and no
    network, and keeps its data in SQLite under `CBM_CACHE_DIR`, default
    `~/.cache/codebase-memory-mcp`. Mounting the Box Cache on that default
    path means `CBM_CACHE_DIR` need not be set at all, the same way
    `~/.cache/ms-playwright` and `~/.npm` need no configuration.
  - `config set` persists under that same root, so runtime configuration
    baked at build time would be hidden by the volume. `auto_index` (default
    `false`) therefore gets set by the entrypoint on each start of a
    `--code-graph` Box, where it is idempotent and lands in the Workspace's
    own Box Cache.
  - The daemon starts itself on the first MCP connection and shuts down with
    the last session, so nothing about it belongs in the entrypoint.
  - `watcher_enabled` and `auto_watch` default to `true` and follow git
    projects; left at their defaults deliberately. The graph can still lag
    the working tree, which is why the README says so and why `git diff` and
    reading files stay the answer to "what did I just change".
  - `CBM_ALLOWED_ROOT` is what confines indexing; `bin/claude-box` already
    knows the Workspace path.
  - It carries its own `update` command. Unused: the version belongs to the
    Image, as with Claude Code and `DISABLE_AUTOUPDATER`.
- `auto_index_limit` defaults to 50000 and may well be reached by the large
  codebases this is meant for. Worth watching on the first real Workspace;
  it is a `config set` away, and whether the Image should set it is a
  question for after that, not a guess now.
- Whether a Code Graph actually beats `rg` on a large codebase is not
  decided here and not something bats can answer. It gets tested the only way
  it can be: the same large Workspaces driven with and without the flag. If
  that shows Claude ignoring the server's tools and reaching for `rg` anyway,
  the fix is an instruction surface the Image owns — and the Image has none
  today, because `~/.claude/CLAUDE.md` and `~/.claude/skills` live in the
  `claude-home` volume, which is seeded once and never again. That is a
  ticket of its own, not a part of this one.

### Confirmed

Built and checked on 2026-10-04 against a locally built Image
(`scripts/build-image.sh`), with `scripts/check.sh` green.

- The two managed surfaces were tested rather than taken from the docs, and
  both behaved as ADR-0005 now records. `managedMcpServers` with one `command`
  entry and one `http` entry beside it: `claude mcp list` shows only the
  `http` one, the stdio entry is dropped without a word.
  `/etc/claude-code/managed-mcp.json` carrying the stdio server does connect
  it — and in a Workspace with a `.mcp.json` of its own, that server vanishes
  from `claude mcp list` until the managed file is removed.
- `ui_enabled` turned out to default to `true`, which the ticket's notes did
  not mention: left alone, the graph UI listens on 127.0.0.1:9749 inside the
  Box. The entrypoint therefore sets `ui_enabled false` next to
  `auto_index true`, and `tests/code-graph-probe.sh` reads /proc/net/tcp to
  prove nothing listens.
- `auto_index` is asynchronous: `list_projects` on the same connection answers
  `projects: 0` before indexing finishes. The probe waits for the Workspace to
  appear instead, which is what Claude asking a second time amounts to. A
  one-file Workspace is indexed within a few seconds; a `--code-graph` Box
  including the probe's three sessions takes about 27s end to end.
- `CBM_ALLOWED_ROOT` confines the MCP tools as expected, but the binary's own
  `allow-root` command can record another root in the Box Cache and overrides
  the variable. Not hardened: inside a Box Claude has `sudo` anyway, so the
  Box is the wall. ADR-0005 says so rather than claiming more than the setting
  does.
- The binary is 300 MB unpacked, so the Image grows by about that much. The
  release ships `-portable` variants too; the glibc build works on
  `node:24-trixie` and is the one the ticket named.
- `auto_index_limit` is still at its default 50000, as the ticket's second
  note asks. Nothing here touches it.
