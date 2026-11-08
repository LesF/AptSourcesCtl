## Filesystem locations used by APT, relative to a configurable root.
## A non-"/" root allows tests and a sandbox mode to work on a fake tree.

import std/[os, strutils]

type
  AptPaths* = object
    root*: string

proc initAptPaths*(root = ""): AptPaths =
  ## Uses `root` if given, else $APTSOURCESCTL_ROOT, else "/".
  var r = root
  if r.len == 0: r = getEnv("APTSOURCESCTL_ROOT")
  if r.len == 0: r = "/"
  AptPaths(root: r)

proc under*(p: AptPaths, path: string): string =
  ## Map an absolute system path into the root.
  if p.root == "/": path else: p.root / path.strip(leading = true, trailing = false, chars = {'/'})

proc etcApt*(p: AptPaths): string = p.under("/etc/apt")
proc sourcesList*(p: AptPaths): string = p.etcApt / "sources.list"
proc sourcesListD*(p: AptPaths): string = p.etcApt / "sources.list.d"
proc preferences*(p: AptPaths): string = p.etcApt / "preferences"
proc preferencesD*(p: AptPaths): string = p.etcApt / "preferences.d"
proc etcKeyrings*(p: AptPaths): string = p.etcApt / "keyrings"
proc trustedGpgD*(p: AptPaths): string = p.etcApt / "trusted.gpg.d"
proc trustedGpg*(p: AptPaths): string = p.etcApt / "trusted.gpg"
proc usrShareKeyrings*(p: AptPaths): string = p.under("/usr/share/keyrings")
proc osRelease*(p: AptPaths): string = p.under("/etc/os-release")

proc releaseCodename*(p: AptPaths): string =
  ## VERSION_CODENAME from os-release, or "" if unknown.
  let f = p.osRelease
  if not fileExists(f): return ""
  for line in lines(f):
    if line.startsWith("VERSION_CODENAME="):
      return line["VERSION_CODENAME=".len .. ^1].strip(chars = {'"', '\'', ' '})

proc isValidAptFileName*(name: string): bool =
  ## APT ignores files in *.d directories whose names contain other characters.
  if name.len == 0: return false
  for c in name:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}: return false
  true
