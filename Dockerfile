FROM node:24-trixie

# The one place the Claude Code version is pinned.
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.288

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

# JDK only: Kotlin/Spring Boot projects bring their own Gradle or Maven
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

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && npm cache clean --force

# Managed settings outrank anything in the claude-home volume, so the pinned
# version holds even after a developer has used the Box for a while.
COPY image/managed-settings.json /etc/claude-code/managed-settings.json

# The Box starts as root only so that the entrypoint can bring up dockerd; it
# drops to claude before running anything the Box was started for.
COPY image/entrypoint.sh /usr/local/bin/box-entrypoint
USER root
WORKDIR /home/claude
ENTRYPOINT ["box-entrypoint"]
