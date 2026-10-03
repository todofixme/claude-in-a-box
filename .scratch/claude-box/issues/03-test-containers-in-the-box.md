# 03: Backend tests with Test Containers in the Box

**What to build:** Claude can run Kotlin/Spring Boot backend tests that use Testcontainers inside the Box. The Image contains JDK 21 (Debian apt) and Docker Engine with the Compose plugin (Docker's apt repo). The Box runs with `--privileged` and the entrypoint starts its own `dockerd` before dropping to user `claude`, who is in the `docker` group (Docker-in-Docker, see ADR-0001; the Host's Docker socket is never mounted). The inner Docker data lives in one volume per Workspace so Test Container images are cached between runs; `claude-box` refuses to start a second Box on a Workspace that already has one running. No Gradle or Maven installation in the Image: projects bring their wrappers.

**Blocked by:** 01

**Model:** opus

**Status:** ready-for-agent

- [ ] `java -version` in the Box reports 21
- [ ] `docker run hello-world` works in the Box as user `claude`; `docker compose version` works
- [ ] A Spring Boot test using Testcontainers (e.g. PostgreSQL) passes in the Box
- [ ] A second run of that test does not re-pull the Test Container image
- [ ] Starting a second Box on the same Workspace fails with a clear message; Boxes on different Workspaces run side by side
- [ ] The Host's Docker socket is not mounted
- [ ] README documents the privileged mode and per-Workspace Docker data volume
