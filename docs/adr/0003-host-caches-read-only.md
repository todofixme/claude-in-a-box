# Mount Host Caches read-only where the Host executes their contents

The Box should reuse dependencies the Host has already downloaded, but must not write into directories whose contents the Host later executes. `~/.m2/repository` and `~/.gradle/caches/modules-2` are therefore mounted read-only; writes go to Box Caches (Gradle via `GRADLE_RO_DEP_CACHE` plus its own `GRADLE_USER_HOME`, Maven via `maven.repo.local.tail`). The npm cache and pnpm store stay read-write because both verify contents against the lockfile hash on read. Parent directories (`~/.gradle`, `~/.m2`) are never mounted, since they contain `init.d/`, `gradle.properties` and `settings.xml` with credentials.

## Considered Options

- **Host Caches read-write**: maximum reuse, but Maven and Gradle do not re-verify existing cache entries, so a swapped JAR would run in the Host's next build. Gradle also does not support several machines writing to the same cache concurrently.
- **Box Caches only**: safe, but every new Box downloads everything again.

## Consequences

`~/.gradle/wrapper/dists` and the Playwright browser cache are not mounted from the Host: the Host executes wrapper distributions directly, and the Host's Playwright cache holds macOS builds under the same names Linux expects.

The read-only mount stops builds and accidents, not a deliberate attempt: the Box is privileged (ADR-0001) and `claude` has passwordless `sudo`, so `mount -o remount,rw` inside the Box makes the Host's cache writable again. CAP_SYS_ADMIN is what dockerd needs and what remounting needs, so the two cannot be had separately. Anything stronger would mean not mounting the Host's caches at all.
