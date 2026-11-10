## Bottom action bar for system configuration settings (Revert, Diff, Apply).

import seaqt/[qwidget, qhboxlayout, qlabel, qpushbutton, qicon]
import ../appstate

type
  ActionFooter* = ref object
    widget*: QWidget
    statusLabel*: QLabel
    revertBtn*: QPushButton
    diffBtn*: QPushButton
    applyBtn*: QPushButton
    reloadBtn*: QPushButton
    state*: AppState

proc updateState*(self: ActionFooter) =
  let dirty = self.state.isDirty()
  let count = self.state.dirtyCount()

  self.revertBtn.setEnabled(dirty)
  self.diffBtn.setEnabled(dirty)
  self.applyBtn.setEnabled(dirty)

  if dirty:
    self.statusLabel.setText($count & " pending modification" & (if count == 1: "" else: "s") & " (unsaved)")
  else:
    self.statusLabel.setText("All software sources up to date.")

proc createActionFooter*(parent: QWidget, state: AppState): ActionFooter =
  var w = QWidget.create(parent)
  w.owned = false
  var layout = QHBoxLayout.create(w)
  layout.owned = false

  var statusLbl = QLabel.create("Ready")
  statusLbl.owned = false
  layout.addWidget(statusLbl, 1)

  var reloadBtn = QPushButton.create("Reload")
  reloadBtn.owned = false
  reloadBtn.setIcon(QIcon.fromTheme("view-refresh"))
  layout.addWidget(reloadBtn)

  var revertBtn = QPushButton.create("Revert")
  revertBtn.owned = false
  revertBtn.setIcon(QIcon.fromTheme("edit-undo"))
  revertBtn.setEnabled(false)
  layout.addWidget(revertBtn)

  var diffBtn = QPushButton.create("Review Diff...")
  diffBtn.owned = false
  diffBtn.setIcon(QIcon.fromTheme("text-x-generic"))
  diffBtn.setEnabled(false)
  layout.addWidget(diffBtn)

  var applyBtn = QPushButton.create("Apply Changes")
  applyBtn.owned = false
  applyBtn.setIcon(QIcon.fromTheme("dialog-ok-apply"))
  applyBtn.setEnabled(false)
  layout.addWidget(applyBtn)

  result = ActionFooter(
    widget: w,
    statusLabel: statusLbl,
    revertBtn: revertBtn,
    diffBtn: diffBtn,
    applyBtn: applyBtn,
    reloadBtn: reloadBtn,
    state: state
  )

  result.updateState()

