# Box Caches per Workspace, nothing of the Host's

Supersedes [ADR-0003](0003-host-caches-read-only.md), which had the Box reuse the Host's Maven repository and Gradle dependency cache through read-only mounts. Building that showed the price: `GRADLE_RO_DEP_CACHE` is an incubating Gradle feature, it only serves entries whose metadata the running Gradle's own generation wrote, `maven.repo.local.tail` needs Maven 3.9 and is ignored by any `mvnw` that carries a `maven-wrapper.jar` unless the same properties also ride in `MAVEN_OPTS`, and a privileged Box can `mount -o remount,rw` its way into the Host's cache anyway. So Maven and Gradle now download into `~/.m2` and `~/.gradle` inside the Box, where one Box Cache per Workspace keeps them for the next Box, and nothing of the Host's home is mounted at all.

## Considered Options

- **The Host's caches read-only** (ADR-0003): most reuse, at the cost above. It also made the sandbox depend on cache formats of two tools rather than on a volume.
- **Box Caches shared by every Box**: fewer downloads than per Workspace, but one cache that every Workspace writes to, so a poisoned entry reaches every later build in every Workspace. [agentbox](https://github.com/fletchgqc/agentbox) keeps its caches per container for the same reason.

## Consequences

Every Workspace downloads its dependencies once and keeps its own copy, Gradle distribution included — more traffic and more disk than sharing, which is accepted deliberately. Dependencies that only the Host has are no longer reachable: a Workspace resolving from a private repository whose credentials live in the Host's `settings.xml` or `gradle.properties` would not build in a Box, since those files are not mounted either. This project's Workspaces use public dependencies.

The Image configures neither tool, so there is nothing to keep in step with a Maven or Gradle version: the mechanism is two volumes mounted onto the two directories the tools use by default.

Ticket 05 extended the same per-Workspace Box Cache mechanism to npm, pnpm and Playwright. npm and Playwright need no configuration for the same reason Maven and Gradle don't: the volumes sit where each already looks by default. pnpm is the one exception found so far — left to itself it ignores `$HOME` and picks a store path on whatever filesystem the current Workspace happens to sit on, so the Image points pnpm's `store-dir` at the volume through pnpm's own config file. That one setting doesn't change the rule this ADR records: still no cache of the Host's reaches a Box, and still one Box Cache per Workspace rather than one shared by all of them.
