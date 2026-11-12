FROM node:24-trixie@sha256:6e5d4c38403930b420404f190be8563396dca2bd156a6cb4722707b0efcf6fc1

# The one place the Claude Code version is pinned.
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.322

# `claude` must own its home directory, because the claude-home volume is
# seeded from it. node:24 already holds UID/GID 1000 with the `node` user, so
# rename that one rather than creating a second user beside it. This leaves no
# `node` user or group behind: anything expecting those names needs `claude`.
RUN usermod --login claude --home /home/claude --move-home node \
  && groupmod --new-name claude node \
  && apt-get update \
  && apt-get install -y --no-install-recommends sudo \
  && rm -rf /var/lib/apt/lists/* \
  && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude \
  && chmod 0440 /etc/sudoers.d/claude

# JDK only: a Kotlin/Spring Boot Workspace brings its own Gradle or Maven
# wrapper, and a Gradle or Maven of the Image's choosing would only compete
# with it. Headless because nothing in a Box draws on a screen.
RUN apt-get update \
  && apt-get install -y --no-install-recommends openjdk-21-jdk-headless \
  && rm -rf /var/lib/apt/lists/*

# Docker Engine, for the dockerd each Box starts for itself (ADR-0001). From
# Docker's own repository rather than Debian's docker.io, because the Compose
# plugin is only packaged there.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
  && install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian %s stable\n' \
    "$(dpkg --print-architecture)" \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" \
    > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    containerd.io docker-ce docker-ce-cli docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/* \
  && usermod --append --groups docker claude

# `gh`'s own apt repository, the same pattern as Docker's above, because
# Debian does not package it. `git`, `glab`, `jq`, `yq`, `ripgrep` (binary
# `rg`), `httpie` (binary `http`), `shellcheck` and `rsync` are already in
# Debian's own repository, so no extra repository is needed for those; `curl`
# is too, but is already installed by the Docker Engine step above.
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    git gh glab jq yq ripgrep httpie shellcheck rsync \
  && rm -rf /var/lib/apt/lists/*

# `psql` 18 from the PostgreSQL project's own apt repository (PGDG), the same
# pattern as Docker's and gh's above, because Debian trixie only packages the
# 17 client. Client only: a Workspace that needs a server runs one in the
# Box's dockerd. Debian's postgresql-common wrapper puts `psql` on the PATH
# and resolves it to the newest installed client, which is this one.
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    -o /etc/apt/keyrings/postgresql.asc \
  && chmod a+r /etc/apt/keyrings/postgresql.asc \
  && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/postgresql.asc] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' \
    "$(dpkg --print-architecture)" \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" \
    > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client-18 \
  && rm -rf /var/lib/apt/lists/*

# Maven and Gradle download into ~/.m2 and ~/.gradle, and claude-box mounts a
# Box Cache of the Workspace onto each (ADR-0004). The two exist here so that
# docker seeds those volumes with claude as their owner; beyond that the Image
# configures neither tool, and no cache of the Host's reaches a Box.
RUN install -d -o claude -g claude /home/claude/.m2 /home/claude/.gradle

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && npm cache clean --force

# Corepack ships with Node and resolves `pnpm`/`yarn` to the exact version a
# Workspace declares in its "packageManager" field, downloading that version
# on first use. There is nothing to pin here: the Workspace pins it.
RUN corepack enable

# ccstatusline renders Claude's status line (wired up below via managed
# settings), pinned version so an update only ever reaches a Box through this
# Image. A developer's own layout lives in ~/.config/ccstatusline, which the
# claude-home volume already covers, so nothing further is needed here for it
# to survive a Box restart.
# renovate: datasource=npm depName=ccstatusline
ARG CCSTATUSLINE_VERSION=2.2.34
RUN npm install -g "ccstatusline@${CCSTATUSLINE_VERSION}" \
  && npm cache clean --force

# Playwright CLI, pinned version, so Claude can drive a browser directly,
# together with the Chromium build that version of Playwright expects and the
# system libraries it needs. The browser is baked in so that it is there in
# every Box from the first second, rather than downloaded into each new
# Workspace's Box Cache on first use.
#
# It goes to /opt/ms-playwright, not ~/.cache/ms-playwright: the Playwright
# Box Cache is mounted over the latter and would hide it. PLAYWRIGHT_BROWSERS_PATH
# is set for this one step only, so a Workspace's own `@playwright/test` still
# downloads its matching browser into the Box Cache as before.
#
# Chromium rather than Google Chrome, which Playwright CLI defaults to: Chrome
# is not available for linux/arm64. The two PLAYWRIGHT_MCP_* variables point
# Playwright CLI at this Chromium so that no call needs `--browser chromium`.
# The executable's path contains Playwright's browser revision, which changes
# with every Playwright CLI update, hence the stable symlink. `--no-shell`
# skips the separate headless shell build: Playwright CLI is given the full
# Chromium executable, which runs headless just as well.
#
# The package's own `playwright-cli` skill goes to Claude Code's managed skills
# directory, which every Box loads and the claude-home volume does not cover,
# so it always matches the installed version. Copied rather than installed
# with `playwright-cli install --skills`, which writes into the current
# directory and downloads a second Chromium into the Playwright cache.
# renovate: datasource=npm depName=@playwright/cli
ARG PLAYWRIGHT_CLI_VERSION=0.1.24
RUN npm install -g "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" \
  && npm cache clean --force \
  && install -d /etc/claude-code/.claude/skills \
  && cp -r "$(npm root -g)/@playwright/cli/skills/playwright-cli" /etc/claude-code/.claude/skills/ \
  && [ -f /etc/claude-code/.claude/skills/playwright-cli/SKILL.md ] \
  && PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    "$(npm root -g)/@playwright/cli/node_modules/.bin/playwright" install --with-deps --no-shell chromium \
  && chromium="$(find /opt/ms-playwright -path '*/chromium-*/chrome-linux*/chrome' -type f)" \
  && [ "$(printf '%s\n' "$chromium" | wc -l)" -eq 1 ] \
  && [ -x "$chromium" ] \
  && ln -s "$chromium" /opt/ms-playwright/chromium \
  && rm -rf /var/lib/apt/lists/*
ENV PLAYWRIGHT_MCP_BROWSER=chromium \
  PLAYWRIGHT_MCP_EXECUTABLE_PATH=/opt/ms-playwright/chromium

# codebase-memory-mcp serves the Code Graph of a Workspace (ADR-0005). Pinned
# here and nowhere else, downloaded from the upstream release and verified
# against that release's own `checksums.txt` before anything is unpacked; the
# ARG carries the release tag, since that is what a GitHub release is named
# by. arm64 only, because the Image targets linux/arm64. Only the binary is
# kept: the tarball's `install.sh` writes MCP client configuration, which is
# `--mcp-config`'s job per Box. `sha256sum --ignore-missing` checks the one
# asset downloaded and skips the release's other platforms; with none of them
# present it verifies nothing and fails, which is what should happen if the
# asset is ever renamed. Nothing registers the server here — a Box gets it
# only through `claude-box --code-graph`.
# renovate: datasource=github-releases depName=DeusData/codebase-memory-mcp
ARG CODEBASE_MEMORY_MCP_VERSION=v0.12.1
RUN tmp="$(mktemp -d)" \
  && cd "$tmp" \
  && base="https://github.com/DeusData/codebase-memory-mcp/releases/download/${CODEBASE_MEMORY_MCP_VERSION}" \
  && curl -fsSLO "$base/codebase-memory-mcp-linux-arm64.tar.gz" \
  && curl -fsSLO "$base/checksums.txt" \
  && sha256sum --ignore-missing --check checksums.txt \
  && tar xzf codebase-memory-mcp-linux-arm64.tar.gz codebase-memory-mcp \
  && install -m 0755 codebase-memory-mcp /usr/local/bin/codebase-memory-mcp \
  && cd / \
  && rm -rf "$tmp"

# npm's cache, pnpm's store and Playwright's browser cache all live under
# claude's home and get a Box Cache of the Workspace mounted onto them
# (ADR-0004), the same mechanism as ~/.m2 and ~/.gradle above. `install -d`
# only chowns the directories named, not the parents it creates along the
# way, so ~/.cache, ~/.local/share and ~/.config are listed too: corepack's
# own cache sits at ~/.cache/node next to ~/.cache/ms-playwright, and without
# write access there `pnpm`/`yarn` fail outright. ~/.cache/codebase-memory-mcp
# is where codebase-memory-mcp keeps a Workspace's graph and its own
# configuration by default, so a `--code-graph` Box gets a Box Cache there and
# needs no CBM_CACHE_DIR; a Box without the flag gets no volume there and
# leaves the directory empty.
RUN install -d -o claude -g claude \
  /home/claude/.npm \
  /home/claude/.cache \
  /home/claude/.cache/ms-playwright \
  /home/claude/.cache/codebase-memory-mcp \
  /home/claude/.local \
  /home/claude/.local/share \
  /home/claude/.local/share/pnpm \
  /home/claude/.config \
  /home/claude/.config/pnpm

# npm already looks under ~/.npm and Playwright under ~/.cache/ms-playwright
# by default, so those two needed no configuration. pnpm does not: without a
# store-dir set, it puts its store at the root of whatever filesystem the
# current Workspace happens to sit on, so the Box Cache mounted above would
# otherwise go unused. This is pnpm's own config file rather than the shared
# ~/.npmrc, because npm reads that file too and warns on every command about
# a "store-dir" key it does not understand.
RUN printf 'store-dir=/home/claude/.local/share/pnpm\n' > /home/claude/.config/pnpm/rc \
  && chown claude:claude /home/claude/.config/pnpm/rc

# Managed settings outrank anything in the claude-home volume, so the pinned
# version holds even after a developer has used the Box for a while.
COPY image/managed-settings.json /etc/claude-code/managed-settings.json

# Managed CLAUDE.md: what Claude needs to know about every Box, whatever the
# Workspace, so that no Workspace has to repeat it in its own CLAUDE.md. Like
# managed settings, it lives outside the claude-home volume and changes only
# with the Image.
COPY image/CLAUDE.md /etc/claude-code/CLAUDE.md

# The Box starts as root only so that the entrypoint can bring up dockerd; it
# drops to claude before running anything the Box was started for.
COPY image/entrypoint.sh /usr/local/bin/box-entrypoint
USER root
WORKDIR /home/claude
ENTRYPOINT ["box-entrypoint"]
