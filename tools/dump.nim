## Dev tool: print what the core library sees (no Qt needed).
## Usage: nim r tools/dump.nim [root]     (or APTSOURCESCTL_ROOT=...)

import std/[os, strutils, times]
import ../src/core

let p = initAptPaths(if paramCount() > 0: paramStr(1) else: "")
let codename = p.releaseCodename
echo "Root: ", p.root, "   Release: ", codename

var all: seq[SourceEntry]
echo "\n== Sources"
for f in loadAllSources(p):
  echo f.path, "  [", f.format, "]", (if f.error.len > 0: "  PARSE ERROR: " & f.error else: ""),
    (if f.render != f.raw: "  !! ROUND-TRIP MISMATCH" else: "")
  for e in f.entries:
    all.add e
    echo "  ", (if e.enabled: "[x] " else: "[ ] "), e.label, " ", e.components.join(" "),
      (if e.signedBy.len > 0: "  key=" & (if e.hasInlineKey: "<inline>" else: e.signedBy) else: "")

echo "\n== Keyrings"
var ks = scanKeyrings(p)
ks.crossReference(all, p)
for k in ks:
  echo k.path, (if k.armored: " (armored)" else: ""), (if k.isOrphan: "  ORPHAN" else: ""),
    (if k.error.len > 0: "  error: " & k.error else: "")
  for key in k.keys:
    let exp = if key.expires == 0: "never" else: fromUnix(key.expires).format("yyyy-MM-dd")
    echo "    ", key.fingerprint, "  ", key.uid, "  expires ", exp
  for u in k.usedBy: echo "    used by: ", u

echo "\n== Pinning"
for f in loadAllPrefs(p):
  echo f.path, (if f.error.len > 0: "  PARSE ERROR: " & f.error else: "")
  for r in f.rules:
    echo "  ", r.package, " | ", r.pin, " | ", r.priority, " (", priorityMeaning(r.priority), ")"

echo "\n== Issues"
for i in validateAll(all, p, codename):
  echo "  ", i.severity, ": ", i.file.extractFilename, "#", i.index + 1, ": ", i.message
