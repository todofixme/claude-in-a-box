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

## What persists between Boxes

A Box itself is thrown away when you leave it (`docker run --rm`). What
survives is the `claude-home` volume mounted at `/home/claude`, which holds
Claude's login, settings, memory and session transcripts.

To start over with a clean slate, including logging in again:

```sh
docker volume rm claude-home
```

## What the Image contains

- `node:24-trixie` as the base
- Claude Code, installed from npm at a version pinned in the `Dockerfile`
- A non-root user `claude` (UID 1000) with passwordless `sudo`, which Claude
  runs as

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
  settings.
- `tests/box.bats` — real Boxes: the Workspace mount, state surviving a
  restart, separate session histories per Workspace. Uses its own home volume,
  so your Claude login is left alone.

The last two skip themselves unless `claude-in-a-box:dev` is on the Host;
`CLAUDE_BOX_TEST_IMAGE` points them at another Image.
