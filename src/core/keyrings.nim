## Keyring discovery and inspection. Key metadata comes from
## `gpg --show-keys --with-colons` run in a throwaway GNUPGHOME, so the
## user's (or root's) keyring is never touched.

import std/[os, osproc, strutils, tempfiles, algorithm]
import paths, model

proc parseGpgColons*(output: string): seq[KeyInfo] =
  var cur: KeyInfo
  var inPrimary = false
  var have = false
  for line in output.splitLines:
    let f = line.split(':')
    if f.len < 2: continue
    case f[0]
    of "pub":
      if have: result.add cur
      cur = KeyInfo()
      have = true
      inPrimary = true
      cur.expired = f[1] == "e"
      cur.revoked = f[1] == "r"
      if f.len > 2: cur.bits = try: parseInt(f[2]) except ValueError: 0
      if f.len > 3: cur.algo = f[3]
      if f.len > 5: cur.created = try: parseBiggestInt(f[5]) except ValueError: 0
      if f.len > 6 and f[6].len > 0: cur.expires = try: parseBiggestInt(f[6]) except ValueError: 0
    of "sub":
      inPrimary = false
    of "fpr":
      if inPrimary and cur.fingerprint.len == 0 and f.len > 9: cur.fingerprint = f[9]
    of "uid":
      if cur.uid.len == 0 and f.len > 9: cur.uid = f[9]
    else: discard
  if have: result.add cur

proc isArmored*(path: string): bool =
  try:
    let f = open(path)
    defer: f.close()
    var buf = newString(64)
    let n = f.readChars(toOpenArray(buf, 0, buf.high))
    buf.setLen(n)
    "-----BEGIN PGP" in buf
  except IOError: false

proc inspectKeyring*(path: string, location: KeyringLocation): KeyringFile =
  result = KeyringFile(path: path, location: location, armored: isArmored(path))
  let home = createTempDir("aptsourcesctl-gpg", "")
  defer: removeDir(home)
  let cmd = "gpg --homedir " & quoteShell(home) &
    " --batch --no-tty --quiet --show-keys --with-colons --with-fingerprint " & quoteShell(path)
  let (outp, code) = execCmdEx(cmd, options = {poUsePath, poEvalCommand})
  if code != 0:
    result.error = "gpg exit " & $code
  result.keys = parseGpgColons(outp)
  if result.keys.len == 0 and result.error.len == 0:
    result.error = "no keys found"

proc isKeyringName(name: string): bool =
  name.endsWith(".gpg") or name.endsWith(".asc") or name.endsWith(".pgp")

proc scanDir(dir: string, loc: KeyringLocation, into: var seq[KeyringFile]) =
  if not dirExists(dir): return
  var files: seq[string]
  for kind, f in walkDir(dir):
    if kind in {pcFile, pcLinkToFile} and isKeyringName(f.extractFilename): files.add f
  files.sort()
  for f in files: into.add inspectKeyring(f, loc)

proc scanKeyrings*(p: AptPaths): seq[KeyringFile] =
  scanDir(p.etcKeyrings, klEtcKeyrings, result)
  scanDir(p.usrShareKeyrings, klUsrShare, result)
  scanDir(p.trustedGpgD, klTrustedD, result)
  if fileExists(p.trustedGpg): result.add inspectKeyring(p.trustedGpg, klLegacy)

proc crossReference*(keyrings: var seq[KeyringFile], entries: openArray[SourceEntry], p: AptPaths) =
  ## Fill `usedBy` (paths in Signed-By are system paths; map them via root).
  for k in keyrings.mitems: k.usedBy = @[]
  for e in entries:
    for sp in e.signedByPaths:
      let mapped = p.under(sp)
      for k in keyrings.mitems:
        if k.path == mapped: k.usedBy.add e.label

proc isOrphan*(k: KeyringFile): bool =
  ## Unreferenced keyrings in /etc/apt/keyrings are likely leftovers.
  ## (/usr/share/keyrings is package-owned; trusted.gpg.d is global trust.)
  k.location == klEtcKeyrings and k.usedBy.len == 0
