# 04: Host Caches and Box Caches for Maven and Gradle

**What to build:** Backend builds in the Box reuse the dependencies the Host has already downloaded without being able to modify anything the Host later executes (ADR-0003). The Host's Maven local repository and Gradle dependency cache (`modules-2`) are bind-mounted read-only on every run; Gradle uses them as read-only dependency cache with its own Gradle user home in a Box Cache, Maven uses the Host repository as read-only tail with its own local repository in a Box Cache. Gradle wrapper distributions live only in a Box Cache. Missing Host directories are created empty instead of blocking the start. Parent directories (`~/.gradle`, `~/.m2`) are never mounted.

**Blocked by:** 03

**Model:** opus

**Status:** ready-for-human

- [x] A Gradle build in the Box resolves dependencies present on the Host without downloading them
- [x] A Maven build in the Box resolves dependencies present on the Host without downloading them
- [x] Dependencies missing on the Host are downloaded into a Box Cache and reused by the next Box
- [ ] The Box cannot write into the Host's Maven repository or Gradle cache
- [x] `~/.gradle/init.d`, `gradle.properties`, `settings.xml` and wrapper dists of the Host are not visible in the Box
- [x] A missing Host cache directory is created empty and the Box starts normally

## Comments

### Confirmed

Verified by hand on 2026-10-03, because no test in the suite can run a real
build:

- A Gradle 8.10.2 build in a Box, `--offline` and with an empty Box Cache,
  compiled against `org.slf4j:slf4j-api:2.0.16` straight out of the Host's
  read-only cache. The jar was not copied into the Box Cache: Gradle read it
  where it lies.
- `org.tinylog:tinylog-api:2.7.0`, on neither Host cache, was downloaded by
  one Box into the Box Cache, and the next Box compiled against it
  `--offline`.
- A Maven 3.9.6 build through an `mvnw` with a `maven-wrapper.jar`, `-o`,
  resolved `slf4j-api:2.0.9` and every lifecycle plugin from the Host's
  repository as a read-only tail, with the Box's own local repository staying
  completely empty. Adding `tinylog` produced exactly two `Downloading from
  central` lines, both for `tinylog`, which then landed in the Box Cache and
  was reused offline by the next Box.
- `MAVEN_USER_HOME` is honoured by that wrapper, so the Maven distribution it
  downloads lands in the Box Cache and not in the `claude-home` volume.

Two things that verification taught, both now in the README:

- Gradle only reuses Host entries whose metadata the running Gradle's own
  format wrote. `slf4j-api:2.0.17` sat in the Host's `metadata-2.107` (written
  by a Gradle 9 project) and Gradle 8.10.2, which reads `metadata-2.106`,
  downloaded it instead. Nothing to fix; it is how the read-only dependency
  cache works.
- `MAVEN_ARGS` alone is not enough. An `mvnw` with a `maven-wrapper.jar`
  launches Maven itself rather than running Maven's `mvn` script, and passes
  on only `MAVEN_OPTS` — so the first attempt silently ignored the whole
  split and failed offline. The Image now puts the same two properties in
  both variables.

### Review

`/code-review` ran both axes against this ticket. Findings acted on:

- **The read-only mount is not a wall against the Box.** The Spec axis
  remounted it: `sudo mount -o remount,rw /host-caches/maven/repository` in a
  Box, then wrote a file that appeared on the Host. Reproduced. CAP_SYS_ADMIN
  is what dockerd needs (ADR-0001) and what remounting needs, so a privileged
  Box with passwordless `sudo` can always undo `:ro`; nothing short of not
  mounting the Host's caches closes it. ADR-0003 and the README now say so,
  and the README offers `CLAUDE_BOX_HOST_HOME` pointed at an empty directory
  as the way out. This is why the fourth criterion is still unchecked — see
  below.
- `CLAUDE_BOX_HOST_HOME=""` fell back to `$HOME` through `${VAR:-...}`, so the
  one setting meant to keep the Host's caches out of a Box quietly shared
  them. It is `${VAR-...}` now and an empty value fails the start, with a test.
  Both axes found this independently.
- The two "reads the Host Cache but cannot write to it" tests were the same
  ten lines twice, one reaching the path through `$GRADLE_RO_DEP_CACHE` and
  the other hardcoding it. They are now one `host_cache_is_read_only` helper
  and two one-line tests.
- `BOX_HOST_MAVEN_REPOSITORY` and `BOX_MAVEN_CACHE` read as "Box host" and
  said nothing about which cache they are. They are `BOX_HOST_CACHE_MAVEN`,
  `BOX_HOST_CACHE_GRADLE`, `BOX_CACHE_MAVEN` and `BOX_CACHE_GRADLE`: `BOX_` is
  a path in the Box, and the glossary's two terms name the rest.
- `ARG MAVEN_REPOSITORY_SPLIT` named neither the flags nor the paths; it is
  `MAVEN_LOCAL_REPOSITORY_ARGS`. It stays an `ARG` so the two `ENV` values
  cannot drift apart.
- The wrapper explanation was written twice, in the `Dockerfile` and in
  `tests/image.bats`. The test now points at the `Dockerfile`.
- Maven's tail needs Maven 3.9+, which the README did not say while it did say
  the analogous Gradle caveat. It says both now.

Findings noted and kept as they are:

- `CLAUDE_BOX_MAVEN_VOLUME` and `CLAUDE_BOX_GRADLE_VOLUME` name a Box Cache by
  the word the glossary tells us to avoid. What the developer passes is a
  docker volume name, `CLAUDE_BOX_HOME_VOLUME` already set that shape, and the
  prose around them says Box Cache.
- The three new variables are not in the ticket, but `tests/box.bats` cannot
  touch a developer's real `~/.m2` and `~/.gradle`, and nothing else gives it
  a Host home and Box Caches of its own.

### Open for the human

Five criteria are met. The fourth — "The Box cannot write into the Host's
Maven repository or Gradle cache" — is true of every build and of anything
Claude does by accident, and false against a deliberate `sudo mount -o
remount,rw`. The limit is now recorded in ADR-0003 and the README rather than
papered over, and the decision is yours:

- accept it as the price of a privileged Box and tick the box, or
- have the Host's caches not mounted at all by default, with
  `CLAUDE_BOX_HOST_HOME` as the opt-in rather than the opt-out.

Nothing else blocks 05, which only needs the Host Cache pattern this ticket
establishes.
