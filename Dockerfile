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

# Maven and Gradle read the Host's dependencies through read-only mounts and
# write into Box Caches of their own (ADR-0003). The paths are the Image's and
# claude-box mounts onto them; they exist empty so that a Box started without
# those mounts still builds, and belong to claude so that docker seeds the Box
# Cache volumes from them with the right owner.
#
# GRADLE_RO_DEP_CACHE names the directory containing modules-2, not modules-2
# itself. maven.repo.local.tail is Maven 3.9's chained local repository, whose
# tails are read-only; ignoreAvailability makes Maven use what the tail has
# even when the Host downloaded it from a remote repository this build does
# not declare, which is the point of sharing the Host's repository at all.
# MAVEN_USER_HOME is what the Maven wrapper reads, so its distributions land
# in the Box Cache instead of the claude-home volume.
#
# The same two properties go into MAVEN_ARGS and MAVEN_OPTS because which one
# a Workspace honours depends on its wrapper: a script-based mvnw reaches
# Maven's own `mvn`, which reads MAVEN_ARGS, while an mvnw with a
# maven-wrapper.jar launches Maven itself and passes on only MAVEN_OPTS, where
# the two -D land as JVM system properties. A build that overwrites MAVEN_OPTS
# for its own reasons still has MAVEN_ARGS.
ARG MAVEN_LOCAL_REPOSITORY_ARGS="-Dmaven.repo.local=/box-caches/maven/repository -Dmaven.repo.local.tail=/host-caches/maven/repository -Dmaven.repo.local.tail.ignoreAvailability=true"
ENV GRADLE_USER_HOME=/box-caches/gradle \
  GRADLE_RO_DEP_CACHE=/host-caches/gradle \
  MAVEN_USER_HOME=/box-caches/maven \
  MAVEN_ARGS="${MAVEN_LOCAL_REPOSITORY_ARGS}" \
  MAVEN_OPTS="${MAVEN_LOCAL_REPOSITORY_ARGS}"
RUN mkdir -p \
    /box-caches/gradle \
    /box-caches/maven/repository \
    /host-caches/gradle/modules-2 \
    /host-caches/maven/repository \
  && chown -R claude:claude /box-caches /host-caches

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
