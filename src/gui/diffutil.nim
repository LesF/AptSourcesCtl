## Unified diff generation utility for previewing pending changes.

import std/[strutils, math]

type
  DiffOpKind* = enum
    opEqual, opInsert, opDelete

  DiffOp* = object
    kind*: DiffOpKind
    text*: string

proc diffLines*(a, b: seq[string]): seq[DiffOp] =
  ## Compute an edit script between two sequences of lines using dynamic programming LCS.
  let n = a.len
  let m = b.len
  var dp = newSeq[seq[int]](n + 1)
  for i in 0 .. n:
    dp[i] = newSeq[int](m + 1)

  for i in 1 .. n:
    for j in 1 .. m:
      if a[i - 1] == b[j - 1]:
        dp[i][j] = dp[i - 1][j - 1] + 1
      else:
        dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])

  var i = n
  var j = m
  var ops: seq[DiffOp] = @[]
  while i > 0 or j > 0:
    if i > 0 and j > 0 and a[i - 1] == b[j - 1]:
      ops.add DiffOp(kind: opEqual, text: a[i - 1])
      dec i
      dec j
    elif j > 0 and (i == 0 or dp[i][j - 1] >= dp[i - 1][j]):
      ops.add DiffOp(kind: opInsert, text: b[j - 1])
      dec j
    else:
      ops.add DiffOp(kind: opDelete, text: a[i - 1])
      dec i

  # Reverse ops to get chronological order
  for k in 0 ..< ops.len div 2:
    let opp = ops.len - 1 - k
    let tmp = ops[k]
    ops[k] = ops[opp]
    ops[opp] = tmp

  ops

proc unifiedDiff*(origPath, newPath, origText, newText: string; contextLines = 3): string =
  ## Format a unified diff between origText and newText with file headers.
  let a = if origText.len == 0: @[] else: origText.splitLines()
  let b = if newText.len == 0: @[] else: newText.splitLines()
  if a == b: return ""

  let ops = diffLines(a, b)
  var outLines: seq[string] = @[
    "--- " & origPath,
    "+++ " & newPath
  ]

  # Find hunks
  var idx = 0
  while idx < ops.len:
    # Find next change
    while idx < ops.len and ops[idx].kind == opEqual:
      inc idx
    if idx >= ops.len: break

    # Context before
    let startIdx = max(0, idx - contextLines)
    # Find end of this hunk
    var endIdx = idx
    var consecutiveEqual = 0
    while endIdx < ops.len:
      if ops[endIdx].kind == opEqual:
        inc consecutiveEqual
        if consecutiveEqual > contextLines * 2:
          break
      else:
        consecutiveEqual = 0
      inc endIdx

    let hunkEnd = min(ops.len, endIdx - consecutiveEqual + contextLines)

    outLines.add "@@" # marker
    for k in startIdx ..< hunkEnd:
      case ops[k].kind
      of opEqual: outLines.add " " & ops[k].text
      of opInsert: outLines.add "+" & ops[k].text
      of opDelete: outLines.add "-" & ops[k].text

    idx = hunkEnd

  outLines.join("\n") & "\n"

