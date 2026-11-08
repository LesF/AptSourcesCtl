## Format-independent data model shared by the GUI and helper.

import std/strutils

type
  SourceFormat* = enum
    sfDeb822 = "deb822"     ## *.sources
    sfOneLine = "one-line"  ## sources.list, *.list

  SourceEntry* = object
    file*: string           ## absolute path of origin file
    format*: SourceFormat
    index*: int             ## stanza index (deb822) or line index (one-line)
    enabled*: bool
    types*: seq[string]     ## deb, deb-src
    uris*: seq[string]
    suites*: seq[string]
    components*: seq[string]
    architectures*: seq[string]
    signedBy*: string       ## path(s), fingerprint(s), or inline armored key
    options*: seq[(string, string)] ## other options, using deb822 field names

  KeyringLocation* = enum
    klEtcKeyrings = "/etc/apt/keyrings"
    klUsrShare = "/usr/share/keyrings"
    klTrustedD = "/etc/apt/trusted.gpg.d"
    klLegacy = "/etc/apt/trusted.gpg"

  KeyInfo* = object
    fingerprint*: string
    uid*: string
    algo*: string
    bits*: int
    created*: int64         ## unix time
    expires*: int64         ## unix time, 0 = never
    expired*: bool
    revoked*: bool

  KeyringFile* = object
    path*: string
    location*: KeyringLocation
    armored*: bool
    keys*: seq[KeyInfo]
    error*: string
    usedBy*: seq[string]    ## labels of sources referencing this file

  PinRule* = object
    file*: string
    index*: int             ## stanza index
    package*: string
    pin*: string
    priority*: int
    explanations*: seq[string]

const
  ## one-line option name -> deb822 field name
  optionMap* = [
    ("arch", "Architectures"), ("lang", "Languages"), ("target", "Targets"),
    ("pdiffs", "PDiffs"), ("by-hash", "By-Hash"), ("allow-insecure", "Allow-Insecure"),
    ("allow-weak", "Allow-Weak"), ("allow-downgrade-to-insecure", "Allow-Downgrade-To-Insecure"),
    ("trusted", "Trusted"), ("signed-by", "Signed-By"), ("check-valid-until", "Check-Valid-Until"),
    ("valid-until-min", "Valid-Until-Min"), ("valid-until-max", "Valid-Until-Max"),
    ("check-date", "Check-Date"), ("date-max-future", "Date-Max-Future"),
    ("inrelease-path", "InRelease-Path"), ("snapshot", "Snapshot"),
  ]

proc toDeb822Name*(opt: string): string =
  ## Handles "arch", "arch+" and "arch-" (the suffix is kept: "Architectures-Add"
  ## is APT's deb822 spelling of "arch+").
  var base = opt
  var suffix = ""
  if base.endsWith('+'): base.setLen(base.len - 1); suffix = "-Add"
  elif base.endsWith('-'): base.setLen(base.len - 1); suffix = "-Remove"
  for (o, d) in optionMap:
    if cmpIgnoreCase(o, base) == 0: return d & suffix
  opt

proc toOneLineName*(field: string): string =
  var base = field
  var suffix = ""
  if base.toLowerAscii.endsWith("-add"): base.setLen(base.len - 4); suffix = "+"
  elif base.toLowerAscii.endsWith("-remove"): base.setLen(base.len - 7); suffix = "-"
  for (o, d) in optionMap:
    if cmpIgnoreCase(d, base) == 0: return o & suffix
  field.toLowerAscii

proc label*(e: SourceEntry): string =
  ## Short human label, e.g. "deb http://deb.debian.org/debian trixie".
  e.types.join(",") & " " & e.uris.join(" ") & " " & e.suites.join(" ")

proc hasInlineKey*(e: SourceEntry): bool = "BEGIN PGP" in e.signedBy

proc signedByPaths*(e: SourceEntry): seq[string] =
  ## Keyring file paths referenced in Signed-By (ignores fingerprints/inline keys).
  if e.hasInlineKey: return
  for tok in e.signedBy.split({',', ' ', '\t', '\n'}):
    if tok.startsWith('/'): result.add tok
