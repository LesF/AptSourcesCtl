import std/[unittest, os, strutils, options]
import ../src/core/deb822

const fx = currentSourcePath().parentDir / "fixtures/root/etc/apt"

suite "deb822":
  test "round-trip fixtures byte-for-byte":
    for f in [fx / "sources.list.d/debian.sources", fx / "sources.list.d/messy.sources",
              fx / "preferences.d/pins"]:
      let s = readFile(f)
      check parseDeb822(s).render == s

  test "round-trip edge cases":
    for s in ["", "\n", "\n\n", "A: b", "A: b\n", "# only comment\n", "A: b\n\n\n# x\n\nB: c\n",
              "A:\n b\n .\n c\n"]:
      check parseDeb822(s).render == s

  test "stanzas and comment-only paragraphs":
    let d = parseDeb822(readFile(fx / "sources.list.d/messy.sources"))
    check d.stanzaCount == 2
    let s0 = d.stanza(0)
    check s0.getField("Types") == some("deb")          # case-insensitive lookup
    check s0.getFieldOr("uris") == "https://download.docker.com/linux/debian"
    check s0.getFieldOr("X-Custom") == "keep me"

  test "multiline values":
    let d = parseDeb822(readFile(fx / "sources.list.d/messy.sources"))
    let key = d.stanza(1).getFieldOr("Signed-By")
    check key.startsWith("-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nmQENB")
    check key.endsWith("-----END PGP PUBLIC KEY BLOCK-----")

  test "minimal edit touches one line only":
    let src = readFile(fx / "sources.list.d/messy.sources")
    var d = parseDeb822(src)
    d.stanzaMut(0).setField("Suites", "forky")
    let outp = d.render
    check outp == src.replace("Suites: trixie\nComponents: stable", "Suites: forky\nComponents: stable")

  test "setField with unchanged value keeps odd spacing":
    let src = readFile(fx / "sources.list.d/messy.sources")
    var d = parseDeb822(src)
    d.stanzaMut(0).setField("URIs", "https://download.docker.com/linux/debian")
    check d.render == src

  test "add field keeps original casing elsewhere, append before trailing comments":
    var d = parseDeb822("Types: deb\n# tail\n")
    d.stanzaMut(0).setField("Suites", "trixie")
    check d.render == "Types: deb\nSuites: trixie\n# tail\n"

  test "remove field and stanza":
    var d = parseDeb822("A: 1\n\nB: 2\n\nC: 3\n")
    d.stanzaMut(1).removeField("B")
    d.stanzaMut(1).setField("B", "x")
    check d.render == "A: 1\n\nB: x\n\nC: 3\n"
    d.removeStanza(1)
    check d.render == "A: 1\n\nC: 3\n"
    d.removeStanza(1)
    check d.render == "A: 1\n"

  test "add stanza":
    var d = parseDeb822("A: 1")
    d.addStanza(newStanza([("B", "2"), ("C", "x\n\ny")]))
    check d.render == "A: 1\n\nB: 2\nC: x\n .\n y\n"

  test "errors carry line numbers":
    expect Deb822Error:
      discard parseDeb822("A: 1\nnot a field\n")
    try:
      discard parseDeb822("A: 1\n\n continuation\n")
    except Deb822Error as e:
      check e.line == 3
