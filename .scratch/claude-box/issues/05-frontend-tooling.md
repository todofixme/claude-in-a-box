# 05: Frontend tooling: pnpm/yarn and Playwright

**What to build:** Claude can install and test TypeScript/React projects and drive a browser. Corepack shims for pnpm and yarn are enabled. The Playwright CLI (`@playwright/cli`, pinned version) is installed globally with headless Chromium plus the system dependencies Chromium needs, so projects' own `@playwright/test` versions can download and run their matching browser. The npm cache, the pnpm store and the Playwright browser cache are Box Caches of the Workspace, like Maven's and Gradle's (ADR-0004); nothing of the Host's is mounted, and the Host's macOS Playwright cache would be useless in a Box anyway.

**Blocked by:** 01

**Model:** sonnet

**Status:** ready-for-agent

- [ ] `pnpm` and `yarn` resolve via corepack to the version the project declares
- [ ] A second Box on the same Workspace reuses what `pnpm install` / `npm ci` downloaded in the first, and another Workspace has its own
- [ ] `playwright-cli` can open a page headlessly and take a screenshot
- [ ] A project's `@playwright/test` E2E suite runs headless in the Box; its downloaded browser persists in the Workspace's Box Cache for the next Box
- [ ] `@playwright/cli` version is pinned in one place in the Image definition

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
