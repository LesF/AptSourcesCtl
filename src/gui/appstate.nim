## In-memory state and dirty-change manager for AptSourcesCtl.

import std/[os, strutils, tables, sets]
import ../core
import ./diffutil

type
  AppState* = ref object
    paths*: AptPaths
    sources*: seq[SourceFile]
    keyrings*: seq[KeyringFile]
    prefs*: seq[PrefFile]
    issues*: seq[Issue]
    converted*: Table[string, SourceFile] ## orig .list path -> converted .sources SourceFile
    deletedFiles*: HashSet[string]
    listeners*: seq[proc()]

proc notifyChanged*(self: AppState) =
  for cb in self.listeners:
    if cb != nil: cb()

proc addChangeListener*(self: AppState, cb: proc()) =
  self.listeners.add cb

proc recomputeIssues*(self: AppState) =
  var all: seq[SourceEntry] = @[]
  for f in self.sources:
    if f.path notin self.deletedFiles:
      for e in f.entries:
        all.add e
  for origPath, f in self.converted:
    for e in f.entries:
      all.add e

  let codename = self.paths.releaseCodename
  self.issues = validateAll(all, self.paths, codename)
  for f in self.prefs:
    for r in f.rules:
      for iss in validateRule(r):
        self.issues.add iss

proc reload*(self: AppState) =
  self.converted.clear()
  self.deletedFiles.clear()
  self.sources = loadAllSources(self.paths)
  self.keyrings = scanKeyrings(self.paths)
  self.prefs = loadAllPrefs(self.paths)

  var all: seq[SourceEntry] = @[]
  for f in self.sources:
    for e in f.entries: all.add e
  self.keyrings.crossReference(all, self.paths)
  self.recomputeIssues()
  self.notifyChanged()

proc newAppState*(root = ""): AppState =
  result = AppState(
    paths: initAptPaths(root),
    converted: initTable[string, SourceFile](),
    deletedFiles: initHashSet[string](),
    listeners: @[]
  )
  result.reload()

proc allEntries*(self: AppState): seq[tuple[fileIdx: int, entryIdx: int, entry: SourceEntry]] =
  for fIdx, f in self.sources:
    if f.path in self.deletedFiles: continue
    var eIdx = 0
    for e in f.entries:
      result.add (fIdx, eIdx, e)
      inc eIdx
  # Also include converted files
  for origPath, f in self.converted:
    var eIdx = 0
    for e in f.entries:
      result.add (-1, eIdx, e) # -1 marks converted file
      inc eIdx

proc toggleEntry*(self: AppState, fileIdx: int, entryIdx: int) =
  if fileIdx >= 0 and fileIdx < self.sources.len:
    var entries = self.sources[fileIdx].entries
    if entryIdx >= 0 and entryIdx < entries.len:
      var e = entries[entryIdx]
      e.enabled = not e.enabled
      self.sources[fileIdx].applyEntry(e)
      self.recomputeIssues()
      self.notifyChanged()

proc updateEntry*(self: AppState, fileIdx: int, entryIdx: int, updated: SourceEntry) =
  if fileIdx >= 0 and fileIdx < self.sources.len:
    self.sources[fileIdx].applyEntry(updated)
    self.recomputeIssues()
    self.notifyChanged()

proc convertFileToDeb822*(self: AppState, fileIdx: int): bool =
  if fileIdx < 0 or fileIdx >= self.sources.len: return false
  let orig = self.sources[fileIdx]
  if orig.format != sfOneLine: return false

  let deb822Text = orig.convertToDeb822()
  let filename = extractFilename(orig.path)
  let baseName = if filename.endsWith(".list"):
    filename[0 ..< filename.len - 5] & ".sources"
  else:
    filename & ".sources"
  let targetPath = self.paths.sourcesListD / baseName

  let convertedFile = parseSourceContent(targetPath, deb822Text)
  self.converted[orig.path] = convertedFile
  self.deletedFiles.incl orig.path
  self.recomputeIssues()
  self.notifyChanged()
  return true

proc isDirty*(self: AppState): bool =
  if self.converted.len > 0 or self.deletedFiles.len > 0: return true
  for f in self.sources:
    if f.isModified: return true
  for f in self.prefs:
    if f.render != f.raw: return true
  return false

proc dirtyCount*(self: AppState): int =
  var count = 0
  if self.deletedFiles.len > 0: count += self.deletedFiles.len
  if self.converted.len > 0: count += self.converted.len
  for f in self.sources:
    if f.path notin self.deletedFiles and f.isModified: inc count
  for f in self.prefs:
    if f.render != f.raw: inc count
  count

proc getDiffs*(self: AppState): seq[tuple[path: string, status: string, diff: string]] =
  ## Return diffs for all modified, converted, or deleted files.
  for origPath in self.deletedFiles:
    if origPath in self.converted:
      let conv = self.converted[origPath]
      let diffT = unifiedDiff("/dev/null", conv.path, "", conv.render)
      result.add (conv.path, "converted (new)", diffT)
      let delDiff = unifiedDiff(origPath, "/dev/null", readFile(origPath), "")
      result.add (origPath, "converted (removed)", delDiff)
    else:
      let delDiff = unifiedDiff(origPath, "/dev/null", readFile(origPath), "")
      result.add (origPath, "deleted", delDiff)

  for f in self.sources:
    if f.path notin self.deletedFiles and f.isModified:
      let diffT = unifiedDiff(f.path, f.path, f.raw, f.render)
      result.add (f.path, "modified", diffT)

  for f in self.prefs:
    if f.render != f.raw:
      let diffT = unifiedDiff(f.path, f.path, f.raw, f.render)
      result.add (f.path, "modified", diffT)

proc revertAll*(self: AppState) =
  self.reload()

proc issuesForEntry*(self: AppState, file: string, index: int): seq[Issue] =
  for iss in self.issues:
    if iss.file == file and iss.index == index:
      result.add iss
