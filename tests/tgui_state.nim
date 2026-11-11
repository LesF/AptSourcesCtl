import std/[unittest, strutils, tables, os]
import ../src/gui/[diffutil, appstate]
import ../src/core

suite "diff and appstate":
  test "unified diff generation":
    let a = "line1\nline2\nline3\n"
    let b = "line1\nline2_modified\nline3\nline4\n"
    let d = unifiedDiff("fileA", "fileB", a, b)
    check d.contains("--- fileA")
    check d.contains("+++ fileB")
    check d.contains("-line2")
    check d.contains("+line2_modified")
    check d.contains("+line4")

  test "appstate load fixtures":
    let state = newAppState("tests/fixtures/root")
    check state.sources.len > 0
    check state.keyrings.len > 0
    check state.prefs.len > 0
    check not state.isDirty()

    # Find the one-line sources.list file
    var olIdx = -1
    for i, s in state.sources:
      if s.format == sfOneLine:
        olIdx = i
        break
    check olIdx >= 0

    # Toggle entry
    state.toggleEntry(olIdx, 0)
    check state.isDirty()
    let diffs = state.getDiffs()
    check diffs.len == 1

    # Revert
    state.revertAll()
    check not state.isDirty()

    # Convert to deb822
    let origPath = state.sources[olIdx].path
    let convertedOk = state.convertFileToDeb822(olIdx)
    check convertedOk
    check state.isDirty()
    check origPath in state.converted
    check state.converted[origPath].path == state.paths.sourcesListD / "sources.sources"
    let convDiffs = state.getDiffs()
    check convDiffs.len == 2 # 1 new deb822, 1 removed one-line
    check convDiffs[0].path == state.paths.sourcesListD / "sources.sources"

