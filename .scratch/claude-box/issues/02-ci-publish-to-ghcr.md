# 02: CI: publish the Image to GHCR

**What to build:** Every push to `main` of the public GitHub repo `todofixme/claude-in-a-box` builds the Image on a native arm64 runner (`ubuntu-24.04-arm`) and publishes it to `ghcr.io/todofixme/claude-in-a-box` tagged `latest`, `sha-<short>` and `claude-<version>` (the pinned Claude Code version). Pull requests build the Image without publishing, so the build can serve as a required check for Renovate automerge. `claude-box` pulls from GHCR by default.

Human steps: create the GitHub repo, push, make the GHCR package public, and enable the PR build as a required status check on `main`.

**Blocked by:** 01

**Model:** sonnet

**Status:** ready-for-human

- [x] Workflow builds on PRs without pushing
- [x] Workflow builds and pushes on every push to `main` with the three tags
- [x] `claude-<version>` tag matches the Claude Code version pinned in the Image definition
- [ ] GHCR package is public and pullable without login
- [x] `claude-box` defaults to the GHCR Image
- [ ] PR build is a required status check on `main`

## Comments

Implemented `.github/workflows/image.yml`: one job on `ubuntu-24.04-arm`
(native, matching the Image's only platform). On `pull_request` against
`main` it builds without logging in or pushing. On `push` to `main` it logs
in to GHCR with the workflow's own `GITHUB_TOKEN` and pushes
`ghcr.io/todofixme/claude-in-a-box` tagged `latest`, `sha-<short>` (from
`GITHUB_SHA`) and `claude-<version>`, where `<version>` is read from the
Dockerfile with the same `sed` expression `tests/image.bats` already uses, so
the tag can't drift from what the Image actually has installed. A
concurrency group cancels a build still running for an older push to the same
ref.

`claude-box` already defaulted to the GHCR Image as of 01 (`DEFAULT_IMAGE` in
`bin/claude-box`); nothing to change there.

Three boxes stay unticked because they are the human steps the ticket itself
calls out, and need the GitHub repo to exist first:

- Create `todofixme/claude-in-a-box` on GitHub and push.
- Once a build has run, go to *Settings → Branches* and add a branch
  protection rule on `main` requiring the `build` job as a status check (its
  full name will show up in the picker as `Image / build`).
- Make the `claude-in-a-box` package public: *package → Package settings →
  Change visibility*. GHCR packages pushed via `GITHUB_TOKEN` are private by
  default regardless of repo visibility, so this step is needed even though
  the repo itself is public.

Ran `scripts/check.sh` (shellcheck + all 31 bats tests) — unaffected by this
change, all green. The workflow itself can't be exercised by a local test:
it only runs once pushed to a real GitHub Actions runner.

### Review

`/code-review` ran both axes against `02-ci-publish-to-ghcr.md`. Findings
acted on:

- The checkout step was named "Check out the Workspace". `GLOSSARY.md`
  reserves Workspace for the Host directory mounted into a Box; a CI
  runner's checkout is neither on a Host nor mounted into a Box. Renamed to
  "Check out the repository".
- The PR-only build step and the push-and-publish step were the same
  `docker/build-push-action` call differing only in `push`/`tags`, with
  `github.event_name` checked three times across the job. Merged into one
  step (`push: ${{ github.event_name == 'push' }}`), down to two checks.
- `cancel-in-progress: true` on the concurrency group would cancel a push to
  `main` that is already publishing, which could leave GHCR with some of the
  three tags updated and some not. Scoped it to `pull_request` only, where
  canceling a superseded build is safe; a push to `main` now always runs to
  completion.

Findings noted and kept as they are:

- The concurrency block and the README's "Continuous integration" section
  were flagged as not literally asked for by the ticket. Kept: the
  concurrency group (now push-safe) avoids wasting runners on superseded PR
  builds, and the README section is the only place a developer would learn
  the Image now comes from CI at all — ticket 01 set the precedent of
  updating the README alongside behaviour it introduces.
