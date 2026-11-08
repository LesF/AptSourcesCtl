## Discovery, loading and entry extraction for APT source files, plus
## one-line -> deb822 conversion.

import std/[os, strutils, algorithm, options]
import paths, model, deb822, onelinesources

type
  SourceFile* = object
    path*: string
    raw*: string            ## original content as read
    error*: string          ## parse error, if any (doc then unusable)
    case format*: SourceFormat
    of sfDeb822: d822*: Deb822Doc
    of sfOneLine: ol*: OneLineDoc

proc formatFor*(path: string): SourceFormat =
  if path.endsWith(".sources"): sfDeb822 else: sfOneLine

proc listSourceFiles*(p: AptPaths): seq[string] =
  ## Files APT would read, in APT's order.
  if fileExists(p.sourcesList): result.add p.sourcesList
  var dfiles: seq[string]
  if dirExists(p.sourcesListD):
    for kind, f in walkDir(p.sourcesListD):
      if kind notin {pcFile, pcLinkToFile}: continue
      let name = f.extractFilename
      if not isValidAptFileName(name): continue
      if name.endsWith(".list") or name.endsWith(".sources"): dfiles.add f
  dfiles.sort()
  result.add dfiles

proc parseSourceContent*(path, content: string): SourceFile =
  let fmt = formatFor(path)
  result = SourceFile(path: path, raw: content, format: fmt)
  try:
    case fmt
    of sfDeb822: result.d822 = parseDeb822(content)
    of sfOneLine: result.ol = parseOneLine(content)
  except Deb822Error as e:
    result.error = e.msg

proc loadSourceFile*(path: string): SourceFile =
  parseSourceContent(path, readFile(path))

proc loadAllSources*(p: AptPaths): seq[SourceFile] =
  for f in listSourceFiles(p): result.add loadSourceFile(f)

proc render*(f: SourceFile): string =
  if f.error.len > 0: return f.raw
  case f.format
  of sfDeb822: f.d822.render
  of sfOneLine: f.ol.render

proc isModified*(f: SourceFile): bool = f.render != f.raw

# ---------------------------------------------------------------- entries

const coreFields = ["Types", "URIs", "Suites", "Components", "Architectures",
                    "Signed-By", "Enabled"]

proc entryFromStanza*(s: Stanza, path: string, index: int): SourceEntry =
  result = SourceEntry(file: path, format: sfDeb822, index: index)
  result.enabled = s.getFieldOr("Enabled", "yes").strip.toLowerAscii notin ["no", "false", "0"]
  result.types = s.getFieldOr("Types").splitWhitespace
  result.uris = s.getFieldOr("URIs").splitWhitespace
  result.suites = s.getFieldOr("Suites").splitWhitespace
  result.components = s.getFieldOr("Components").splitWhitespace
  result.architectures = s.getFieldOr("Architectures").splitWhitespace
  result.signedBy = s.getFieldOr("Signed-By")
  for it in s.items:
    if it.kind == ikField:
      var core = false
      for c in coreFields:
        if cmpIgnoreCase(c, it.name) == 0: core = true
      if not core: result.options.add (it.name, it.value)

proc entryFromLine*(l: OneLine, path: string, index: int): SourceEntry =
  assert l.kind == olEntry
  result = SourceEntry(file: path, format: sfOneLine, index: index, enabled: l.enabled,
                       types: @[l.typ], uris: @[l.uri], suites: @[l.suite],
                       components: l.components)
  for (k, v) in l.options:
    let name = toDeb822Name(k)
    case name
    of "Architectures": result.architectures = v.split(',')
    of "Signed-By": result.signedBy = v
    else: result.options.add (name, v)

proc entries*(f: SourceFile): seq[SourceEntry] =
  if f.error.len > 0: return
  case f.format
  of sfDeb822:
    var i = 0
    for s in f.d822.stanzas:
      result.add entryFromStanza(s, f.path, i)
      inc i
  of sfOneLine:
    for i, l in f.ol.lines:
      if l.kind == olEntry: result.add entryFromLine(l, f.path, i)

# ---------------------------------------------------------------- editing

proc applyEntry*(f: var SourceFile, e: SourceEntry) =
  ## Write the fields of `e` back into the file at `e.index`, touching only
  ## what changed.
  case f.format
  of sfDeb822:
    var s = addr f.d822.stanzaMut(e.index)
    template put(name: string, v: string) =
      if v.len == 0: s[].removeField(name)
      else: s[].setField(name, v)
    put("Types", e.types.join(" "))
    put("URIs", e.uris.join(" "))
    put("Suites", e.suites.join(" "))
    put("Components", e.components.join(" "))
    put("Architectures", e.architectures.join(" "))
    put("Signed-By", e.signedBy)
    if e.enabled:
      if s[].getField("Enabled").isSome: s[].removeField("Enabled")
    else:
      s[].setField("Enabled", "no")
    for (k, v) in e.options: put(k, v)
  of sfOneLine:
    var l = addr f.ol.lines[e.index]
    let before = l[].format
    l.enabled = e.enabled
    l.typ = e.types[0]
    l.uri = e.uris[0]
    l.suite = e.suites[0]
    l.components = e.components
    l[].setOption("arch", e.architectures.join(","))
    l[].setOption("signed-by", e.signedBy)
    for (k, v) in e.options: l[].setOption(toOneLineName(k), v)
    if l[].format != before: l.dirty = true

# ---------------------------------------------------------------- conversion

proc entryToStanza*(e: SourceEntry): Stanza =
  var fields: seq[(string, string)] = @[
    ("Types", e.types.join(" ")), ("URIs", e.uris.join(" ")),
    ("Suites", e.suites.join(" "))]
  if e.components.len > 0: fields.add ("Components", e.components.join(" "))
  if e.architectures.len > 0: fields.add ("Architectures", e.architectures.join(" "))
  if e.signedBy.len > 0: fields.add ("Signed-By", e.signedBy)
  for o in e.options: fields.add o
  if not e.enabled: fields.add ("Enabled", "no")
  newStanza(fields)

proc sameExceptType(a, b: SourceEntry): bool =
  a.enabled == b.enabled and a.uris == b.uris and a.suites == b.suites and
    a.components == b.components and a.architectures == b.architectures and
    a.signedBy == b.signedBy and a.options == b.options

proc convertToDeb822*(f: SourceFile): string =
  ## Convert a one-line file to deb822 text. Adjacent entries differing only
  ## in deb/deb-src are merged. Stand-alone comments become stanza comments.
  assert f.format == sfOneLine
  var doc: Deb822Doc
  var pendingComments: seq[string]
  var last: Option[SourceEntry]
  proc flush(doc: var Deb822Doc, last: var Option[SourceEntry], comments: var seq[string]) =
    if last.isSome:
      var s = entryToStanza(last.get)
      for i in countdown(comments.high, 0):
        s.items.insert(Item(kind: ikComment, text: comments[i]), 0)
      comments = @[]
      doc.addStanza(s)
      last = none(SourceEntry)
  for i, l in f.ol.lines:
    case l.kind
    of olOther:
      if l.raw.strip.len > 0:
        flush(doc, last, pendingComments)
        pendingComments.add(if l.raw.strip.startsWith('#'): l.raw.strip else: "# " & l.raw.strip)
    of olEntry:
      let e = entryFromLine(l, f.path, i)
      if last.isSome and sameExceptType(last.get, e) and e.types[0] notin last.get.types:
        var m = last.get
        m.types.add e.types[0]
        m.types.sort() # "deb" before "deb-src"
        last = some(m)
      else:
        flush(doc, last, pendingComments)
        if l.comment.strip.len > 0: pendingComments.add "#" & l.comment
        last = some(e)
  flush(doc, last, pendingComments)
  if pendingComments.len > 0:
    doc.blocks.add Block(kind: bkGap, lines: @[""] & pendingComments)
  doc.trailingNewline = true
  doc.render
