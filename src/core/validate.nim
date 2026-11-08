## Validation of source entries and pin rules.

import std/[os, strutils, tables, sets]
import paths, model

type
  Severity* = enum sevInfo = "info", sevWarning = "warning", sevError = "error"

  Issue* = object
    severity*: Severity
    message*: string
    file*: string
    index*: int

const
  knownSchemes = ["http", "https", "file", "cdrom", "copy", "ftp", "mirror",
                  "mirror+http", "mirror+https", "mirror+file", "tor+http",
                  "tor+https", "rsh", "ssh", "s3", "gs"]
  debianCodenames = ["buster", "bullseye", "bookworm", "trixie", "forky", "duke"]
  suiteSuffixes = ["-updates", "-security", "-backports-sloppy", "-backports",
                   "-proposed-updates"]

proc suiteBase*(suite: string): string =
  result = suite
  for s in suiteSuffixes:
    if result.endsWith(s): return result[0 ..< result.len - s.len]

proc validateEntry*(e: SourceEntry, p: AptPaths, codename = ""): seq[Issue] =
  template add(sev: Severity, msg: string) =
    result.add Issue(severity: sev, message: msg, file: e.file, index: e.index)

  if e.types.len == 0: add(sevError, "missing Types")
  for t in e.types:
    if t notin ["deb", "deb-src"]: add(sevError, "unknown type '" & t & "'")
  if e.uris.len == 0: add(sevError, "missing URIs")
  for u in e.uris:
    let c = u.find(':')
    if c <= 0: add(sevError, "URI without scheme: " & u)
    elif u[0 ..< c].toLowerAscii notin knownSchemes:
      add(sevWarning, "unusual URI scheme '" & u[0 ..< c] & "' (needs an apt transport)")
  if e.suites.len == 0: add(sevError, "missing Suites")
  for s in e.suites:
    if s.endsWith('/'):
      if e.components.len > 0: add(sevError, "exact path suite '" & s & "' must not have Components")
    elif e.components.len == 0:
      add(sevError, "suite '" & s & "' requires Components")
  # signing
  if e.signedBy.len == 0:
    var isCdrom = false
    for u in e.uris:
      if u.toLowerAscii.startsWith("cdrom:"): isCdrom = true
    if e.enabled and not isCdrom:
      add(sevWarning, "no Signed-By: trusted by every global key (trusted.gpg.d)")
  else:
    for sp in e.signedByPaths:
      if not fileExists(p.under(sp)): add(sevError, "Signed-By keyring not found: " & sp)
  # release sanity
  if codename.len > 0 and e.enabled:
    for s in e.suites:
      let b = suiteBase(s)
      if b in debianCodenames and b != codename:
        let ci = debianCodenames.find(codename)
        let bi = debianCodenames.find(b)
        if ci >= 0 and bi >= 0 and bi < ci:
          add(sevWarning, "suite '" & s & "' is older than this system (" & codename & ")")
        elif ci >= 0 and bi > ci:
          add(sevWarning, "suite '" & s & "' is newer than this system (" & codename & "); consider pinning")

proc normUri(u: string): string = u.strip(leading = false, chars = {'/'}).toLowerAscii

proc validateAll*(entries: openArray[SourceEntry], p: AptPaths, codename = ""): seq[Issue] =
  var seen = initTable[string, string]()
  for e in entries:
    result.add validateEntry(e, p, codename)
    if not e.enabled: continue
    var dupReported = initHashSet[string]()
    for t in e.types:
      for u in e.uris:
        for s in e.suites:
          let comps = if e.components.len == 0: @[""] else: e.components
          for c in comps:
            let key = t & " " & normUri(u) & " " & s & " " & c
            let here = e.file.extractFilename & ":" & $(e.index + 1)
            if key in seen and seen[key] != here and seen[key] notin dupReported:
              dupReported.incl seen[key]
              result.add Issue(severity: sevWarning, file: e.file, index: e.index,
                message: "duplicates entry in " & seen[key] & " (" & key & ")")
            elif key notin seen:
              seen[key] = here

proc validateRule*(r: PinRule): seq[Issue] =
  template add(sev: Severity, msg: string) =
    result.add Issue(severity: sev, message: msg, file: r.file, index: r.index)
  if r.package.strip.len == 0: add(sevError, "missing Package")
  if r.pin.strip.len == 0: add(sevError, "missing Pin")
  else:
    let kind = r.pin.splitWhitespace[0]
    if kind notin ["release", "origin", "version"]:
      add(sevError, "Pin must start with release, origin or version")
  if r.priority == 0: add(sevWarning, "Pin-Priority missing or 0")
