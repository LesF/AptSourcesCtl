## Lossless deb822 parser/renderer.
##
## The document keeps every original line: comments, blank lines, field order,
## field-name casing and continuation formatting. `render(parseDeb822(x)) == x`
## holds byte-for-byte. Edits only rewrite the field(s) they touch.

import std/[strutils, options]

type
  Deb822Error* = object of ValueError
    line*: int ## 1-based line number

  ItemKind* = enum ikField, ikComment

  Item* = object
    case kind*: ItemKind
    of ikField:
      name*: string        ## as written in the file
      raw*: seq[string]    ## first line plus continuation lines, verbatim
    of ikComment:
      text*: string        ## verbatim comment line

  Stanza* = object
    items*: seq[Item]

  BlockKind* = enum bkStanza, bkGap

  Block* = object
    case kind*: BlockKind
    of bkStanza: stanza*: Stanza
    of bkGap: lines*: seq[string] ## blank lines and stand-alone comment paragraphs

  Deb822Doc* = object
    blocks*: seq[Block]
    trailingNewline*: bool

proc raiseAt(line: int, msg: string) {.noreturn.} =
  var e = newException(Deb822Error, "line " & $line & ": " & msg)
  e.line = line
  raise e

proc isBlank(s: string): bool {.inline.} = s.strip.len == 0
proc isComment(s: string): bool {.inline.} = s.len > 0 and s[0] == '#'
proc isContinuation(s: string): bool {.inline.} = s.len > 0 and s[0] in {' ', '\t'}

proc splitLinesKeep(content: string): (seq[string], bool) =
  if content.len == 0: return (@[], true)
  var ls = content.split('\n')
  let trailing = content.endsWith('\n')
  if trailing: ls.setLen(ls.len - 1)
  (ls, trailing)

proc hasFields*(s: Stanza): bool =
  for it in s.items:
    if it.kind == ikField: return true

proc parseDeb822*(content: string): Deb822Doc =
  let (lines, trailing) = splitLinesKeep(content)
  result.trailingNewline = trailing
  var cur: Stanza
  var gap: seq[string]

  template flushGap() =
    if gap.len > 0:
      result.blocks.add Block(kind: bkGap, lines: gap)
      gap = @[]

  template flushStanza() =
    if cur.items.len > 0:
      if cur.hasFields:
        flushGap()
        result.blocks.add Block(kind: bkStanza, stanza: cur)
      else:
        # comment-only paragraph: not a stanza
        for it in cur.items: gap.add it.text
      cur = Stanza()

  for i, line in lines:
    let ln = i + 1
    if line.isBlank:
      flushStanza()
      gap.add line
    elif line.isComment:
      cur.items.add Item(kind: ikComment, text: line)
    elif line.isContinuation:
      if cur.items.len == 0 or cur.items[^1].kind != ikField:
        raiseAt(ln, "continuation line without a field")
      cur.items[^1].raw.add line
    else:
      let c = line.find(':')
      if c <= 0:
        raiseAt(ln, "expected 'Field: value'")
      let name = line[0 ..< c]
      if name.contains({' ', '\t'}):
        raiseAt(ln, "invalid field name '" & name & "'")
      cur.items.add Item(kind: ikField, name: name, raw: @[line])
  flushStanza()
  flushGap()

proc renderLines(doc: Deb822Doc): seq[string] =
  for b in doc.blocks:
    case b.kind
    of bkGap: result.add b.lines
    of bkStanza:
      for it in b.stanza.items:
        case it.kind
        of ikField: result.add it.raw
        of ikComment: result.add it.text

proc render*(doc: Deb822Doc): string =
  let ls = doc.renderLines
  result = ls.join("\n")
  if doc.trailingNewline and ls.len > 0: result.add '\n'

# ---------------------------------------------------------------- values

proc value*(it: Item): string =
  ## Field value: first-line text plus continuation lines (" ." = empty line),
  ## joined with '\n'. Leading/trailing whitespace of each line is stripped.
  assert it.kind == ikField
  let first = it.raw[0]
  result = first[first.find(':') + 1 .. ^1].strip
  for i in 1 ..< it.raw.len:
    var l = it.raw[i].strip
    if l == ".": l = ""
    if result.len > 0 or i > 1: result.add '\n'
    result.add l

proc formatField*(name, value: string): seq[string] =
  let parts = value.split('\n')
  result.add(if parts[0].len > 0: name & ": " & parts[0] else: name & ":")
  for i in 1 ..< parts.len:
    result.add(" " & (if parts[i].strip.len == 0: "." else: parts[i]))

proc findField(s: Stanza, name: string): int =
  for i, it in s.items:
    if it.kind == ikField and cmpIgnoreCase(it.name, name) == 0: return i
  -1

proc getField*(s: Stanza, name: string): Option[string] =
  let i = s.findField(name)
  if i >= 0: some(s.items[i].value) else: none(string)

proc getFieldOr*(s: Stanza, name: string, default = ""): string =
  s.getField(name).get(default)

proc getAll*(s: Stanza, name: string): seq[string] =
  for it in s.items:
    if it.kind == ikField and cmpIgnoreCase(it.name, name) == 0: result.add it.value

proc fieldNames*(s: Stanza): seq[string] =
  for it in s.items:
    if it.kind == ikField: result.add it.name

proc setField*(s: var Stanza, name, value: string) =
  ## Replace the value (keeping original name casing and position) or append.
  ## Unchanged values leave the raw lines untouched.
  let i = s.findField(name)
  if i >= 0:
    if s.items[i].value == value: return
    s.items[i].raw = formatField(s.items[i].name, value)
  else:
    var at = s.items.len
    # keep trailing comments at the end of the stanza
    while at > 0 and s.items[at - 1].kind == ikComment: dec at
    s.items.insert(Item(kind: ikField, name: name, raw: formatField(name, value)), at)

proc removeField*(s: var Stanza, name: string): bool {.discardable.} =
  let i = s.findField(name)
  if i >= 0:
    s.items.delete(i)
    return true

proc newStanza*(fields: openArray[(string, string)]): Stanza =
  for (k, v) in fields:
    result.items.add Item(kind: ikField, name: k, raw: formatField(k, v))

# ---------------------------------------------------------------- doc ops

proc stanzaCount*(doc: Deb822Doc): int =
  for b in doc.blocks:
    if b.kind == bkStanza: inc result

proc blockIndexOf(doc: Deb822Doc, n: int): int =
  var k = 0
  for i, b in doc.blocks:
    if b.kind == bkStanza:
      if k == n: return i
      inc k
  raise newException(IndexDefect, "stanza index out of range: " & $n)

proc stanza*(doc: Deb822Doc, n: int): Stanza = doc.blocks[doc.blockIndexOf(n)].stanza

proc stanzaMut*(doc: var Deb822Doc, n: int): var Stanza =
  doc.blocks[doc.blockIndexOf(n)].stanza

iterator stanzas*(doc: Deb822Doc): Stanza =
  for b in doc.blocks:
    if b.kind == bkStanza: yield b.stanza

proc addStanza*(doc: var Deb822Doc, s: Stanza) =
  if doc.blocks.len > 0:
    let last = doc.blocks[^1]
    if not (last.kind == bkGap and last.lines[^1].isBlank):
      doc.blocks.add Block(kind: bkGap, lines: @[""])
  doc.blocks.add Block(kind: bkStanza, stanza: s)
  doc.trailingNewline = true

proc removeStanza*(doc: var Deb822Doc, n: int) =
  ## Remove a stanza (including its attached comments) and one separating blank line.
  let bi = doc.blockIndexOf(n)
  doc.blocks.delete(bi)
  template trimBlank(idx: int) =
    if idx >= 0 and idx < doc.blocks.len and doc.blocks[idx].kind == bkGap and
        doc.blocks[idx].lines.len > 0 and doc.blocks[idx].lines[0].isBlank:
      doc.blocks[idx].lines.delete(0)
      if doc.blocks[idx].lines.len == 0: doc.blocks.delete(idx)
  if bi < doc.blocks.len: trimBlank(bi) else: trimBlank(bi - 1)
