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

**Box Cache**:
A build cache a Box fills and later Boxes on the same Workspace reuse; the Host never reads it, and no cache of the Host's reaches a Box.
_Avoid_: volume, container cache, host cache

**Code Graph**:
A searchable graph of a Workspace's symbols and the relationships between them, served to Claude by `codebase-memory-mcp` in a Box started with `--code-graph` (or `CLAUDE_BOX_CODE_GRAPH`); it is built from the Workspace and can lag its working tree.
_Avoid_: index, code index, memory, codebase memory
