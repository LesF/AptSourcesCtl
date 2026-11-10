## Diagnostics and health checks view.

import std/[strutils, os]
import seaqt/[qwidget, qvboxlayout, qsplitter, qtablewidget, qlabel, qgroupbox,
              qformlayout, qplaintextedit]
import ../core
import ./appstate

type
  DiagnosticsView* = ref object
    widget*: QWidget
    state*: AppState
    table*: QTableWidget
    countLabel*: QLabel
    descEdit*: QPlainTextEdit
    remedyEdit*: QPlainTextEdit
    inPopulate*: bool

proc populate*(self: DiagnosticsView)
proc showIssueDetails(self: DiagnosticsView, iss: Issue)

proc createDiagnosticsView*(parent: QWidget, state: AppState): DiagnosticsView =
  var w = QWidget.create(parent)
  w.owned = false
  var mainLayout = QVBoxLayout.create(w)
  mainLayout.owned = false

  var countLbl = QLabel.create("System Health Diagnostics")
  countLbl.owned = false
  mainLayout.addWidget(countLbl)

  var splitter = QSplitter.create()
  splitter.owned = false
  splitter.setOrientation(2)

  var table = QTableWidget.create()
  table.owned = false
  table.setColumnCount(4)
  table.setHorizontalHeaderLabels(@["Severity", "File", "Entry #", "Issue Summary"])
  splitter.addWidget(table)

  # Issue Details
  var group = QGroupBox.create("Diagnostic Assessment & Recommended Remedy")
  group.owned = false
  var formLayout = QFormLayout.create(group)
  formLayout.owned = false

  var descEdit = QPlainTextEdit.create()
  descEdit.owned = false
  descEdit.setReadOnly(true)
  descEdit.setMaximumHeight(80)
  formLayout.addRow("Description:", descEdit)

  var remedyEdit = QPlainTextEdit.create()
  remedyEdit.owned = false
  remedyEdit.setReadOnly(true)
  remedyEdit.setMaximumHeight(80)
  formLayout.addRow("Recommended Action:", remedyEdit)

  splitter.addWidget(group)
  mainLayout.addWidget(splitter, 1)

  result = DiagnosticsView(
    widget: w,
    state: state,
    table: table,
    countLabel: countLbl,
    descEdit: descEdit,
    remedyEdit: remedyEdit,
    inPopulate: false
  )

  let dv = result

  dv.table.onItemSelectionChanged(proc() {.raises: [].} =
    try:
      if dv.inPopulate: return
      let r = dv.table.currentRow()
      if r >= 0 and r < dv.state.issues.len:
        dv.showIssueDetails(dv.state.issues[r])
    except Exception: discard
  )

  dv.populate()

proc showIssueDetails(self: DiagnosticsView, iss: Issue) =
  self.descEdit.setPlainText(
    "File: " & iss.file & "\n" &
    "Index: Line or stanza #" & $(iss.index + 1) & "\n" &
    "Message: " & iss.message
  )

  var remedy = ""
  if "duplicate" in iss.message.toLowerAscii:
    remedy = "The same package archive is configured multiple times. Disable or remove one of the duplicate entries in the Repositories view to speed up apt updates."
  elif "keyring not found" in iss.message.toLowerAscii:
    remedy = "A repository references a Signed-By keyring file that does not exist on disk. Check that the key file is installed under /etc/apt/keyrings or /usr/share/keyrings."
  elif "no signed-by" in iss.message.toLowerAscii:
    remedy = "This repository relies on global trusted keys (trusted.gpg.d). To follow Debian Trixie best practices, specify an explicit keyring path in the Signed-By field."
  elif "older than this system" in iss.message.toLowerAscii or "newer than this system" in iss.message.toLowerAscii:
    remedy = "Suite codename does not match current system codename. Verify your distribution settings or configure pinning if intentionally tracking backports or another release."
  else:
    remedy = "Review the entry settings in the Repositories or Pinning view."

  self.remedyEdit.setPlainText(remedy)

proc makeItem(text: string): QTableWidgetItem =
  result = QTableWidgetItem.create(text)
  result.owned = false

proc populate*(self: DiagnosticsView) =
  self.inPopulate = true
  let total = self.state.issues.len

  var errors = 0
  var warnings = 0
  for iss in self.state.issues:
    if iss.severity == sevError: inc errors
    elif iss.severity == sevWarning: inc warnings

  self.countLabel.setText(
    "Detected " & $total & " item" & (if total == 1: "" else: "s") &
    " (" & $errors & " errors, " & $warnings & " warnings)"
  )

  self.table.setRowCount(cint(total))
  for i, iss in self.state.issues:
    let row = cint(i)
    self.table.setItem(row, 0, makeItem(toUpperAscii($iss.severity)))
    self.table.setItem(row, 1, makeItem(iss.file.extractFilename))
    self.table.setItem(row, 2, makeItem("#" & $(iss.index + 1)))
    self.table.setItem(row, 3, makeItem(iss.message))

  self.inPopulate = false
  if total > 0:
    self.showIssueDetails(self.state.issues[0])
  else:
    self.descEdit.setPlainText("No configuration errors or warnings detected.")
    self.remedyEdit.setPlainText("System software sources are in excellent health.")
