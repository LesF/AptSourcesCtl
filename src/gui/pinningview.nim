## Package pinning and APT preferences view.

import std/[strutils, os, tables]
import seaqt/[qwidget, qvboxlayout, qhboxlayout, qsplitter, qtablewidget,
              qlineedit, qspinbox, qlabel, qgroupbox, qformlayout, qpushbutton,
              qmessagebox, qicon]
import ../core
import ./appstate

type
  PinningView* = ref object
    widget*: QWidget
    state*: AppState
    table*: QTableWidget
    pkgEdit*: QLineEdit
    pinEdit*: QLineEdit
    prioSpin*: QSpinBox
    meaningLabel*: QLabel
    saveBtn*: QPushButton
    ruleMap*: Table[int, tuple[fileIdx: int, ruleIdx: int]]
    selectedFileIdx*: int
    selectedRuleIdx*: int
    inPopulate*: bool

proc populate*(self: PinningView)
proc updateEditor(self: PinningView, r: PinRule)

proc createPinningView*(parent: QWidget, state: AppState): PinningView =
  var w = QWidget.create(parent)
  w.owned = false
  var mainLayout = QVBoxLayout.create(w)
  mainLayout.owned = false

  var infoLbl = QLabel.create("Configure package pinning priorities (/etc/apt/preferences and preferences.d/*):")
  infoLbl.owned = false
  mainLayout.addWidget(infoLbl)

  var splitter = QSplitter.create()
  splitter.owned = false
  splitter.setOrientation(2)

  var table = QTableWidget.create()
  table.owned = false
  table.setColumnCount(5)
  table.setHorizontalHeaderLabels(@["Package", "Pin Expression", "Priority", "Behavior Meaning", "Origin File"])
  splitter.addWidget(table)

  # Editor
  var group = QGroupBox.create("Edit Pin Rule")
  group.owned = false
  var formLayout = QFormLayout.create(group)
  formLayout.owned = false

  var pkgEdit = QLineEdit.create()
  pkgEdit.owned = false
  formLayout.addRow("Package Pattern:", pkgEdit)

  var pinEdit = QLineEdit.create()
  pinEdit.owned = false
  formLayout.addRow("Pin Target (release/origin/version):", pinEdit)

  var prioSpin = QSpinBox.create()
  prioSpin.owned = false
  prioSpin.setRange(-1000, 2000)
  prioSpin.setValue(500)
  formLayout.addRow("Pin-Priority:", prioSpin)

  var meaningLbl = QLabel.create(priorityMeaning(500))
  meaningLbl.owned = false
  formLayout.addRow("Effective Meaning:", meaningLbl)

  var btnLayout = QHBoxLayout.create()
  btnLayout.owned = false
  var saveBtn = QPushButton.create("Save Pin Rule")
  saveBtn.owned = false
  saveBtn.setIcon(QIcon.fromTheme("document-save"))
  saveBtn.setEnabled(false)
  btnLayout.addWidget(saveBtn)
  formLayout.addRow("", btnLayout)

  splitter.addWidget(group)
  mainLayout.addWidget(splitter, 1)

  result = PinningView(
    widget: w,
    state: state,
    table: table,
    pkgEdit: pkgEdit,
    pinEdit: pinEdit,
    prioSpin: prioSpin,
    meaningLabel: meaningLbl,
    saveBtn: saveBtn,
    ruleMap: initTable[int, tuple[fileIdx: int, ruleIdx: int]](),
    selectedFileIdx: -1,
    selectedRuleIdx: -1,
    inPopulate: false
  )

  let pv = result

  pv.prioSpin.onValueChanged(proc(v: cint) {.raises: [].} =
    try: pv.meaningLabel.setText(priorityMeaning(int(v))) except Exception: discard
  )

  pv.table.onItemSelectionChanged(proc() {.raises: [].} =
    try:
      if pv.inPopulate: return
      let r = pv.table.currentRow()
      if r in pv.ruleMap:
        let (fIdx, rIdx) = pv.ruleMap[r]
        pv.selectedFileIdx = fIdx
        pv.selectedRuleIdx = rIdx
        if fIdx >= 0 and fIdx < pv.state.prefs.len:
          let rules = pv.state.prefs[fIdx].rules
          if rIdx >= 0 and rIdx < rules.len:
            pv.updateEditor(rules[rIdx])
            return
      pv.selectedFileIdx = -1
      pv.selectedRuleIdx = -1
      pv.saveBtn.setEnabled(false)
    except Exception: discard
  )

  pv.saveBtn.onClicked(proc() {.raises: [].} =
    try:
      if pv.selectedFileIdx >= 0 and pv.selectedRuleIdx >= 0:
        var r = PinRule(
          file: pv.state.prefs[pv.selectedFileIdx].path,
          index: pv.selectedRuleIdx,
          package: pv.pkgEdit.text().strip,
          pin: pv.pinEdit.text().strip,
          priority: int(pv.prioSpin.value())
        )
        pv.state.prefs[pv.selectedFileIdx].applyRule(r)
        pv.state.recomputeIssues()
        pv.state.notifyChanged()
        discard QMessageBox.information(pv.widget, "Saved", "Pin rule updated in memory.")
    except Exception: discard
  )

  pv.populate()

proc updateEditor(self: PinningView, r: PinRule) =
  self.pkgEdit.setText(r.package)
  self.pinEdit.setText(r.pin)
  self.prioSpin.setValue(cint(r.priority))
  self.meaningLabel.setText(priorityMeaning(r.priority))
  self.saveBtn.setEnabled(true)

proc makeItem(text: string): QTableWidgetItem =
  result = QTableWidgetItem.create(text)
  result.owned = false

proc populate*(self: PinningView) =
  self.inPopulate = true
  self.ruleMap.clear()

  var allRules: seq[tuple[fileIdx: int, ruleIdx: int, rule: PinRule]] = @[]
  for fIdx, f in self.state.prefs:
    for rIdx, r in f.rules:
      allRules.add (fIdx, rIdx, r)

  self.table.setRowCount(cint(allRules.len))
  for i, item in allRules:
    let row = cint(i)
    let r = item.rule
    self.table.setItem(row, 0, makeItem(r.package))
    self.table.setItem(row, 1, makeItem(r.pin))
    self.table.setItem(row, 2, makeItem($r.priority))
    self.table.setItem(row, 3, makeItem(priorityMeaning(r.priority)))
    self.table.setItem(row, 4, makeItem(item.rule.file.extractFilename))
    self.ruleMap[int(row)] = (item.fileIdx, item.ruleIdx)

  self.inPopulate = false
  if allRules.len > 0:
    self.updateEditor(allRules[0].rule)
