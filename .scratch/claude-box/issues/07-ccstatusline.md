# 07: ccstatusline

**What to build:** Claude in the Box shows a status line rendered by ccstatusline. ccstatusline is installed globally from npm at a pinned version and configured as Claude's `statusLine` via managed settings, so it applies regardless of what is in the `claude-home` volume. The default ccstatusline layout is used; a layout the developer customises interactively persists across Box restarts.

**Blocked by:** 01

**Model:** sonnet

**Status:** ready-for-agent

- [ ] Status line appears in Claude in a fresh Box with an empty `claude-home` volume
- [ ] ccstatusline version is pinned in one place in the Image definition
- [ ] A customised ccstatusline layout survives a Box restart
