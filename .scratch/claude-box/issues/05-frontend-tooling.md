# 05: Frontend tooling: pnpm/yarn and Playwright

**What to build:** Claude can install and test TypeScript/React projects and drive a browser. Corepack shims for pnpm and yarn are enabled. The Playwright CLI (`@playwright/cli`, pinned version) is installed globally with headless Chromium plus the system dependencies Chromium needs, so projects' own `@playwright/test` versions can download and run their matching browser. The Playwright browser cache is a Box Cache shared between Boxes (the Host's macOS cache is never mounted). The Host's npm cache and pnpm store are bind-mounted read-write as Host Caches; missing Host directories are created empty.

**Blocked by:** 01

**Model:** sonnet

**Status:** ready-for-agent

- [ ] `pnpm` and `yarn` resolve via corepack to the version the project declares
- [ ] `pnpm install` / `npm ci` in the Box reuse the Host's pnpm store / npm cache
- [ ] `playwright-cli` can open a page headlessly and take a screenshot
- [ ] A project's `@playwright/test` E2E suite runs headless in the Box; its downloaded browser persists in the Box Cache for the next Box
- [ ] `@playwright/cli` version is pinned in one place in the Image definition
