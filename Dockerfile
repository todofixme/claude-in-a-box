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

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && npm cache clean --force

# Managed settings outrank anything in the claude-home volume, so the pinned
# version holds even after a developer has used the Box for a while.
COPY image/managed-settings.json /etc/claude-code/managed-settings.json

USER claude
WORKDIR /home/claude
