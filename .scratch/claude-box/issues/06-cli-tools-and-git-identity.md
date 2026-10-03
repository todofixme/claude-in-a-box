# 06: CLI tools and Git identity

**What to build:** The Box contains `git`, `gh` (GitHub's apt repo), `glab`, `jq`, `yq`, `ripgrep`, `httpie` and `curl` (Debian apt otherwise). Claude commits locally under the developer's name and email, taken from the Host's Git config by `claude-box`; it never gets push credentials. If `CLAUDE_BOX_GH_TOKEN` or `CLAUDE_BOX_GITLAB_TOKEN` is set on the Host, it is passed in as the token for `gh` / `glab` (intended as read-only fine-grained tokens); otherwise no token enters the Box.

**Blocked by:** 01

**Model:** sonnet

**Status:** ready-for-agent

- [ ] All listed tools are on the PATH in the Box
- [ ] A commit made by Claude in the Box carries the Host's Git name and email
- [ ] `git push` from the Box fails for lack of credentials
- [ ] With `CLAUDE_BOX_GH_TOKEN` set, `gh issue list` works; without it, no GitHub/GitLab token env var exists in the Box
- [ ] README documents the token variables and recommends read-only scopes
