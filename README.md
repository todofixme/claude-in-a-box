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

| Variable                   | Effect                                                   |
| -------------------------- | -------------------------------------------------------- |
| `CLAUDE_BOX_IMAGE`         | Default Image reference                                  |
| `CLAUDE_BOX_HOME_VOLUME`   | Volume holding Claude's login and state                  |
| `CLAUDE_BOX_HOST_HOME`     | Home directory the Host Caches are read from (see below) |
| `CLAUDE_BOX_MAVEN_VOLUME`  | Box Cache volume for Maven's local repository            |
| `CLAUDE_BOX_GRADLE_VOLUME` | Box Cache volume for Gradle's user home                  |

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

Besides the Workspace, two directories of your home come along, both read-only
and both build caches: the Maven repository and the Gradle dependency cache
(see below). Your SSH keys, the rest of your home directory and your shell
configuration are not visible in the Box.

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

That daemon keeps the Test Container images it pulls in a Docker volume of its
own per Workspace, named after the Workspace
(`claude-docker-my-service-<digest>`). The Postgres image a test pulled is
therefore still there in the next Box, and a second run of the test starts it
instead of downloading it again. The price is that each Workspace pays for its
images once, and that they do not come from the Host's image cache.

Because two daemons on one data directory would corrupt it, **only one Box per
Workspace runs at a time**. A second one is refused:

```
claude-box: a Box is already running on /Users/you/projects/my-service; leave that one first
```

Boxes on different Workspaces are unaffected and run side by side.

The Image brings no Gradle and no Maven: a Workspace brings its own wrapper,
and that is the version the build should use. Where the wrapper and the build
get their dependencies is the next section.

## The Host's Maven and Gradle caches

A build in a Box reuses the dependencies your Host has already downloaded
rather than fetching them again, and cannot change them. Two directories are
bind-mounted **read-only**:

| On the Host                  | In the Box                        |
| ---------------------------- | --------------------------------- |
| `~/.m2/repository`           | `/host-caches/maven/repository`   |
| `~/.gradle/caches/modules-2` | `/host-caches/gradle/modules-2`   |

Their parents stay outside: `~/.m2/settings.xml` and `~/.gradle/gradle.properties`
hold credentials, and `~/.gradle/init.d` holds scripts Gradle runs. Read-only is
what [ADR 0003](docs/adr/0003-host-caches-read-only.md) is about — neither Maven
nor Gradle re-verifies a cache entry it already has, so a jar swapped in the Box
would run in your next build on the Host.

Read-only here means what a build can do, not what the Box can do: it is
privileged and Claude has `sudo`, so `mount -o remount,rw` inside the Box makes
those two directories writable again. The capability dockerd needs is the
capability remounting needs, so this is the price of Test Containers in a Box
(ADR 0001); if you would rather not pay it, point `CLAUDE_BOX_HOST_HOME` at an
empty directory and let Boxes download their own dependencies.

What a build downloads for itself goes into two **Box Caches**, volumes shared
by every Box:

- `claude-gradle` at `/box-caches/gradle` is Gradle's user home: its own
  dependency cache and the wrapper's Gradle distributions.
- `claude-maven` at `/box-caches/maven` holds Maven's local repository and the
  wrapper's Maven distributions.

So a dependency your Host has is read straight out of the Host Cache and never
copied, and one it does not have is downloaded once and then found by the next
Box.

Two things to expect:

- Gradle only reuses Host entries whose metadata the same Gradle generation
  wrote (`caches/modules-2/metadata-2.107` and its siblings). A Box running
  Gradle 8 does not see what Gradle 9 resolved on the Host; it downloads those
  into the Box Cache instead.
- Maven reuses the Host's repository through `maven.repo.local.tail`, which
  Maven 3.9 introduced. A Workspace whose wrapper pins something older still
  writes into the Box Cache, but downloads everything itself.
- A Host that has never run Maven or Gradle gets the two directories created,
  empty, on the first `claude-box`. Nothing else in `~/.m2` or `~/.gradle` is
  touched.

`CLAUDE_BOX_HOST_HOME` points the two mounts at a home directory other than
yours. Pointing it at an empty directory is how you share neither cache: the
two mounts are then empty directories created inside it, and a build in the
Box downloads everything into the Box Caches.

## What persists between Boxes

A Box itself is thrown away when you leave it (`docker run --rm`). Four volumes
survive it:

- `claude-home`, mounted at `/home/claude` and shared by every Box, holds
  Claude's login, settings, memory and session transcripts.
- `claude-docker-<workspace>-<digest>`, mounted at `/var/lib/docker`, holds
  one Workspace's Test Container images.
- `claude-gradle` and `claude-maven`, the Box Caches of the section above,
  shared by every Box.

To start over with a clean slate, including logging in again:

```sh
docker volume rm claude-home
```

To reclaim the disk a Workspace's Test Container images take:

```sh
docker volume ls | grep claude-docker
docker volume rm claude-docker-my-service-1a2b3c4d5e6f
```

To make the next build download its dependencies again:

```sh
docker volume rm claude-gradle claude-maven
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
`claude` before Claude or a shell gets to run. `docker exec` into a running Box
bypasses that entrypoint and lands as root, so pass `-u claude` when you want
to see what Claude sees.

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
  settings, JDK, Docker Engine, where it points Maven and Gradle.
- `tests/box.bats` — real Boxes: the Workspace mount, state surviving a
  restart, separate session histories per Workspace, the Box's own Docker and
  its per-Workspace Docker data, one Box per Workspace, and the Host Caches
  being readable but not writable. Uses its own home volume, Box Caches and a
  throwaway Host home, so your Claude login and your real caches are left
  alone, and throws away the Docker data its Boxes leave behind.

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
