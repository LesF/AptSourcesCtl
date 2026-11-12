## AptSourcesCtl - Qt 6 / seaqt Control Panel for APT Software Sources.

import std/[os, parseopt]
import seaqt/[qapplication, qguiapplication, qmainwindow, qwidget, qicon, qpixmap]
import ./gui/appstate
import ./gui/mainwindow

const AppIconSvg = staticRead("../data/icons/hicolor/scalable/apps/aptsourcesctl.svg")

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
  # Match the installed .desktop file (Wayland app_id / taskbar grouping).
  QGuiApplication.setDesktopFileName("io.github.lesf.AptSourcesCtl")
  # Prefer the themed icon; fall back to the SVG embedded at compile time.
  let fallbackPix = QPixmap.create()
  discard fallbackPix.loadFromData(AppIconSvg.toOpenArrayByte(0, AppIconSvg.high), "SVG")
  QGuiApplication.setWindowIcon(
    QIcon.fromTheme("aptsourcesctl", QIcon.create(fallbackPix)))
  let state = newAppState(rootDir)
  let mw = createMainWindow(state)
  mw.win.show()

  quit(QApplication.exec())

when isMainModule:
  main()
