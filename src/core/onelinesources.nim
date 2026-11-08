## Lossless parser for one-line style sources (sources.list, *.list).
##
##   [#] deb|deb-src [ opt=val ... ] uri suite [component ...] [# comment]
##
## Lines are kept verbatim unless an entry is modified (`dirty`), in which case
## only that line is regenerated. Commented-out entries are recognised as
## disabled entries.

import std/strutils

type
  OneLineKind* = enum olEntry, olOther

  OneLine* = object
    raw*: string
    case kind*: OneLineKind
    of olEntry:
      enabled*: bool
      typ*: string
      options*: seq[(string, string)] ## key may end in '+' / '-'
      uri*: string
      suite*: string
      components*: seq[string]
      comment*: string                ## trailing comment text (after '#')
      dirty*: bool
    of olOther: discard

  OneLineDoc* = object
    lines*: seq[OneLine]
    trailingNewline*: bool

proc tokens(s: string): seq[string] =
  ## Whitespace split that keeps `[...]` groups inside a token together
  ## (e.g. `cdrom:[Debian GNU/Linux 13 ...]/`).
  var cur = ""
  var depth = 0
  for c in s:
    if c == '[': inc depth
    elif c == ']' and depth > 0: dec depth
    if c in Whitespace and depth == 0:
      if cur.len > 0: result.add cur; cur = ""
    else: cur.add c
  if cur.len > 0: result.add cur

proc parseEntry(body: string, enabled: bool, raw: string, ok: var bool): OneLine =
  ## `body` is the line without any leading disable-'#'.
  ok = false
  var s = body
  var comment = ""
  let h = s.find('#')
  if h >= 0:
    comment = s[h + 1 .. ^1]
    s = s[0 ..< h]
  s = s.strip
  var typ = ""
  for t in ["deb-src", "deb"]:
    if s.startsWith(t) and (s.len == t.len or s[t.len] in Whitespace + {'['}):
      typ = t
      break
  if typ.len == 0: return
  s = s[typ.len .. ^1].strip(trailing = false)
  var opts: seq[(string, string)]
  if s.startsWith('['):
    let e = s.find(']')
    if e < 0: return
    for tok in s[1 ..< e].splitWhitespace:
      let eq = tok.find('=')
      if eq <= 0: return
      opts.add (tok[0 ..< eq], tok[eq + 1 .. ^1])
    s = s[e + 1 .. ^1]
  let toks = s.tokens
  if toks.len < 2: return
  let suite = toks[1]
  if toks.len == 2 and not suite.endsWith('/'): return
  ok = true
  OneLine(kind: olEntry, raw: raw, enabled: enabled, typ: typ, options: opts,
          uri: toks[0], suite: suite, components: toks[2 .. ^1], comment: comment)

proc parseLine*(line: string): OneLine =
  var ok: bool
  let st = line.strip
  if st.startsWith('#'):
    let body = st.strip(trailing = false, chars = {'#'} + Whitespace)
    result = parseEntry(body, false, line, ok)
  else:
    result = parseEntry(st, true, line, ok)
  if not ok: result = OneLine(kind: olOther, raw: line)

proc parseOneLine*(content: string): OneLineDoc =
  result.trailingNewline = content.len == 0 or content.endsWith('\n')
  if content.len == 0: return
  var ls = content.split('\n')
  if content.endsWith('\n'): ls.setLen(ls.len - 1)
  for l in ls: result.lines.add parseLine(l)

proc format*(e: OneLine): string =
  assert e.kind == olEntry
  if not e.enabled: result.add "# "
  result.add e.typ
  if e.options.len > 0:
    result.add " ["
    for i, (k, v) in e.options:
      if i > 0: result.add ' '
      result.add k & "=" & v
    result.add ']'
  result.add " " & e.uri & " " & e.suite
  for c in e.components: result.add " " & c
  if e.comment.len > 0: result.add " #" & e.comment

proc render*(doc: OneLineDoc): string =
  var parts: seq[string]
  for l in doc.lines:
    parts.add(if l.kind == olEntry and l.dirty: l.format else: l.raw)
  result = parts.join("\n")
  if doc.trailingNewline and parts.len > 0: result.add '\n'

proc getOption*(e: OneLine, key: string): string =
  for (k, v) in e.options:
    if cmpIgnoreCase(k, key) == 0: return v

proc setOption*(e: var OneLine, key, value: string) =
  for i, (k, v) in e.options:
    if cmpIgnoreCase(k, key) == 0:
      if value.len == 0: e.options.delete(i)
      elif v != value: e.options[i][1] = value
      else: return
      e.dirty = true
      return
  if value.len > 0:
    e.options.add (key, value)
    e.dirty = true
