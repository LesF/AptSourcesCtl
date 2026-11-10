## Privileged helper for AptSourcesCtl.
## Run via pkexec to validate and atomically write APT configuration files.

import std/[os, strutils, json]

type
  FileOp = object
    action: string # "write" or "delete"
    path: string
    content: string

proc validateSafePath(path: string, root = ""): bool =
  let target = if root.len > 0: root / "etc/apt" else: "/etc/apt"
  let norm = normalizedPath(absolutePath(path))
  let targetNorm = normalizedPath(absolutePath(target))
  norm.startsWith(targetNorm) and not norm.contains("..")

proc applyPayload(root: string, operations: seq[FileOp]): int =
  for op in operations:
    if not validateSafePath(op.path, root):
      stderr.writeLine("Security rejection: path outside /etc/apt: " & op.path)
      return 2

    case op.action
    of "delete":
      if fileExists(op.path):
        removeFile(op.path)
    of "write":
      let dir = op.path.parentDir
      if not dirExists(dir):
        createDir(dir)
      let tmpPath = op.path & ".tmp"
      writeFile(tmpPath, op.content)
      setFilePermissions(tmpPath, {fpUserRead, fpUserWrite, fpGroupRead, fpOthersRead})
      moveFile(tmpPath, op.path)
    else:
      stderr.writeLine("Unknown action: " & op.action)
      return 3
  return 0

proc main() =
  let root = getEnv("APTSOURCESCTL_ROOT", "")
  if paramCount() >= 1 and paramStr(1) in ["--help", "-h"]:
    echo "AptSourcesCtl privileged helper - expects JSON list of operations on stdin"
    quit(0)

  let input = stdin.readAll()
  if input.strip.len == 0:
    quit(0)

  try:
    let node = parseJson(input)
    var ops: seq[FileOp] = @[]
    for item in node:
      ops.add FileOp(
        action: item["action"].getStr(),
        path: item["path"].getStr(),
        content: if item.hasKey("content"): item["content"].getStr() else: ""
      )
    quit(applyPayload(root, ops))
  except Exception as e:
    stderr.writeLine("Helper error: " & e.msg)
    quit(1)

when isMainModule:
  main()
