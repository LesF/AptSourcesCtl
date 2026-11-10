## AptSourcesCtl - Qt 6 / seaqt Control Panel for APT Software Sources.

import std/[os, parseopt]
import seaqt/[qapplication, qmainwindow, qwidget]
import ./gui/appstate
import ./gui/mainwindow

proc main() =
  var rootDir = getEnv("APTSOURCESCTL_ROOT", "")

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if p.key in ["r", "root"]:
        rootDir = p.val
      elif p.key in ["h", "help"]:
        echo "Usage: aptsourcesctl [--root=<dir>]"
        quit(0)
    of cmdArgument:
      if rootDir.len == 0:
        rootDir = p.key

  let app = QApplication.create()
  let state = newAppState(rootDir)
  let mw = createMainWindow(state)
  mw.win.show()

  quit(QApplication.exec())

when isMainModule:
  main()
