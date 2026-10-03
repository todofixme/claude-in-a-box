# 03: Backend tests with Test Containers in the Box

**What to build:** Claude can run Kotlin/Spring Boot backend tests that use Testcontainers inside the Box. The Image contains JDK 21 (Debian apt) and Docker Engine with the Compose plugin (Docker's apt repo). The Box runs with `--privileged` and the entrypoint starts its own `dockerd` before dropping to user `claude`, who is in the `docker` group (Docker-in-Docker, see ADR-0001; the Host's Docker socket is never mounted). The inner Docker data lives in one volume per Workspace so Test Container images are cached between runs; `claude-box` refuses to start a second Box on a Workspace that already has one running. No Gradle or Maven installation in the Image: projects bring their wrappers.

**Blocked by:** 01

**Model:** opus

**Status:** resolved

- [x] `java -version` in the Box reports 21
- [x] `docker run hello-world` works in the Box as user `claude`; `docker compose version` works
- [x] A Spring Boot test using Testcontainers (e.g. PostgreSQL) passes in the Box
- [x] A second run of that test does not re-pull the Test Container image
- [x] Starting a second Box on the same Workspace fails with a clear message; Boxes on different Workspaces run side by side
- [x] The Host's Docker socket is not mounted
- [x] README documents the privileged mode and per-Workspace Docker data volume

## Comments

### Review

`/code-review` ran both axes against this ticket. Findings acted on:

- `GLOSSARY.md` requires Workspace, not "project", and Test Container, not
  "container". The README, the `Dockerfile` comment and two test names said
  "projects bring their wrappers"; they now speak of a Workspace, and the
  README says Test Container images where it meant them.
- The entrypoint did `start_dockerd || true`: a Box whose daemon never came
  up started Claude anyway, and the criterion would have failed later as an
  opaque Testcontainers error. It now fails the start. The unprivileged case
  is already separate — the capability check means we never try there.
- `bin/claude-box` only looked for a *running* Box of the Workspace's name, so
  a Box that had not cleaned up after itself fell through to docker's
  "container name is already in use" — the message this ticket exists to
  replace. The two cases now have two messages, and a test each.
- `privileged()` in the entrypoint tested only CAP_SYS_ADMIN; it is
  `has_cap_sys_admin` now, which is what it actually asks.
- The dockerd wait loop counted 0.2s ticks and needed `TIMEOUT * 5` to
  compare. It uses `SECONDS` against a deadline.
- The "second Workspace" dance (`make_workspace`, `cd`, `rm -rf`) was in three
  tests, and the variant that did not `cd` back left teardown in a removed
  directory, which leaked two Docker data volumes per run. It is
  `enter_other_workspace` / `leave_other_workspace` in `tests/helper.bash`.
- The README promised "proper caches follow in a later version" and cited
  ADR-0003 for it. That is 04's territory and ADR-0003 says nothing about it;
  the paragraph now states only where wrapper downloads land today.
- README now says `docker exec` into a running Box lands as root, since the
  Image's user is root and only the entrypoint drops to `claude`.

Findings noted and kept as they are:

- dockerd is SIGKILLed when the Box ends, because the entrypoint `exec`s the
  command as PID 1. A supervisor that stops dockerd gracefully would have to
  forward signals to Claude's TUI correctly, which is a worse risk than an
  ungraceful stop of a daemon whose data is crash-consistent. `docker:dind`
  makes the same trade. Stopped Test Containers do accumulate in the
  Workspace's volume; the README says how to reclaim that disk.
- `workspace_box_name` and `workspace_docker_volume` parse `--dry-run` with
  the same shape of `sed`. Two one-line helpers reading different values; a
  shared parser would be indirection for nothing.
- "the Box name and Docker data volume are the same on every start" was
  called tautological. Each call is a separate `claude-box` process, and the
  test is what would catch a name built from `$$` or a timestamp, which the
  "another Workspace" test would not.

### Confirmed

Verified by hand on 2026-10-03, because no test in the suite can:

- A Kotlin/Spring Boot project generated from start.spring.io with
  `spring-boot-testcontainers` and a `@ServiceConnection PostgreSQLContainer`
  ran `./mvnw test` green inside a Box: JDK 21.0.12, Postgres 18.6 answering
  `select version()` over JDBC from the Test Container.
- A second Box on the same Workspace ran the same test with no
  "Pulling image layers" at all — straight to "Creating container for image:
  postgres:latest". The Workspace's Docker data volume is what carried it.
- An interactive Box (`--shell` under a pty) gets `/dev/pts/0` owned by
  `claude`, so Claude's TUI can reopen its terminal after the entrypoint has
  dropped privileges.

The automated suite covers the rest: `java -version`, `docker run
hello-world` and `docker compose version` as `claude`, images surviving into
the next Box, the one-Box-per-Workspace refusal in both its forms, Boxes on
other Workspaces unaffected, and no `docker.sock` in the argv.

All seven criteria are met and this ticket is resolved, which unblocks 04.
