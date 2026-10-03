# 09: Box Caches per Workspace instead of the Host's Maven and Gradle caches

**What to build:** Reverses the sharing half of 04. Nothing of the Host's home
is mounted into a Box any more: Maven and Gradle download into `~/.m2` and
`~/.gradle` inside the Box, and `claude-box` mounts a Box Cache of the
Workspace on each, the way it already does for the Box's Docker data. That
drops `GRADLE_RO_DEP_CACHE` (an incubating Gradle feature), the
`maven.repo.local.tail` machinery with its Maven 3.9 requirement and its
`MAVEN_ARGS`/`MAVEN_OPTS` duplication, the Gradle metadata-generation
asymmetry, and the privileged-remount path into the Host's caches — the Image
configures neither tool at all. The price, accepted deliberately: every
Workspace downloads its own dependencies once and keeps its own copy on disk.

**Blocked by:** 04

**Model:** opus

**Status:** resolved

- [x] No directory of the Host's home reaches the Box; the Host's `~/.m2` and `~/.gradle` are invisible in it
- [x] A Gradle build in the Box keeps its dependency cache and the wrapper's distributions in the Workspace's Box Cache
- [x] A Maven build in the Box keeps its local repository and the wrapper's distributions in the Workspace's Box Cache
- [x] A second Box on the same Workspace finds what the first one downloaded; another Workspace has its own caches
- [x] The Image sets no Maven or Gradle environment: `~/.m2` and `~/.gradle` in the Box are the caches, owned by `claude`
- [x] An ADR records the reversal and supersedes ADR-0003; README and `--help` match the new behaviour

## Comments

### Confirmed

Verified by hand on 2026-10-04 with the two throwaway projects 04 was checked
with, each in its own Workspace:

- Gradle, first Box: `~/.gradle` and `~/.m2` start empty, the wrapper
  downloads the 8.10.2 distribution (146 MB in `~/.gradle/wrapper/dists`) and
  the build resolves its dependencies. Second Box on the same Workspace:
  `./gradlew --offline` green, both jars found in the Workspace's Box Cache,
  both directories owned by `claude`.
- Maven, first Box: 77 `Downloading from` lines — plugins and dependencies —
  into `~/.m2/repository`, and the wrapper's Maven into `~/.m2/wrapper`.
  Second Box: `./mvnw -o` green.
- `env | grep -E "MAVEN_|GRADLE_"` in a Box finds nothing: the Image
  configures neither tool, which is the point of the design.

The automated suite covers the rest: the argv has no `:ro` mount and nothing
of `$HOME`, the Box Caches are named per Workspace and stable across starts,
the Host's home path does not exist inside a Box, markers written in one Box
are found by the next and not by another Workspace's, `~/.m2` and `~/.gradle`
belong to `claude` in the Image, and `--help` offers no cache settings because
there are none.

### Notes

- The three environment variables 04 introduced (`CLAUDE_BOX_HOST_HOME`,
  `CLAUDE_BOX_MAVEN_VOLUME`, `CLAUDE_BOX_GRADLE_VOLUME`) are gone. Per-Workspace
  names are derived from the Workspace path, so a test in a temporary
  Workspace gets its own Box Caches without being told.
- 05 specified the Host's npm cache and pnpm store as read-write Host Caches,
  which would have rebuilt the pattern this ticket removed. Its spec now reads
  the same way as this one: npm cache, pnpm store and the Playwright browser
  cache are Box Caches of the Workspace. The argument for the exception stays
  on record in ADR-0003, since npm and pnpm verify their contents against the
  lockfile hash.
- With that, nothing in the project has a Host Cache, so the term is out of
  the GLOSSARY and **Box Cache** says per Workspace rather than shared. The
  superseded ADR-0003 and ticket 04 still use the old word; they are history
  and explain themselves.
