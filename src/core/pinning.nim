## APT preferences (pinning): /etc/apt/preferences and preferences.d/*.
## The files are deb822-style, so the lossless deb822 model is reused.

import std/[os, strutils, algorithm]
import paths, model, deb822

type
  PrefFile* = object
    path*: string
    raw*: string
    error*: string
    doc*: Deb822Doc

proc listPreferenceFiles*(p: AptPaths): seq[string] =
  ## APT reads preferences.d files with no extension or a ".pref" extension.
  if fileExists(p.preferences): result.add p.preferences
  var dfiles: seq[string]
  if dirExists(p.preferencesD):
    for kind, f in walkDir(p.preferencesD):
      if kind notin {pcFile, pcLinkToFile}: continue
      let name = f.extractFilename
      if not isValidAptFileName(name): continue
      if name.endsWith(".pref") or not name.contains('.'): dfiles.add f
  dfiles.sort()
  result.add dfiles

proc parsePrefContent*(path, content: string): PrefFile =
  result = PrefFile(path: path, raw: content)
  try: result.doc = parseDeb822(content)
  except Deb822Error as e: result.error = e.msg

proc loadPrefFile*(path: string): PrefFile = parsePrefContent(path, readFile(path))

proc loadAllPrefs*(p: AptPaths): seq[PrefFile] =
  for f in listPreferenceFiles(p): result.add loadPrefFile(f)

proc render*(f: PrefFile): string =
  if f.error.len > 0: f.raw else: f.doc.render

proc ruleFromStanza*(s: Stanza, path: string, index: int): PinRule =
  result = PinRule(file: path, index: index,
                   package: s.getFieldOr("Package"), pin: s.getFieldOr("Pin"),
                   explanations: s.getAll("Explanation"))
  result.priority = try: parseInt(s.getFieldOr("Pin-Priority").strip) except ValueError: 0

proc rules*(f: PrefFile): seq[PinRule] =
  if f.error.len > 0: return
  var i = 0
  for s in f.doc.stanzas:
    result.add ruleFromStanza(s, f.path, i)
    inc i

proc applyRule*(f: var PrefFile, r: PinRule) =
  var s = addr f.doc.stanzaMut(r.index)
  s[].setField("Package", r.package)
  s[].setField("Pin", r.pin)
  s[].setField("Pin-Priority", $r.priority)

proc ruleToStanza*(r: PinRule): Stanza =
  var fields: seq[(string, string)]
  for e in r.explanations: fields.add ("Explanation", e)
  fields.add [("Package", r.package), ("Pin", r.pin), ("Pin-Priority", $r.priority)]
  newStanza(fields)

proc priorityMeaning*(prio: int): string =
  ## Summary of apt_preferences(5) priority ranges.
  if prio < 0: "never install"
  elif prio == 0: "undefined (avoid)"
  elif prio < 100: "only if no installed version"
  elif prio < 500: "lower than default"
  elif prio < 990: "default-like"
  elif prio < 1000: "preferred over target release"
  else: "force, even downgrade"
