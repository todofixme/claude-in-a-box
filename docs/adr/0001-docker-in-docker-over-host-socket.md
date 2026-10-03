# Docker-in-Docker instead of the Host's Docker socket

Backend tests in the Box need Docker for Test Containers. Each Box therefore runs its own `dockerd` (the Box runs with `--privileged`) instead of mounting the Host's Docker socket. Through the Host socket, Claude in YOLO mode could mount arbitrary Host directories into new containers, and the Box would no longer be a sandbox. An escape from a privileged Box ends in Docker Desktop's Linux VM, not on the Host.

## Considered Options

- **Host socket** (`/var/run/docker.sock`): faster and shares the Host's image cache, but removes the isolation.
- **Sysbox**: DinD without `--privileged`, but it does not run under Docker Desktop for macOS.

## Consequences

Test Container images are pulled per Workspace and do not live in the Host's image cache.
