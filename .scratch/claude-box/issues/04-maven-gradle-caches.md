# 04: Host Caches and Box Caches for Maven and Gradle

**What to build:** Backend builds in the Box reuse the dependencies the Host has already downloaded without being able to modify anything the Host later executes (ADR-0003). The Host's Maven local repository and Gradle dependency cache (`modules-2`) are bind-mounted read-only on every run; Gradle uses them as read-only dependency cache with its own Gradle user home in a Box Cache, Maven uses the Host repository as read-only tail with its own local repository in a Box Cache. Gradle wrapper distributions live only in a Box Cache. Missing Host directories are created empty instead of blocking the start. Parent directories (`~/.gradle`, `~/.m2`) are never mounted.

**Blocked by:** 03

**Model:** opus

**Status:** ready-for-agent

- [ ] A Gradle build in the Box resolves dependencies present on the Host without downloading them
- [ ] A Maven build in the Box resolves dependencies present on the Host without downloading them
- [ ] Dependencies missing on the Host are downloaded into a Box Cache and reused by the next Box
- [ ] The Box cannot write into the Host's Maven repository or Gradle cache
- [ ] `~/.gradle/init.d`, `gradle.properties`, `settings.xml` and wrapper dists of the Host are not visible in the Box
- [ ] A missing Host cache directory is created empty and the Box starts normally
