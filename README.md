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

| Flag            | Effect                                                             |
| --------------- | ------------------------------------------------------------------ |
| `--shell`       | Open a bash login shell in the Box instead of Claude               |
| `--code-graph`  | Give Claude a Code Graph of the Workspace (see below)              |
| `--no-pull`     | Use the Image already on the Host instead of pulling a new one     |
| `--image REF`   | Start the Box from another Image                                   |
| `--dry-run`     | Print the `docker run` command instead of running it               |
| `--help`        | Show usage                                                         |

| Variable                  | Effect                                                 |
| ------------------------- | ------------------------------------------------------ |
| `CLAUDE_BOX_IMAGE`        | Default Image reference                                |
| `CLAUDE_BOX_HOME_VOLUME`  | Volume holding Claude's login and state                |
| `CLAUDE_BOX_GH_TOKEN`     | Token `gh` uses in the Box                              |
| `CLAUDE_BOX_GITLAB_TOKEN` | Token `glab` uses in the Box                            |
| `CLAUDE_BOX_CODE_GRAPH`   | Turn `--code-graph` on for every Box                   |

`--image` overrides `CLAUDE_BOX_IMAGE`. A second home volume gives you a
second, separate Claude login. The two tokens are covered in
[Git identity and tokens](#git-identity-and-tokens) below.

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

The Workspace is the only thing mounted from the Host. Your SSH keys, your
shell configuration, the rest of your home directory and your Maven and Gradle
caches are not visible in the Box — a build in a Box downloads into caches of
its own (see below).

## Git identity and tokens

Claude commits locally under your name: `claude-box` reads `user.name` and
`user.email` from the Host's own `git config` — the Workspace's local config
if it has one, your global config otherwise — and passes them into the Box as
`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and
`GIT_COMMITTER_EMAIL`. Your SSH keys and any stored HTTPS credentials are not
mounted, so `git push` from the Box always fails for lack of them — pushing
stays something you do on the Host, after reviewing what Claude committed.

`gh` and `glab` work read-only if you want them to. Set `CLAUDE_BOX_GH_TOKEN`
or `CLAUDE_BOX_GITLAB_TOKEN` on the Host and `claude-box` passes it into the
Box as `GH_TOKEN` or `GITLAB_TOKEN`, which each tool reads directly — so
`gh issue list`, for instance, works without any further setup. Leave one
unset and its variable does not exist in the Box at all, not even empty. A
**read-only, fine-grained token** is recommended for each: the Box never needs
to write to GitHub or GitLab, and a broader token would hand Claude more than
it has a use for.

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

## Maven and Gradle caches

A build in a Box downloads its dependencies itself, into `~/.m2` and
`~/.gradle` **inside** the Box. Each of those is a Docker volume of the
Workspace, named after it the way the Docker data volume is:

| In the Box        | Volume                                |
| ----------------- | ------------------------------------- |
| `~/.m2`           | `claude-maven-my-service-<digest>`    |
| `~/.gradle`       | `claude-gradle-my-service-<digest>`   |

So the second Box on a Workspace finds the dependencies, the Gradle
distribution and the Maven distribution the first one downloaded, and no
Workspace can put anything into another Workspace's cache. Nothing of your own
`~/.m2` or `~/.gradle` is mounted: not the repository, and not `settings.xml`,
`gradle.properties` or `init.d`, which hold credentials and run code. The Image
sets no Maven or Gradle variables either — the two volumes sit exactly where
both tools look by default, so there is nothing to configure and nothing to
keep in step with a tool version.

What that costs, deliberately
([ADR 0004](docs/adr/0004-box-caches-only-per-workspace.md)): the first build
in a Workspace downloads everything, including the ~130 MB Gradle
distribution, and every Workspace keeps its own copy on disk. An earlier
version mounted the Host's caches read-only to avoid that; it depended on an
incubating Gradle feature, reused only part of what the Host had, needed Maven
3.9, and a privileged Box could remount its way into the Host's cache
regardless. Two volumes are the simpler and stricter trade.

A Workspace whose dependencies come from a private repository will not build in
a Box: the credentials for it live in the `settings.xml` and
`gradle.properties` that stay on the Host.

## Frontend tooling

Corepack ships with Node and is enabled in the Image, so `pnpm` and `yarn`
resolve to whatever version a Workspace declares in its `package.json`
`"packageManager"` field, downloading that version the first time it is used.

The Image also carries [Playwright CLI](https://playwright.dev) (`playwright-cli`),
installed globally at a version pinned in the `Dockerfile`, so Claude can drive
a browser directly:

```sh
playwright-cli --browser chromium open https://example.com
playwright-cli screenshot --filename=shot.png
```

`--browser chromium` is needed on every call: Playwright CLI defaults to a real
Google Chrome, which the Image does not install, only the headless Chromium
build Playwright downloads itself and the system libraries it needs to run
(both installed the same way for the Workspace's own `@playwright/test`).

Like Maven and Gradle, npm's cache, pnpm's store and the Playwright browser
cache are Box Caches of the Workspace:

| In the Box                 | Volume                                     |
| --------------------------- | ------------------------------------------- |
| `~/.npm`                    | `claude-npm-my-service-<digest>`           |
| `~/.local/share/pnpm`       | `claude-pnpm-my-service-<digest>`          |
| `~/.cache/ms-playwright`     | `claude-playwright-my-service-<digest>`    |

npm and Playwright already look in those two places by default, so neither is
configured. pnpm is the exception: left to itself it ignores `$HOME` and puts
its store at the root of whatever filesystem the current Workspace happens to
sit on, which would make the volume above pointless, so the Image points it at
`~/.local/share/pnpm` through pnpm's own config file (not `~/.npmrc`, which npm
reads too and would warn about the setting on every command).

The Workspace's own `@playwright/test` downloads its matching browser the same way
Playwright CLI's did, into the same Box Cache, so the second Box on a Workspace
runs its E2E suite without downloading anything.

## Code Graph

On a large Workspace, answering "where is this used" by searching hundreds of
files with `rg` is slow and incomplete. `--code-graph` gives Claude a **Code
Graph** instead: a searchable graph of the Workspace's symbols and how they
relate, served inside the Box by
[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) at a
version pinned in the `Dockerfile`.

```sh
cd ~/projects/my-app
claude-box --code-graph
> which callers would break if I change the signature of OrderService.place?
```

There is no indexing step. The first time Claude connects to the server it
indexes the Workspace itself; on a big Workspace the first question therefore
takes a while to come back, and the ones after it are fast. The graph goes
into a Box Cache of the Workspace:

| In the Box                     | Volume                                   |
| ------------------------------ | ---------------------------------------- |
| `~/.cache/codebase-memory-mcp` | `claude-codegraph-my-service-<digest>`   |

So the next Box on that Workspace finds the graph the last one built, and
another Workspace gets a graph of its own. Set `CLAUDE_BOX_CODE_GRAPH` to any
value on the Host if you want every Box to have one without passing the flag.

**The graph can lag the working tree.** It is a snapshot, refreshed as the
server notices changes, so `git diff` and reading the files stay the answer to
"what did I just change" — the graph is for finding your way around code you
have not just written.

Two things are deliberately true of it:

- **Indexing stays inside the Workspace.** `claude-box` points the server at
  the Workspace and it refuses any other path, so the graph never covers
  `$HOME` in the Box, Claude's login or the Box Caches.
- **The graph UI never starts and no port is published.** The server can serve
  an HTTP visualisation of the graph; a Box turns it off, because nothing in a
  Box would open it.

A Box started **without** the flag is exactly what it was before: the server is
in the Image but nothing registers it, no graph volume is created on the Host,
and none of its 17 tool descriptions reach Claude's context. That is why this
is a flag rather than something every Box has
([ADR 0005](docs/adr/0005-code-graph-registered-per-box-via-mcp-config.md),
which also records why registration goes through Claude's `--mcp-config`
instead of the Image's managed settings).

## What persists between Boxes

A Box itself is thrown away when you leave it (`docker run --rm`). The volumes
survive it:

- `claude-home`, mounted at `/home/claude` and shared by every Box, holds
  Claude's login, settings, memory and session transcripts.
- `claude-docker-<workspace>-<digest>`, mounted at `/var/lib/docker`, holds
  one Workspace's Test Container images.
- `claude-maven-<workspace>-<digest>` and
  `claude-gradle-<workspace>-<digest>`, the Box Caches of the Maven and Gradle
  section, hold one Workspace's backend dependencies.
- `claude-npm-<workspace>-<digest>`, `claude-pnpm-<workspace>-<digest>` and
  `claude-playwright-<workspace>-<digest>`, the Box Caches of the Frontend
  tooling section, hold one Workspace's frontend dependencies and downloaded
  browsers.
- `claude-codegraph-<workspace>-<digest>`, holding one Workspace's Code Graph.
  Only a `--code-graph` Box creates it.

To start over with a clean slate, including logging in again:

```sh
docker volume rm claude-home
```

To reclaim the disk a Workspace's Test Container images take:

```sh
docker volume ls | grep claude-docker
docker volume rm claude-docker-my-service-1a2b3c4d5e6f
```

To reclaim the disk a Workspace's dependencies take, or to make its next build
download them again:

```sh
docker volume ls | grep -E 'claude-(maven|gradle|npm|pnpm|playwright)'
docker volume rm claude-maven-my-service-1a2b3c4d5e6f claude-gradle-my-service-1a2b3c4d5e6f \
  claude-npm-my-service-1a2b3c4d5e6f claude-pnpm-my-service-1a2b3c4d5e6f \
  claude-playwright-my-service-1a2b3c4d5e6f
```

To make a Workspace's Code Graph be built again from scratch:

```sh
docker volume rm claude-codegraph-my-service-1a2b3c4d5e6f
```

## What the Image contains

- `node:24-trixie` as the base
- Claude Code, installed from npm at a version pinned in the `Dockerfile`
- A non-root user `claude` (UID 1000) with passwordless `sudo`, which Claude
  runs as
- JDK 21, for Kotlin/Spring Boot builds
- Docker Engine with the Compose plugin, for the daemon the Box runs itself
- Corepack, enabled, for `pnpm` and `yarn`
- Playwright CLI, installed from npm at a version pinned in the `Dockerfile`,
  with the system libraries headless Chromium needs
- `codebase-memory-mcp`, the Code Graph server, downloaded from its GitHub
  release at a version pinned in the `Dockerfile` and verified against that
  release's `checksums.txt` at build time. Registered for a Box only by
  `--code-graph`
- `git`, `gh` (from GitHub's own apt repository), `glab`, `jq`, `yq`,
  `ripgrep`, `httpie` and `curl`, all otherwise from Debian's own apt
  repository

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
- `tests/image.bats` — the built Image: user, sudo, pinned versions, managed
  settings, JDK, Docker Engine, corepack, Playwright CLI and the Chromium
  libraries it needs, the Code Graph server, and that it configures Maven,
  Gradle and npm not at all.
- `tests/box.bats` — real Boxes: the Workspace mount, state surviving a
  restart, separate session histories per Workspace, the Box's own Docker and
  its per-Workspace Docker data, one Box per Workspace, the Box Caches a
  Workspace downloads into, and the Code Graph — a `--code-graph` Box answers
  a query from a graph nothing indexed by hand, via
  `tests/code-graph-probe.sh`, which drives the server over stdio the way
  Claude's MCP client does. Uses its own home volume, so your Claude login is
  left alone, and throws away the Docker data and Box Caches its Boxes leave
  behind.

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

### Dependency updates

`renovate.json` picks up four versions pinned by an `ARG ..._VERSION=` line in
the `Dockerfile` — Claude Code, ccstatusline, `@playwright/cli` and
`codebase-memory-mcp` — via a custom regex manager keyed off the
`# renovate: datasource=... depName=...` comment directly above each `ARG`.
Claude Code and ccstatusline PRs automerge once the PR build is green, so the
merge to `main` publishes a new `claude-<version>` Image. The base image
digest, GitHub Actions, `@playwright/cli` and `codebase-memory-mcp` are
grouped into a single weekly PR that is never automerged, since none of the
four gate on the build the way Claude Code and ccstatusline do.
