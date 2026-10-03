# Claude in a Box

A sandbox in which Claude Code works in YOLO mode on your projects without
endangering the machine you develop on.

`claude-box` starts a container — a **Box** — from a prepared **Image**, mounts
the project directory you are in — the **Workspace** — into it, and hands it to
Claude Code with `--dangerously-skip-permissions`. Claude can do whatever it
likes to the Workspace and to the Box, and nothing else on the **Host**, the
machine the Box runs on.

Those four words — Box, Image, Workspace, Host — are used in this sense
throughout the documentation and the code.

### What a Box does not protect

A Box keeps Claude away from the Host. It does not keep the Workspace's
contents in: there is no network filter, so Claude can reach any host it can
route to, and anything in the Workspace can leave over the network. Don't make
a Workspace of something you would not let Claude read in the first place. See
[ADR 0002](docs/adr/0002-no-network-firewall.md).

The Box also runs `--privileged`, because it starts a Docker daemon of its own
for Test Containers. That is a weaker wall than an ordinary container's, but it
is the Host's Docker socket that would be the real hole, and that one is never
mounted: an escape from the Box ends in the Linux VM your Docker runs in, not
on the Host. See [ADR 0001](docs/adr/0001-docker-in-docker-over-host-socket.md).

## Prerequisites

- Docker (Docker Desktop or Rancher Desktop) running on an arm64 Host
- A Claude Pro, Max, Team, Enterprise or Console account

## Install

Put `bin/claude-box` on your `PATH`. Clone this repository and symlink the
script:

```sh
git clone https://github.com/todofixme/claude-in-a-box.git
ln -s "$PWD/claude-in-a-box/bin/claude-box" /usr/local/bin/claude-box
```

A symlink keeps `claude-box` current when you pull the repository. Any other
directory on your `PATH` works just as well — `~/.local/bin`, for example.

Check it:

```sh
claude-box --help
```

## Usage

Run it in the Workspace you want Claude to work on:

```sh
cd ~/projects/my-app
claude-box
```

The first Box asks you to log in. The login is kept in a Docker volume shared
by every Box, so later Boxes start straight into Claude.

Arguments `claude-box` does not recognise go to Claude, so the flags you
already know keep working:

```sh
claude-box --resume          # resume this Workspace's previous session
claude-box --model opus
```

If an argument collides with one of `claude-box`'s own flags, put it after
`--`:

```sh
claude-box -- --shell
```

### Flags

| Flag          | Effect                                                             |
| ------------- | ------------------------------------------------------------------ |
| `--shell`     | Open a bash login shell in the Box instead of Claude               |
| `--no-pull`   | Use the Image already on the Host instead of pulling a new one     |
| `--image REF` | Start the Box from another Image                                   |
| `--dry-run`   | Print the `docker run` command instead of running it               |
| `--help`      | Show usage                                                         |

| Variable                 | Effect                                                 |
| ------------------------ | ------------------------------------------------------ |
| `CLAUDE_BOX_IMAGE`       | Default Image reference                                |
| `CLAUDE_BOX_HOME_VOLUME` | Volume holding Claude's login and state                |

`--image` overrides `CLAUDE_BOX_IMAGE`. A second home volume gives you a
second, separate Claude login.

By default every start pulls the Image, so you get fixes and new Claude Code
versions without doing anything. `--no-pull` is the escape hatch for working
offline or testing an Image you built yourself. It refuses to pull rather than
pulling when the Image is absent, so a mistyped `--image` fails on the Host
instead of being fetched from somewhere.

## How the Workspace reaches the Box

The Workspace is mounted at **the same absolute path it has on the Host**,
and that is also the Box's working directory. So `~/projects/my-app` is
`/Users/you/projects/my-app` inside the Box too.

That matters because Claude Code files its session history and memory under the
working directory's path. Two Workspaces therefore keep two separate histories,
and `claude-box --resume` in a Workspace finds that Workspace's last session
rather than some other Workspace's.

As things stand the Workspace is the only thing mounted from the Host, so your
SSH keys, the rest of your home directory and your shell configuration are not
visible in the Box. Later versions add read-only mounts of the Host's Maven and
Gradle dependency caches
([ADR 0003](docs/adr/0003-host-caches-read-only.md)); treat the list of mounts
as something to check, not a guarantee.

## Backend tests with Test Containers

The Box has JDK 21 and a Docker daemon of its own, so Claude can run
Kotlin/Spring Boot tests that start Test Containers. Nothing needs setting up:

```sh
cd ~/projects/my-service
claude-box
> run the tests
```

The Box's `dockerd` starts before Claude does. Test Containers reach it through
`/var/run/docker.sock` **inside** the Box; the Host's socket of the same name
is not mounted, so nothing Claude starts can see the Host's containers or
mount Host directories into new ones.

That daemon keeps its images and containers in a Docker volume of its own per
Workspace, named after the Workspace (`claude-docker-my-service-<digest>`). The
Postgres image a test pulled is therefore still there in the next Box, and a
second run of the test starts it instead of downloading it again. The price is
that each Workspace pays for its images once, and that they do not come from
the Host's image cache.

Because two daemons on one data directory would corrupt it, **only one Box per
Workspace runs at a time**. A second one is refused:

```
claude-box: a Box is already running on /Users/you/projects/my-service; leave that one first
```

Boxes on different Workspaces are unaffected and run side by side.

The Image brings no Gradle and no Maven: projects bring their own wrapper, and
that is the version the build should use. The wrapper's downloads currently
land in the `claude-home` volume, so they are there for the next Box but shared
by all Workspaces; proper caches follow in a later version
([ADR 0003](docs/adr/0003-host-caches-read-only.md)).

## What persists between Boxes

A Box itself is thrown away when you leave it (`docker run --rm`). Two volumes
survive it:

- `claude-home`, mounted at `/home/claude` and shared by every Box, holds
  Claude's login, settings, memory and session transcripts.
- `claude-docker-<workspace>-<digest>`, mounted at `/var/lib/docker`, holds
  one Workspace's Docker images and containers.

To start over with a clean slate, including logging in again:

```sh
docker volume rm claude-home
```

To reclaim the disk a Workspace's Test Container images take:

```sh
docker volume ls | grep claude-docker
docker volume rm claude-docker-my-service-1a2b3c4d5e6f
```

## What the Image contains

- `node:24-trixie` as the base
- Claude Code, installed from npm at a version pinned in the `Dockerfile`
- A non-root user `claude` (UID 1000) with passwordless `sudo`, which Claude
  runs as
- JDK 21, for Kotlin/Spring Boot builds
- Docker Engine with the Compose plugin, for the daemon the Box runs itself

A Box starts as root, long enough for its entrypoint to bring up `dockerd`
(`/var/log/dockerd.log` inside the Box, if it ever does not), and drops to
`claude` before Claude or a shell gets to run.

Claude Code's auto-updater is switched off through managed settings at
`/etc/claude-code/managed-settings.json`, so the Box runs the version the Image
pins and not whatever shipped since. A new Claude Code version reaches you
through a new Image.

Passwordless `sudo` inside the Box is deliberate: Claude needs to install
packages while it works, and root in the Box is not root on the Host.

## Development

Build the Image locally and run a Box from it:

```sh
scripts/build-image.sh
claude-box --no-pull --image claude-in-a-box:dev
```

Run the checks:

```sh
scripts/check.sh
```

This needs [shellcheck](https://www.shellcheck.net) and
[bats](https://bats-core.readthedocs.io) (`brew install shellcheck bats-core`).

The suite is in three parts:

- `tests/cli.bats` — the `docker run` command `claude-box` assembles, via
  `--dry-run`. Needs neither Docker nor an Image.
- `tests/image.bats` — the built Image: user, sudo, pinned version, managed
  settings, JDK, Docker Engine.
- `tests/box.bats` — real Boxes: the Workspace mount, state surviving a
  restart, separate session histories per Workspace, the Box's own Docker and
  its per-Workspace image cache, one Box per Workspace. Uses its own home
  volume, so your Claude login is left alone, and throws away the Docker data
  its Boxes leave behind.

The last two skip themselves unless `claude-in-a-box:dev` is on the Host;
`CLAUDE_BOX_TEST_IMAGE` points them at another Image.

### Continuous integration

`.github/workflows/image.yml` builds the Image on every pull request against
`main`, without pushing it, so the build can be a required check before
Renovate automerges a dependency bump. On every push to `main` it also
publishes the Image to `ghcr.io/todofixme/claude-in-a-box`, tagged `latest`,
`sha-<short commit>` and `claude-<version>` — the Claude Code version pinned
in the `Dockerfile`, so you can pull the Image that has a specific Claude Code
version without reading a changelog.
