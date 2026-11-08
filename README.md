# AptSourcesCtl

A KDE/Qt 6 control panel for viewing and editing APT configuration on Debian
(Trixie and later): **sources** (both one-line `.list` and deb822 `.sources`),
**keyrings** and **pinning** (`preferences.d`).

Written in [Nim](https://nim-lang.org) with [seaqt](https://github.com/seaqt/nim-seaqt) Qt Widgets bindings.

## Design

- `src/core/` — UI-free library. Parsers keep files **byte-for-byte** intact
  (comments, spacing, field order); edits rewrite only the touched lines.
- `src/gui/` — seaqt Qt 6 Widgets front end (runs as the user).
- `src/helper/` — small privileged helper run via `pkexec`; re-validates
  and atomically writes files under `/etc/apt` only.

## Requirements

```sh
sudo apt install qt6-base-dev gpg pkexec   # Qt headers, key inspection, elevation
choosenim stable                           # Nim >= 2.2
```

## Development

```sh
nimble test          # core tests (fixtures in tests/fixtures/root)
nimble dump          # print what the core sees on this system
nim r tools/dump.nim tests/fixtures/root   # ...or on the fixture tree
```

Set `APTSOURCESCTL_ROOT=/some/dir` to operate on a sandbox copy of `/etc/apt`.

## Licence

GPL-3.0-or-later — see [LICENSE](LICENSE).
