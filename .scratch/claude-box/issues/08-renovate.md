# 08: Renovate keeps Claude Code current

**What to build:** Renovate (Mend GitHub App) opens PRs whenever a new version of Claude Code, ccstatusline or `@playwright/cli` is published, and for base image digest and GitHub Actions updates. Claude Code and ccstatusline updates are automerged once the PR build is green, so the push to `main` publishes a new Image. Base image, Actions and `@playwright/cli` updates are grouped into one weekly PR without automerge.

Human steps: install the Mend Renovate app on the repo and merge its onboarding PR.

**Blocked by:** 02, 05, 07

**Model:** sonnet

**Status:** ready-for-human

- [ ] Renovate detects the pinned versions of Claude Code, ccstatusline and `@playwright/cli`
- [ ] A Claude Code update PR is automerged after the PR build passes and results in a new `claude-<version>` Image in GHCR
- [ ] Base image digest is pinned and updated by Renovate
- [ ] Base image, Actions and `@playwright/cli` updates arrive as one weekly grouped PR, not automerged
