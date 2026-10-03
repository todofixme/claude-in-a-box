# Claude in a Box

A sandbox in which Claude Code works in YOLO mode on TypeScript/React and Kotlin/Spring Boot projects without endangering the developer's machine.

## Language

**Image**:
The built artifact published to GHCR from which every Box is started.
_Avoid_: container image, sandbox image

**Box**:
A running container started from the Image, in which Claude works.
_Avoid_: sandbox, container, devcontainer

**Host**:
The developer's machine on which the Box runs.
_Avoid_: Mac, local machine

**Workspace**:
The project directory on the Host that is mounted into the Box and that Claude works on.
_Avoid_: project, repo, mount

**Test Container**:
A container started by Testcontainers inside a Box during backend tests.
_Avoid_: sidecar, service container

**Host Cache**:
A build cache of the Host (e.g. Maven, Gradle or npm dependencies) that a Box reuses.
_Avoid_: shared cache, mount

**Box Cache**:
A build cache owned by Boxes and shared among them; the Host never reads it.
_Avoid_: volume, container cache
