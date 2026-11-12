# AptSourcesCtl

A KDE/Qt 6 control panel for viewing and editing APT configuration on Debian
(Trixie and later): **sources** (both one-line `.list` and deb822 `.sources`),
**keyrings** and **pinning** (`preferences.d`).

Written in [Nim](https://nim-lang.org) with [seaqt](https://github.com/seaqt/nim-seaqt) Qt Widgets bindings.

## Motivation

I have used apt/sources as a data source while tinkering with other languages, mostly as a view-only resource, while learning UI tools or just passing time.
This is an exercise in learning Nim and Qt, where I will go further and include updates to sources and managing keyrings.  I will update this comment if/when I believe it is safe to use on live sources, until then see APTSOURCESCTL_ROOT below.

## Design

- `src/core/` — UI-free library. Parsers keep files **byte-for-byte** intact
  (comments, spacing, field order); edits rewrite only the touched lines.
- `src/gui/` — seaqt Qt 6 Widgets front end (runs as the user).
- `src/helper/` — small privileged helper run via `pkexec`; re-validates
  and atomically writes files under `/etc/apt` only.

## Requirements

```sh
sudo apt install qt6-base-dev qt6-base-private-dev gpg pkexec   # Qt headers, key inspection, elevation
choosenim stable                                                # Nim >= 2.2
```

## Development & Usage

```sh
nimble build         # build aptsourcesctl and aptsourcesctl_helper
nimble test          # run all test suites (core + gui state + headless launch)
nimble dump          # print what the core sees on this system
./aptsourcesctl      # launch the Qt 6 system settings control panel
```

Set `APTSOURCESCTL_ROOT=/some/dir` (or pass `--root=<dir>`) to operate on a sandbox copy of `/etc/apt` (e.g. `tests/fixtures/root`).

## Licence

GPL-3.0-or-later — see [LICENSE](LICENSE).

## Install from .deb

Download `aptsourcesctl_<version>_<arch>.deb` from the
[Releases](https://github.com/LesF/AptSourcesCtl/releases) page, then:

```sh
sudo apt install ./aptsourcesctl_*.deb
```

To build it yourself (needs Nim >= 2.2 on `PATH`):

```sh
sudo apt install build-essential debhelper devscripts lintian qt6-base-dev qt6-base-private-dev
tools/build-deb.sh            # result lands in ../
```
