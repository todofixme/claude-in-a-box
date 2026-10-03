# 02: CI: publish the Image to GHCR

**What to build:** Every push to `main` of the public GitHub repo `todofixme/claude-in-a-box` builds the Image on a native arm64 runner (`ubuntu-24.04-arm`) and publishes it to `ghcr.io/todofixme/claude-in-a-box` tagged `latest`, `sha-<short>` and `claude-<version>` (the pinned Claude Code version). Pull requests build the Image without publishing, so the build can serve as a required check for Renovate automerge. `claude-box` pulls from GHCR by default.

Human steps: create the GitHub repo, push, make the GHCR package public, and enable the PR build as a required status check on `main`.

**Blocked by:** 01

**Model:** sonnet

**Status:** ready-for-human

- [ ] Workflow builds on PRs without pushing
- [ ] Workflow builds and pushes on every push to `main` with the three tags
- [ ] `claude-<version>` tag matches the Claude Code version pinned in the Image definition
- [ ] GHCR package is public and pullable without login
- [ ] `claude-box` defaults to the GHCR Image
- [ ] PR build is a required status check on `main`
