## Keyrings and cryptographic trust view.

import std/[strutils, times, os]
import seaqt/[qwidget, qvboxlayout, qhboxlayout, qsplitter, qtablewidget,
              qlineedit, qlabel, qgroupbox, qformlayout, qplaintextedit]
import ../core
import ./appstate

type
  KeyringsView* = ref object
    widget*: QWidget
    state*: AppState
    table*: QTableWidget
    searchEdit*: QLineEdit
    pathLabel*: QLabel
    statusLabel*: QLabel
    detailsEdit*: QPlainTextEdit
    usedByEdit*: QPlainTextEdit
    inPopulate*: bool

proc populate*(self: KeyringsView)
proc showKeyDetails(self: KeyringsView, k: KeyringFile)

proc createKeyringsView*(parent: QWidget, state: AppState): KeyringsView =
  var w = QWidget.create(parent)
  w.owned = false
  var mainLayout = QVBoxLayout.create(w)
  mainLayout.owned = false

  # Top toolbar
  var toolLayout = QHBoxLayout.create()
  toolLayout.owned = false
  var searchLbl = QLabel.create("Search Keyrings:")
  searchLbl.owned = false
  toolLayout.addWidget(searchLbl)

  var searchEdit = QLineEdit.create()
  searchEdit.owned = false
  searchEdit.setPlaceholderText("Filter keyrings by filename, UID or fingerprint...")
  toolLayout.addWidget(searchEdit, 1)

  mainLayout.addLayout(toolLayout)

  # Splitter
  var splitter = QSplitter.create()
  splitter.owned = false
  splitter.setOrientation(2) # Vertical

  # Table
  var table = QTableWidget.create()
  table.owned = false
  table.setColumnCount(5)
  table.setHorizontalHeaderLabels(@["Keyring File", "Location", "Keys", "Status", "Referenced By"])
  splitter.addWidget(table)

  # Detail Panel
  var group = QGroupBox.create("Keyring Details & Cryptographic Attributes")
  group.owned = false
  var formLayout = QFormLayout.create(group)
  formLayout.owned = false

  var pathLbl = QLabel.create("-")
  pathLbl.owned = false
  formLayout.addRow("Full Path:", pathLbl)

  var statusLbl = QLabel.create("-")
  statusLbl.owned = false
  formLayout.addRow("Trust Status:", statusLbl)

  var detailsEdit = QPlainTextEdit.create()
  detailsEdit.owned = false
  detailsEdit.setReadOnly(true)
  detailsEdit.setMaximumHeight(130)
  formLayout.addRow("Keys & Signatures:", detailsEdit)

  var usedByEdit = QPlainTextEdit.create()
  usedByEdit.owned = false
  usedByEdit.setReadOnly(true)
  usedByEdit.setMaximumHeight(90)
  formLayout.addRow("Used By Sources:", usedByEdit)

  splitter.addWidget(group)
  mainLayout.addWidget(splitter, 1)

  result = KeyringsView(
    widget: w,
    state: state,
    table: table,
    searchEdit: searchEdit,
    pathLabel: pathLbl,
    statusLabel: statusLbl,
    detailsEdit: detailsEdit,
    usedByEdit: usedByEdit,
    inPopulate: false
  )

  let kv = result

  kv.searchEdit.onTextChanged(proc(t: openArray[char]) {.raises: [].} =
    try: kv.populate() except Exception: discard
  )

  kv.table.onItemSelectionChanged(proc() {.raises: [].} =
    try:
      if kv.inPopulate: return
      let r = kv.table.currentRow()
      if r >= 0 and r < kv.state.keyrings.len:
        kv.showKeyDetails(kv.state.keyrings[r])
    except Exception: discard
  )

  kv.populate()

proc showKeyDetails(self: KeyringsView, k: KeyringFile) =
  self.pathLabel.setText(k.path)

  var statusStr = ""
  if k.isOrphan:
    statusStr = "ORPHAN (Not referenced by any active software source in /etc/apt/keyrings)"
  elif k.location in {klTrustedD, klLegacy}:
    statusStr = "GLOBAL TRUST (Deprecated: trust validates ALL packages on system)"
  elif k.error.len > 0:
    statusStr = "ERROR: " & k.error
  else:
    statusStr = "Active & Trusted (Scoped to specific repositories via Signed-By)"
  self.statusLabel.setText(statusStr)

  var details: seq[string] = @[]
  if k.keys.len == 0:
    details.add("No cryptographic keys could be extracted.")
  for key in k.keys:
    details.add("UID:         " & key.uid)
    details.add("Fingerprint: " & key.fingerprint)
    details.add("Algorithm:   " & key.algo & " (" & $key.bits & " bits)")
    let createdDate = if key.created > 0: fromUnix(key.created).format("yyyy-MM-dd") else: "unknown"
    let expireDate = if key.expires == 0: "Never" else: fromUnix(key.expires).format("yyyy-MM-dd")
    details.add("Created:     " & createdDate & " | Expires: " & expireDate &
      (if key.expired: " [EXPIRED]" else: "") & (if key.revoked: " [REVOKED]" else: ""))
    details.add("")

  self.detailsEdit.setPlainText(details.join("\n"))

  if k.usedBy.len > 0:
    self.usedByEdit.setPlainText(k.usedBy.join("\n"))
  else:
    self.usedByEdit.setPlainText("(No software sources currently reference this file)")

proc makeItem(text: string): QTableWidgetItem =
  result = QTableWidgetItem.create(text)
  result.owned = false

proc populate*(self: KeyringsView) =
  self.inPopulate = true
  let search = self.searchEdit.text().toLowerAscii()

  var matched: seq[KeyringFile] = @[]
  for k in self.state.keyrings:
    var matches = search.len == 0 or k.path.toLowerAscii.contains(search)
    for key in k.keys:
      if key.uid.toLowerAscii.contains(search) or key.fingerprint.toLowerAscii.contains(search):
        matches = true
    if matches:
      matched.add k

  self.table.setRowCount(cint(matched.len))
  for i, k in matched:
    let r = cint(i)
    let fName = k.path.extractFilename
    self.table.setItem(r, 0, makeItem(fName))
    self.table.setItem(r, 1, makeItem($k.location))
    self.table.setItem(r, 2, makeItem($k.keys.len & " key(s)" & (if k.armored: " [asc]" else: " [bin]")))

    var st = "Valid"
    if k.isOrphan: st = "Orphan"
    elif k.location in {klTrustedD, klLegacy}: st = "Global Trust"
    elif k.error.len > 0: st = "Error"
    self.table.setItem(r, 3, makeItem(st))
    self.table.setItem(r, 4, makeItem($k.usedBy.len & " source(s)"))

  self.inPopulate = false
  if matched.len > 0:
    self.showKeyDetails(matched[0])
