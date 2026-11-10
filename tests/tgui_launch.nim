import std/[unittest, os]
import seaqt/[qapplication, qcoreapplication, qlistwidget, qstackedwidget]
import ../src/gui/[appstate, mainwindow]

suite "gui smoke test":
  test "instantiate mainwindow with fixtures in offscreen mode":
    putEnv("QT_QPA_PLATFORM", "offscreen")
    let app = QApplication.create()

    let state = newAppState("tests/fixtures/root")
    check state.sources.len > 0
    check state.keyrings.len > 0

    let mw = createMainWindow(state)
    check mw.win.h != nil
    check mw.sidebar.h != nil
    check mw.stack.h != nil

    # Test switching views
    mw.sidebar.setCurrentRow(1)
    QCoreApplication.processEvents()
    check mw.stack.currentIndex() == 1

    mw.sidebar.setCurrentRow(2)
    QCoreApplication.processEvents()
    check mw.stack.currentIndex() == 2

    mw.sidebar.setCurrentRow(3)
    QCoreApplication.processEvents()
    check mw.stack.currentIndex() == 3

    mw.sidebar.setCurrentRow(0)
    QCoreApplication.processEvents()
    check mw.stack.currentIndex() == 0

    # Test population
    check mw.sourcesView.tree.h != nil
    check mw.keyringsView.table.h != nil
    check mw.pinningView.table.h != nil
    check mw.diagView.table.h != nil

    echo "GUI components created and smoke tested successfully"
