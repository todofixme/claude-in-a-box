FROM node:24-trixie

# The one place the Claude Code version is pinned.
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.292

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
# `rg`) and `httpie` (binary `http`) are already in Debian's own repository,
# so no extra repository is needed for those; `curl` is too, but is already
# installed by the Docker Engine step above.
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    git gh glab jq yq ripgrep httpie \
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
ARG CCSTATUSLINE_VERSION=2.2.30
RUN npm install -g "ccstatusline@${CCSTATUSLINE_VERSION}" \
  && npm cache clean --force

# Playwright CLI, pinned version, so Claude can drive a browser directly.
# Only the system libraries headless Chromium needs are installed in the
# Image, since those are the same for every Chromium build; the browser
# binary itself is not baked in here, the same way the Image carries no
# Gradle distribution. It downloads on first use into a Box Cache of the
# Workspace, like the Workspace's own `@playwright/test` browser does.
# renovate: datasource=npm depName=@playwright/cli
ARG PLAYWRIGHT_CLI_VERSION=0.1.22
RUN npm install -g "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" \
  && npm cache clean --force \
  && "$(npm root -g)/@playwright/cli/node_modules/.bin/playwright" install-deps chromium

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
ARG CODEBASE_MEMORY_MCP_VERSION=v0.11.0
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

# The Box starts as root only so that the entrypoint can bring up dockerd; it
# drops to claude before running anything the Box was started for.
COPY image/entrypoint.sh /usr/local/bin/box-entrypoint
USER root
WORKDIR /home/claude
ENTRYPOINT ["box-entrypoint"]
