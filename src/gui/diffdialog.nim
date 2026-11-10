## Unified diff dialog for previewing pending changes before committing.

import seaqt/[qdialog, qwidget, qvboxlayout, qhboxlayout, qcombobox, qplaintextedit, qpushbutton, qlabel]
import ./appstate

type
  DiffDialog* = ref object
    combo*: QComboBox
    diffEdit*: QPlainTextEdit
    diffs*: seq[tuple[path: string, status: string, diff: string]]

proc updateDisplay(self: DiffDialog) =
  let idx = self.combo.currentIndex()
  if idx >= 0 and idx < self.diffs.len:
    self.diffEdit.setPlainText(self.diffs[idx].diff)
  else:
    self.diffEdit.setPlainText("No pending changes.")

proc showDiffDialog*(parent: QWidget, state: AppState) =
  let diffs = state.getDiffs()
  var dlg = QDialog.create(parent)
  let dlgH = dlg.h
  dlg.setWindowTitle("Review Pending Changes")
  dlg.resize(750, 500)

  var layout = QVBoxLayout.create(dlg)
  layout.owned = false

  var topLayout = QHBoxLayout.create()
  topLayout.owned = false
  var lbl = QLabel.create("Modified File:")
  lbl.owned = false
  topLayout.addWidget(lbl)

  var combo = QComboBox.create()
  combo.owned = false
  for item in diffs:
    combo.addItem(item.path & " (" & item.status & ")")
  topLayout.addWidget(combo)
  layout.addLayout(topLayout)

  var edit = QPlainTextEdit.create()
  edit.owned = false
  edit.setReadOnly(true)
  layout.addWidget(edit)

  var dd = DiffDialog(
    combo: combo,
    diffEdit: edit,
    diffs: diffs
  )

  dd.combo.onCurrentIndexChanged(proc(idx: cint) {.raises: [].} =
    try: dd.updateDisplay() except Exception: discard
  )
  dd.updateDisplay()

  var bottomLayout = QHBoxLayout.create()
  bottomLayout.owned = false
  var closeBtn = QPushButton.create("Close")
  closeBtn.owned = false
  closeBtn.onClicked(proc() {.raises: [].} =
    try:
      var d = QDialog(h: dlgH, owned: false)
      discard d.close()
    except Exception: discard
  )
  bottomLayout.addWidget(closeBtn)
  layout.addLayout(bottomLayout)

  discard dlg.exec()
