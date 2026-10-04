# 06: CLI tools and Git identity

**What to build:** The Box contains `git`, `gh` (GitHub's apt repo), `glab`, `jq`, `yq`, `ripgrep`, `httpie` and `curl` (Debian apt otherwise). Claude commits locally under the developer's name and email, taken from the Host's Git config by `claude-box`; it never gets push credentials. If `CLAUDE_BOX_GH_TOKEN` or `CLAUDE_BOX_GITLAB_TOKEN` is set on the Host, it is passed in as the token for `gh` / `glab` (intended as read-only fine-grained tokens); otherwise no token enters the Box.

**Blocked by:** 01

**Model:** sonnet

**Status:** resolved

- [x] All listed tools are on the PATH in the Box
- [x] A commit made by Claude in the Box carries the Host's Git name and email
- [x] `git push` from the Box fails for lack of credentials
- [x] With `CLAUDE_BOX_GH_TOKEN` set, `gh issue list` works; without it, no GitHub/GitLab token env var exists in the Box
- [x] README documents the token variables and recommends read-only scopes

## Comments

`gh` comes from its own apt repository (the same pattern Docker Engine
already uses in the `Dockerfile`); `git`, `glab`, `jq`, `yq`, `ripgrep` and
`httpie` are already in Debian's own repository. `claude-box` now reads
`user.name`/`user.email` from the Host's own `git config` (so a
Workspace-local config wins the way it always does for `git` itself) and
passes them into the Box as `GIT_AUTHOR_NAME`/`EMAIL` and
`GIT_COMMITTER_NAME`/`EMAIL`; no SSH key or HTTPS credential ever enters the
Box, so `git push` fails there for lack of them. `CLAUDE_BOX_GH_TOKEN` and
`CLAUDE_BOX_GITLAB_TOKEN`, read from the Host, pass into the Box as
`GH_TOKEN`/`GITLAB_TOKEN` — which `gh`/`glab` read directly — only when set;
unset, the variable does not exist in the Box at all. README documents both,
recommending a read-only, fine-grained token for each.

Verified in a real Box (`tests/box.bats`), not just via `--dry-run`: tool
presence, a real commit's `git log` author/committer, a real `git push`
against a real GitHub remote failing with "Permission denied (publickey)",
and `GH_TOKEN`/`GITLAB_TOKEN` reaching the Box's `env` only when set.

### Review

`/code-review` ran both axes against this ticket. Findings acted on:

- The new apt-repository comment conflated two unrelated rationales (why
  `gh` needs its own repository, and the git-identity feature in
  `bin/claude-box`) in one run-on sentence. Trimmed to the one reason the
  comment is actually there for.
- The Dockerfile's new CLI-tools block reinstalled `ca-certificates curl
  gnupg`, already installed by the Docker Engine block above it. Removed;
  `curl` itself is also dropped from the final install line, since that
  earlier block already installs it.
- `bin/claude-box` had four near-identical `if [ -n "$x" ]; then
  docker_argv+=(-e ...); fi` blocks for the Git identity and token
  variables. Replaced with one `pass_env_if_set` helper, in the style of the
  existing `die`/`digest_of` helpers.

Findings noted and kept as they are:

- The acceptance criterion's "`gh issue list` works" half needs a real,
  valid `CLAUDE_BOX_GH_TOKEN` and a real repository; no agent can supply
  either. The env-var plumbing it depends on (`GH_TOKEN` reaching the Box
  only when `CLAUDE_BOX_GH_TOKEN` is set on the Host, and not otherwise) is
  verified in a real Box. The same gap exists for `glab`, by the same
  reasoning. This mirrors 01's and 04's unconfirmable-by-agent criteria:
  please confirm by hand with a real token.
- `bin/claude-box` resolves the Host's Git identity by running `git config`
  in whatever directory the script itself was invoked from, which is always
  the Workspace (`workspace="$(pwd -P)"` reads the same `pwd`). This makes
  "Workspace-local config wins" implicit rather than explicit, but it is
  correct as long as `claude-box` keeps being run from the Workspace, which
  the rest of the script already assumes throughout.
