# Package

version       = "0.1.0"
author        = "Egbert"
description   = "View and edit APT sources, keyrings and pinning (Qt 6 / KDE)"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["aptsourcesctl", "aptsourcesctl_helper"]

# Dependencies

requires "nim >= 2.2.0"
# seaqt is a preview; pinned to a known commit on the Qt 6.8 branch (Trixie ships Qt 6.8).
requires "https://github.com/seaqt/nim-seaqt.git#7d40abd7b493036b4ede5b111fc4260237504796"

# Tasks

task dump, "Print parsed APT configuration (core library smoke test, no Qt)":
  exec "nim r --hints:off tools/dump.nim"
