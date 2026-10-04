# 05: Frontend tooling: pnpm/yarn and Playwright

**What to build:** Claude can install and test TypeScript/React projects and drive a browser. Corepack shims for pnpm and yarn are enabled. The Playwright CLI (`@playwright/cli`, pinned version) is installed globally with headless Chromium plus the system dependencies Chromium needs, so projects' own `@playwright/test` versions can download and run their matching browser. The npm cache, the pnpm store and the Playwright browser cache are Box Caches of the Workspace, like Maven's and Gradle's (ADR-0004); nothing of the Host's is mounted, and the Host's macOS Playwright cache would be useless in a Box anyway.

**Blocked by:** 01

**Model:** sonnet

**Status:** resolved

- [x] `pnpm` and `yarn` resolve via corepack to the version the project declares
- [x] A second Box on the same Workspace reuses what `pnpm install` / `npm ci` downloaded in the first, and another Workspace has its own
- [x] `playwright-cli` can open a page headlessly and take a screenshot
- [x] A project's `@playwright/test` E2E suite runs headless in the Box; its downloaded browser persists in the Workspace's Box Cache for the next Box
- [x] `@playwright/cli` version is pinned in one place in the Image definition

## Comments

### Changed by 09

This ticket originally had the Host's npm cache and pnpm store bind-mounted
read-write as Host Caches, which ADR-0003 allowed because both verify their
contents against the lockfile hash on read. 09 stopped mounting anything of
the Host's home and made Box Caches per Workspace (ADR-0004), so that half of
this ticket would have built the pattern 09 had just removed. The spec above
now follows ADR-0004. The counter-argument is on record in ADR-0003: npm and
pnpm are the two caches where read-write sharing would have been safe.

One thing to check while implementing: pnpm hardlinks from its store into
`node_modules`, and the Workspace is a bind mount from the Host while a Box
Cache is a volume — two different filesystems, so pnpm may fall back to
copying. If that turns out to cost real time or disk, the store's place is the
decision to revisit, not the "nothing of the Host's" rule.

### Confirmed

Verified by hand on 2026-10-04, against a throwaway Workspace with a fixture
`package.json` (`"packageManager": "pnpm@9.12.3"`, a `@playwright/test` E2E
spec) run through `bin/claude-box --no-pull --shell`:

- `pnpm --version` inside the Box printed `9.12.3`, the version the fixture's
  `packageManager` field declared, not whatever corepack's own default would
  have picked. `yarn` resolves the same way; corepack does not distinguish
  between the two.
- First Box: `pnpm install` populated `~/.local/share/pnpm` (12 MB) and a
  plain `npm ci` populated `~/.npm` (59 MB). Second Box, same Workspace:
  `pnpm install` reported "reused 3, downloaded 0"; `npm ci --prefer-offline`
  showed `cache hit` for every package. A third Workspace saw neither marker
  file written into either cache (automated in `tests/box.bats`).
- `playwright-cli install-browser chrome-for-testing` downloaded Chromium into
  `~/.cache/ms-playwright`. `playwright-cli --browser chromium open
  https://example.com` followed by `playwright-cli screenshot
  --filename=shot.png` produced a real 1280x720 PNG, headless (no `--headed`
  passed). `--browser chromium` is required on every call: Playwright CLI
  defaults to a real Google Chrome channel the Image does not install, only
  the system libraries and headless Chromium build Playwright downloads
  itself — now documented in the README.
- `npx playwright install chromium` (the fixture's own `@playwright/test`
  1.47.0, a different browser revision than Playwright CLI's) then `npx
  playwright test` ran the fixture's E2E spec headless and passed. A second
  Box on the same Workspace ran the same suite again with no download. Both
  Playwright versions' browsers sat side by side in `~/.cache/ms-playwright`
  without conflict.
- The hardlink-vs-copy question above: `stat` on a file pnpm placed in
  `node_modules` (device of the Workspace bind mount) against a file in
  `~/.local/share/pnpm` (device of the Box Cache volume) showed two different
  device numbers and `links=1` on both sides — pnpm copied rather than
  hardlinked, as the paragraph above anticipated. For one small fixture
  package this cost was immeasurable; worth watching on a real Workspace with
  a large `node_modules`, but not a reason to revisit the cache's place today.

Two bugs this verification caught that no automated test alone would have:

- `install -d -o claude -g claude <leaf dir>` only chowns the directory it is
  given, not the parents it creates along the way. `~/.cache` and
  `~/.local/share` were left owned by `root`, which blocked corepack from
  creating its own `~/.cache/node` the first time any `pnpm`/`yarn` command
  ran at all (`EACCES`). Fixed by listing every intermediate directory
  explicitly; `tests/image.bats` now checks `~/.cache` and `~/.local/share`
  belong to `claude` too, not just the leaves.
- pnpm's own default `store-dir` ignores `$HOME` entirely: with none set, it
  puts the store at the root of whatever filesystem the current Workspace
  happens to sit on (confirmed against both a bind-mounted and a
  container-local directory), so the Box Cache mounted at
  `~/.local/share/pnpm` would otherwise never be used. Fixed by pointing
  `store-dir` at it through pnpm's own config file at `~/.config/pnpm/rc`,
  not the shared `~/.npmrc`: npm reads that file too and warns on every
  command about a `store-dir` key it does not understand. ADR-0004 now notes
  this one exception to "the Image configures neither tool."

### Review

`/code-review` ran both axes against this ticket. Findings acted on:

- Four new lines (Dockerfile, README) said "a project"/"a project's own"
  where the glossary's term is Workspace. Reworded.
- ADR-0004's "the Image configures neither tool" line is no longer true
  without qualification now that pnpm's `store-dir` is set; a paragraph now
  records the exception and why it doesn't undercut the ADR's actual rule
  (per-Workspace, nothing of the Host's).
- The hand-check ADR-0004's Gradle/Maven precedent asked for ("pnpm hardlinks
  ... may fall back to copying") had not actually been done; it has now,
  confirmed above.

Findings noted and kept as they are:

- Three `tests/image.bats` names were flagged as missing a "so/because"
  clause. Checked against their nearest siblings in the same file (`"Claude
  Code is installed at the version the Image pins"`, `"the Image carries
  Docker Engine with the Compose plugin"`) and the `tests/cli.bats` test they
  sit next to (`"gives the Workspace its own Box Caches for Maven and
  Gradle"`): all three follow the plain-factual style those precedents
  already use in the same files, so this isn't a deviation.
- `bin/claude-box`'s `BOX_CACHE_*`/`*_volume` trio is now five pairs instead
  of two, which could be a loop. Kept explicit to match the file's existing
  style and stay easy for shellcheck to follow, the same tradeoff the Maven
  and Gradle pair already made.
