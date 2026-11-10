## Repositories & Sources management view (list, filter, translate, and edit).

import std/[strutils, tables, sets, os]
import seaqt/[qwidget, qvboxlayout, qhboxlayout, qsplitter, qtreewidget, qlineedit,
              qcombobox, qpushbutton, qlabel, qcheckbox, qgroupbox, qformlayout,
              qmessagebox, qicon]
import ../core
import ./appstate

type
  SourcesView* = ref object
    widget*: QWidget
    state*: AppState
    tree*: QTreeWidget
    searchEdit*: QLineEdit
    filterCombo*: QComboBox
    translateBtn*: QPushButton
    # Editor fields
    editGroup*: QGroupBox
    uriEdit*: QLineEdit
    suiteEdit*: QLineEdit
    compEdit*: QLineEdit
    signedByEdit*: QLineEdit
    debCheck*: QCheckBox
    debSrcCheck*: QCheckBox
    saveEntryBtn*: QPushButton
    # Mapping
    itemMap*: Table[int, tuple[fileIdx: int, entryIdx: int]]
    selectedFileIdx*: int
    selectedEntryIdx*: int
    inPopulate*: bool

proc populate*(self: SourcesView)
proc updateEditor(self: SourcesView, hasSelection: bool, entry: SourceEntry)

proc createSourcesView*(parent: QWidget, state: AppState): SourcesView =
  var w = QWidget.create(parent)
  w.owned = false
  var mainLayout = QVBoxLayout.create(w)
  mainLayout.owned = false

  # Top toolbar
  var toolLayout = QHBoxLayout.create()
  toolLayout.owned = false
  var searchLbl = QLabel.create("Search:")
  searchLbl.owned = false
  toolLayout.addWidget(searchLbl)

  var searchEdit = QLineEdit.create()
  searchEdit.owned = false
  searchEdit.setPlaceholderText("Filter by URI, suite, or component...")
  toolLayout.addWidget(searchEdit, 2)

  var filterCombo = QComboBox.create()
  filterCombo.owned = false
  filterCombo.addItem("All Sources")
  filterCombo.addItem("Enabled Only")
  filterCombo.addItem("Disabled Only")
  filterCombo.addItem("One-line (.list) Only")
  filterCombo.addItem("deb822 (.sources) Only")
  toolLayout.addWidget(filterCombo, 1)

  var translateBtn = QPushButton.create("Translate to deb822")
  translateBtn.owned = false
  translateBtn.setIcon(QIcon.fromTheme("document-export"))
  translateBtn.setEnabled(false)
  translateBtn.setToolTip("Convert selected legacy .list file into modern deb822 format")
  toolLayout.addWidget(translateBtn)

  mainLayout.addLayout(toolLayout)

  # Splitter between Tree and Editor
  var splitter = QSplitter.create()
  splitter.owned = false
  splitter.setOrientation(2) # Qt::Vertical = 2

  # Tree
  var tree = QTreeWidget.create()
  tree.owned = false
  tree.setColumnCount(6)
  tree.setHeaderLabels(@["Enabled", "Format", "Suite", "Components", "URI", "Origin File"])
  splitter.addWidget(tree)

  # Editor Panel
  var editGroup = QGroupBox.create("Repository Details")
  editGroup.owned = false
  var formLayout = QFormLayout.create(editGroup)
  formLayout.owned = false

  var typeLayout = QHBoxLayout.create()
  typeLayout.owned = false
  var debCheck = QCheckBox.create("deb (binaries)")
  debCheck.owned = false
  var debSrcCheck = QCheckBox.create("deb-src (source code)")
  debSrcCheck.owned = false
  typeLayout.addWidget(debCheck)
  typeLayout.addWidget(debSrcCheck)
  formLayout.addRow("Package Types:", typeLayout)

  var uriEdit = QLineEdit.create()
  uriEdit.owned = false
  formLayout.addRow("Repository URI:", uriEdit)

  var suiteEdit = QLineEdit.create()
  suiteEdit.owned = false
  formLayout.addRow("Suite / Codename:", suiteEdit)

  var compEdit = QLineEdit.create()
  compEdit.owned = false
  formLayout.addRow("Components:", compEdit)

  var signedByEdit = QLineEdit.create()
  signedByEdit.owned = false
  formLayout.addRow("Signed-By Keyring:", signedByEdit)

  var btnLayout = QHBoxLayout.create()
  btnLayout.owned = false
  var saveEntryBtn = QPushButton.create("Save Repository Changes")
  saveEntryBtn.owned = false
  saveEntryBtn.setIcon(QIcon.fromTheme("document-save"))
  saveEntryBtn.setEnabled(false)
  btnLayout.addWidget(saveEntryBtn)
  formLayout.addRow("", btnLayout)

  splitter.addWidget(editGroup)
  mainLayout.addWidget(splitter, 1)

  result = SourcesView(
    widget: w,
    state: state,
    tree: tree,
    searchEdit: searchEdit,
    filterCombo: filterCombo,
    translateBtn: translateBtn,
    editGroup: editGroup,
    uriEdit: uriEdit,
    suiteEdit: suiteEdit,
    compEdit: compEdit,
    signedByEdit: signedByEdit,
    debCheck: debCheck,
    debSrcCheck: debSrcCheck,
    saveEntryBtn: saveEntryBtn,
    itemMap: initTable[int, tuple[fileIdx: int, entryIdx: int]](),
    selectedFileIdx: -1,
    selectedEntryIdx: -1,
    inPopulate: false
  )

  let sv = result

  # Wire search & filter
  sv.searchEdit.onTextChanged(proc(t: openArray[char]) {.raises: [].} =
    try: sv.populate() except Exception: discard
  )
  sv.filterCombo.onCurrentIndexChanged(proc(idx: cint) {.raises: [].} =
    try: sv.populate() except Exception: discard
  )

  # Wire tree selection
  sv.tree.onCurrentItemChanged(proc(curr: QTreeWidgetItem, prev: QTreeWidgetItem) {.raises: [].} =
    try:
      if sv.inPopulate: return
      let key = cast[int](curr.h)
      if key in sv.itemMap:
        let (fIdx, eIdx) = sv.itemMap[key]
        sv.selectedFileIdx = fIdx
        sv.selectedEntryIdx = eIdx
        if fIdx >= 0 and fIdx < sv.state.sources.len:
          let f = sv.state.sources[fIdx]
          sv.translateBtn.setEnabled(f.format == sfOneLine)
          let entries = f.entries
          if eIdx >= 0 and eIdx < entries.len:
            sv.updateEditor(true, entries[eIdx])
            return
      sv.selectedFileIdx = -1
      sv.selectedEntryIdx = -1
      sv.translateBtn.setEnabled(false)
      sv.updateEditor(false, SourceEntry())
    except Exception: discard
  )

  # Wire checkbox toggle
  sv.tree.onItemChanged(proc(item: QTreeWidgetItem, col: cint) {.raises: [].} =
    try:
      if sv.inPopulate: return
      if col != 0: return
      let key = cast[int](item.h)
      if key in sv.itemMap:
        let (fIdx, eIdx) = sv.itemMap[key]
        let checked = item.checkState(0) == 2
        if fIdx >= 0 and fIdx < sv.state.sources.len:
          let entries = sv.state.sources[fIdx].entries
          if eIdx >= 0 and eIdx < entries.len:
            if entries[eIdx].enabled != checked:
              sv.state.toggleEntry(fIdx, eIdx)
    except Exception: discard
  )

  # Wire translate
  sv.translateBtn.onClicked(proc() {.raises: [].} =
    try:
      if sv.selectedFileIdx >= 0:
        let ok = sv.state.convertFileToDeb822(sv.selectedFileIdx)
        if ok:
          discard QMessageBox.information(sv.widget, "Converted to deb822",
            "The one-line source file has been translated to deb822 format.\nReview the diff below and click 'Apply Changes' to write.")
    except Exception: discard
  )

  # Wire save entry
  sv.saveEntryBtn.onClicked(proc() {.raises: [].} =
    try:
      if sv.selectedFileIdx >= 0 and sv.selectedEntryIdx >= 0:
        let f = sv.state.sources[sv.selectedFileIdx]
        let entries = f.entries
        if sv.selectedEntryIdx < entries.len:
          var e = entries[sv.selectedEntryIdx]
          var types: seq[string] = @[]
          if sv.debCheck.isChecked(): types.add "deb"
          if sv.debSrcCheck.isChecked(): types.add "deb-src"
          e.types = types
          e.uris = sv.uriEdit.text().strip.splitWhitespace
          e.suites = sv.suiteEdit.text().strip.splitWhitespace
          e.components = sv.compEdit.text().strip.splitWhitespace
          e.signedBy = sv.signedByEdit.text().strip
          sv.state.updateEntry(sv.selectedFileIdx, sv.selectedEntryIdx, e)
          discard QMessageBox.information(sv.widget, "Updated", "Repository entry updated in memory.")
    except Exception: discard
  )

  sv.populate()

proc updateEditor(self: SourcesView, hasSelection: bool, entry: SourceEntry) =
  self.saveEntryBtn.setEnabled(hasSelection)
  self.uriEdit.setEnabled(hasSelection)
  self.suiteEdit.setEnabled(hasSelection)
  self.compEdit.setEnabled(hasSelection)
  self.signedByEdit.setEnabled(hasSelection)
  self.debCheck.setEnabled(hasSelection)
  self.debSrcCheck.setEnabled(hasSelection)

  if hasSelection:
    self.uriEdit.setText(entry.uris.join(" "))
    self.suiteEdit.setText(entry.suites.join(" "))
    self.compEdit.setText(entry.components.join(" "))
    self.signedByEdit.setText(entry.signedBy)
    self.debCheck.setChecked("deb" in entry.types)
    self.debSrcCheck.setChecked("deb-src" in entry.types)
  else:
    self.uriEdit.setText("")
    self.suiteEdit.setText("")
    self.compEdit.setText("")
    self.signedByEdit.setText("")
    self.debCheck.setChecked(false)
    self.debSrcCheck.setChecked(false)

proc populate*(self: SourcesView) =
  self.inPopulate = true
  self.tree.clear()
  self.itemMap.clear()

  let search = self.searchEdit.text().toLowerAscii()
  let filterIdx = self.filterCombo.currentIndex()

  for fIdx, f in self.state.sources:
    if f.path in self.state.deletedFiles: continue
    let entries = f.entries
    for eIdx, e in entries:
      # Apply search
      let matchSearch = search.len == 0 or
        e.label.toLowerAscii.contains(search) or
        e.components.join(" ").toLowerAscii.contains(search) or
        f.path.toLowerAscii.contains(search)
      if not matchSearch: continue

      # Apply filter
      var matchFilter = true
      case filterIdx
      of 1: matchFilter = e.enabled
      of 2: matchFilter = not e.enabled
      of 3: matchFilter = f.format == sfOneLine
      of 4: matchFilter = f.format == sfDeb822
      else: discard
      if not matchFilter: continue

      var item = QTreeWidgetItem.create(self.tree)
      item.owned = false
      item.setText(0, if e.enabled: "Yes" else: "No")
      item.setCheckState(0, if e.enabled: 2 else: 0)
      item.setText(1, $e.format)
      item.setText(2, e.suites.join(" "))
      item.setText(3, e.components.join(" "))
      item.setText(4, e.uris.join(" "))
      item.setText(5, f.path.extractFilename)

      let key = cast[int](item.h)
      self.itemMap[key] = (fIdx, eIdx)

  self.inPopulate = false
