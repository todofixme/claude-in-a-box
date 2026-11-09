# claude-box

You are running inside claude-box: a linux/arm64 container with no display.
The Image pins its tools; installing extra packages with `sudo apt-get` is fine,
but do not replace a tool the Image brings.

## Browser (Playwright)

`playwright-cli`, a headless Chromium and the `playwright-cli` skill are part of
the Image. Where the skill and the Box disagree, the Box wins:

- No `--browser` flag: `playwright-cli open <url>` already uses the Box's
  Chromium. Never use Chrome (`--browser=chrome`, `attach --cdp=chrome`,
  `channel: 'chrome'`): Chrome does not exist for linux/arm64.
- Do not install or update the tooling (`playwright-cli install`,
  `install-browser`, `npm install -g @playwright/cli@latest`), even when
  `playwright-cli` announces an update: the Image pins the version.
- No display: `--headed` and `show --annotate` do not work. Use snapshots and
  screenshots, and show the user a screenshot when they need to see the page.
- `playwright-cli` writes snapshots, screenshots and saved state to
  `.playwright-cli/` in the current directory. Never commit it.
- A project's own `@playwright/test` needs its own version-matched browser:
  `npx playwright install chromium`, without `--with-deps` (the system
  libraries are in the Image). It persists in the Workspace's cache, so this
  is needed once per Workspace and again after a Playwright upgrade.
