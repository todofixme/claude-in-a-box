# 08: Renovate keeps Claude Code current

**What to build:** Renovate (Mend GitHub App) opens PRs whenever a new version of Claude Code, ccstatusline or `@playwright/cli` is published, and for base image digest and GitHub Actions updates. Claude Code and ccstatusline updates are automerged once the PR build is green, so the push to `main` publishes a new Image. Base image, Actions and `@playwright/cli` updates are grouped into one weekly PR without automerge.

Human steps: install the Mend Renovate app on the repo and merge its onboarding PR.

**Blocked by:** 02, 05, 07

**Model:** sonnet

**Status:** ready-for-human

- [x] Renovate detects the pinned versions of Claude Code, ccstatusline and `@playwright/cli`
- [ ] A Claude Code update PR is automerged after the PR build passes and results in a new `claude-<version>` Image in GHCR
- [ ] Base image digest is pinned and updated by Renovate
- [ ] Base image, Actions and `@playwright/cli` updates arrive as one weekly grouped PR, not automerged

## Comments

`renovate.json` now carries, beyond the onboarding `config:recommended`:

- A custom regex manager matching the `# renovate: datasource=... depName=...`
  comment already sitting above each `ARG ..._VERSION=` line in the
  `Dockerfile`. The comment for `CCSTATUSLINE_VERSION` and
  `PLAYWRIGHT_CLI_VERSION` was below its `ARG`, not above like
  `CLAUDE_CODE_VERSION`'s — moved both to match, since the regex (and every
  published example of this pattern) expects the comment first. Checked the
  extraction with a standalone Node script against the real `Dockerfile`:
  all three deps (`@anthropic-ai/claude-code`, `ccstatusline`,
  `@playwright/cli`, all npm datasource) come out with the right
  `currentValue`.
- A package rule automerging `@anthropic-ai/claude-code` and `ccstatusline`
  only.
- Three package rules sharing one `groupName` and a Monday schedule — for
  the `github-actions` manager, for `node` (the Dockerfile base image), and
  for `@playwright/cli` — so all three land in a single weekly PR that none
  of the automerge rules touch.
- `docker:pinDigests` in `extends`, so Renovate's own PR adds the digest pin
  to `FROM node:24-trixie` (and keeps it current afterwards) rather than a
  digest guessed and hand-pinned here; that PR falls into the same weekly
  group as the other `node` updates via the package rule above.

Ran `npx -p renovate renovate-config-validator renovate.json` — validates
cleanly. Ran `scripts/check.sh` (shellcheck + all bats suites, including a
real image build) — all green; the `Dockerfile` edit only moved comments, so
no test needed to change.

All three remaining boxes need a live Renovate run against the real
`todofixme/claude-in-a-box` repo to confirm, not just local config checking:
automerge actually firing on the next Claude Code or ccstatusline release,
the base image's first digest-pin PR landing, and a weekly run bundling
`node`, the Actions and `@playwright/cli` into one PR. `gh` isn't
authenticated in this environment (`gh auth status` fails), so I couldn't
check the live repo myself — a human should watch the next few Renovate runs
and tick these once seen, the same way 02 stayed `ready-for-human` until its
live GHCR pull was confirmed.

### Review

`/code-review` ran both axes against the original ticket text. Spec: no
findings — confirmed independently that the regex matches all three ARGs,
that automerge is scoped to only `@anthropic-ai/claude-code` and
`ccstatusline`, and that the three weekly-group rules correctly share one
`groupName`/`schedule`. Standards: no hard violations against `GLOSSARY.md`
or any ADR; one judgement call — the three weekly-group `packageRules`
repeated `automerge: false` even though that's already `config:recommended`'s
default, a small duplicated-fields smell. Dropped the redundant key from all
three rules; re-ran `renovate-config-validator`, still clean.
