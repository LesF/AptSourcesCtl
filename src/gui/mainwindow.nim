## Main window for AptSourcesCtl in native system configuration panel style.

import std/[strutils, os, sets, tables]
import seaqt/[qmainwindow, qwidget, qvboxlayout, qhboxlayout, qlistwidget,
              qstackedwidget, qpushbutton, qmessagebox]
import ../core
import ./appstate
import ./widgets/statusbar
import ./diffdialog
import ./sourcesview
import ./keyringsview
import ./pinningview
import ./diagnosticsview

type
  MainWindow* = ref object
    win*: QMainWindow
    state*: AppState
    sidebar*: QListWidget
    stack*: QStackedWidget
    footer*: ActionFooter
    sourcesView*: SourcesView
    keyringsView*: KeyringsView
    pinningView*: PinningView
    diagView*: DiagnosticsView

proc applyPendingChanges*(self: MainWindow)

proc createMainWindow*(state: AppState): MainWindow =
  var win = QMainWindow.create()
  win.setWindowTitle("Software Sources & Repositories - APT Configuration")
  win.resize(1000, 680)

  var central = QWidget.create()
  var rootLayout = QVBoxLayout.create(central)
  rootLayout.owned = false

  # Content area with Sidebar on left and StackedWidget on right
  var contentLayout = QHBoxLayout.create()
  contentLayout.owned = false

  var sidebar = QListWidget.create()
  sidebar.owned = false
  sidebar.setMaximumWidth(210)

  sidebar.addItem("Repositories")
  sidebar.addItem("Signing Keys")
  sidebar.addItem("Package Pinning")
  sidebar.addItem("Diagnostics")
  sidebar.setCurrentRow(0)
  contentLayout.addWidget(sidebar)

  # Stack
  var stack = QStackedWidget.create()
  var sv = createSourcesView(stack, state)
  var kv = createKeyringsView(stack, state)
  var pv = createPinningView(stack, state)
  var dv = createDiagnosticsView(stack, state)

  discard stack.addWidget(sv.widget)
  discard stack.addWidget(kv.widget)
  discard stack.addWidget(pv.widget)
  discard stack.addWidget(dv.widget)
  contentLayout.addWidget(stack, 1)

  rootLayout.addLayout(contentLayout, 1)

  # Footer
  var footer = createActionFooter(central, state)
  rootLayout.addWidget(footer.widget)

  win.setCentralWidget(central)
  central.owned = false
  sidebar.owned = false
  stack.owned = false
  win.owned = false
  let winH = win.h
  let stackH = stack.h

  result = MainWindow(
    win: win,
    state: state,
    sidebar: sidebar,
    stack: stack,
    footer: footer,
    sourcesView: sv,
    keyringsView: kv,
    pinningView: pv,
    diagView: dv
  )
  result.win.owned = true

  let mw = result

  # Wire navigation
  mw.sidebar.onCurrentRowChanged(proc(row: cint) {.raises: [].} =
    try:
      var s = QStackedWidget(h: stackH, owned: false)
      s.setCurrentIndex(row)
    except Exception: discard
  )

  # Wire state change notifications
  state.addChangeListener(proc() =
    mw.footer.updateState()
    mw.sourcesView.populate()
    mw.keyringsView.populate()
    mw.pinningView.populate()
    mw.diagView.populate()
  )

  # Wire footer buttons
  mw.footer.revertBtn.onClicked(proc() {.raises: [].} =
    try:
      var w = QWidget(h: winH, owned: false)
      let reply = QMessageBox.question(w, "Revert Changes",
        "Discard all unsaved modifications and revert to files on disk?",
        "Revert", "Cancel")
      if reply == 0:
        mw.state.revertAll()
    except Exception: discard
  )

  mw.footer.diffBtn.onClicked(proc() {.raises: [].} =
    try:
      var w = QWidget(h: winH, owned: false)
      showDiffDialog(w, mw.state)
    except Exception: discard
  )

  mw.footer.reloadBtn.onClicked(proc() {.raises: [].} =
    try: mw.state.reload() except Exception: discard
  )

  mw.footer.applyBtn.onClicked(proc() {.raises: [].} =
    try: mw.applyPendingChanges() except Exception: discard
  )

proc applyPendingChanges*(self: MainWindow) =
  let diffs = self.state.getDiffs()
  if diffs.len == 0: return

  var w = QWidget(h: self.win.h, owned: false)
  let reply = QMessageBox.question(w, "Apply Changes",
    "Are you sure you want to commit " & $diffs.len &
    " file change(s) to the system?",
    "Apply", "Cancel")
  if reply != 0: return

  var allOk = true
  var errors: seq[string] = @[]

  # 1. Process deletions
  for p in self.state.deletedFiles:
    try:
      if p notin self.state.converted and fileExists(p):
        removeFile(p)
    except IOError as e:
      allOk = false
      errors.add "Failed to remove " & p & ": " & e.msg

  # 2. Process converted files
  for origPath, conv in self.state.converted:
    try:
      writeFile(conv.path, conv.render)
      if fileExists(origPath):
        removeFile(origPath)
    except IOError as e:
      allOk = false
      errors.add "Failed to convert " & origPath & " -> " & conv.path & ": " & e.msg

  # 3. Process modified sources
  for f in self.state.sources:
    if f.path notin self.state.deletedFiles and f.isModified:
      try:
        writeFile(f.path, f.render)
      except IOError as e:
        allOk = false
        errors.add "Failed to write " & f.path & ": " & e.msg

  # 4. Process modified prefs
  for f in self.state.prefs:
    if f.render != f.raw:
      try:
        writeFile(f.path, f.render)
      except IOError as e:
        allOk = false
        errors.add "Failed to write " & f.path & ": " & e.msg

  if allOk:
    discard QMessageBox.information(w, "Changes Applied",
      "Successfully applied all modifications to APT configuration.")
    self.state.reload()
  else:
    discard QMessageBox.critical(w, "Error Applying Changes",
      "Some changes could not be applied:\n" & errors.join("\n") &
      "\n\nMake sure you have write permissions or run with administrative privileges.")
