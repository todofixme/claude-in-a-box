# 07: ccstatusline

**What to build:** Claude in the Box shows a status line rendered by ccstatusline. ccstatusline is installed globally from npm at a pinned version and configured as Claude's `statusLine` via managed settings, so it applies regardless of what is in the `claude-home` volume. The default ccstatusline layout is used; a layout the developer customises interactively persists across Box restarts.

**Blocked by:** 01

**Model:** sonnet

**Status:** resolved

- [x] Status line appears in Claude in a fresh Box with an empty `claude-home` volume
- [x] ccstatusline version is pinned in one place in the Image definition
- [x] A customised ccstatusline layout survives a Box restart

## Comments

ccstatusline installs globally from npm at a pinned version (`ARG
CCSTATUSLINE_VERSION`), the same pattern as Claude Code and `@playwright/cli`
in the Dockerfile. `image/managed-settings.json` gets a `statusLine` key
pointing at the `ccstatusline` command; managed settings outrank the
`claude-home` volume for the same reason `DISABLE_AUTOUPDATER` already does,
so this applies however long a Box has been in use.

No Box Cache or extra volume was needed for a customised layout: ccstatusline
persists it at `~/.config/ccstatusline/settings.json`, which is already
inside `/home/claude` and so already inside the shared `claude-home` volume
ticket 01 covers. With no config present it writes its own defaults there and
renders with those, so the default layout criterion and the restart
criterion share one mechanism.

Verified against the real npm package (2.2.30) before writing anything: piped
JSON on stdin renders the status line directly with no TUI and no network
needed, `--version` prints just the version, and editing
`~/.config/ccstatusline/settings.json` between two runs changes the next
render — confirmed in `tests/box.bats` with a `custom-text` widget carrying a
marker string, surviving a second Box the way `tests/box.bats` already
proves for `~/.claude/marker`.

### Review

`/code-review` ran both axes against this ticket. Findings acted on:

- `tests/image.bats`'s new stdin-piping test re-spelled
  `docker run --rm --pull never "$IMAGE"` instead of reusing the file's own
  `in_box` helper. `in_box` now runs with `-i`, so piping into it needs
  nothing more than `run in_box ccstatusline <<< '...'`; none of its other
  callers pipe anything in, so nothing else changes for them.
- A comment in `tests/box.bats` ("A second Box: the first one is gone...")
  was copy-pasted verbatim from the test immediately above it. Shortened to
  point at that test instead of repeating it.

Findings noted and kept as they are:

- "Status line appears in Claude" is verified at the mechanism level
  (managed settings name the right command; that command renders a status
  line from the exact kind of JSON Claude pipes to it) but not by watching an
  actual interactive Claude session, which needs a TUI no agent can drive.
  This mirrors 01's and 06's unconfirmable-by-agent criteria: please confirm
  by hand that the status line is visible on first launch in a fresh Box.
