import std/[unittest, os, strutils]
import ../src/core/[paths, model, onelinesources, sources, deb822]

const root = currentSourcePath().parentDir / "fixtures/root"

suite "one-line sources":
  let p = initAptPaths(root)

  test "round-trip":
    let s = readFile(p.sourcesList)
    check parseOneLine(s).render == s

  test "entries, disabled entries, options, flat repos":
    let f = loadSourceFile(p.sourcesList)
    let es = f.entries
    check es.len == 6
    check es[0].types == @["deb"] and es[0].suites == @["bookworm"]
    check es[1].types == @["deb-src"]
    check not es[2].enabled and es[2].suites == @["bookworm-backports"]
    check es[3].architectures == @["amd64", "i386"]
    check es[3].signedBy == "/etc/apt/keyrings/missing.gpg"
    check es[3].suites == @["./"] and es[3].components.len == 0
    check es[4].options == @[("Trusted", "yes")]

  test "plain comments are not entries":
    check parseLine("# This is just a comment, not an entry").kind == olOther
    check parseLine("#deb").kind == olOther
    check parseLine("deb http://x trixie").kind == olOther  # suite without comps

  test "cdrom URI with spaces in brackets":
    let l = parseLine("# deb cdrom:[Debian GNU/Linux 13 _Trixie_ - amd64 NETINST 20250804-05:57]/ trixie contrib main")
    check l.kind == olEntry and not l.enabled
    check l.uri == "cdrom:[Debian GNU/Linux 13 _Trixie_ - amd64 NETINST 20250804-05:57]/"
    check l.suite == "trixie" and l.components == @["contrib", "main"]

  test "edit regenerates only that line":
    var f = loadSourceFile(p.sourcesList)
    var e = f.entries[0]
    e.enabled = false
    f.applyEntry(e)
    let lines = f.render.splitLines
    check lines[2] == "# deb http://deb.debian.org/debian bookworm main contrib"
    check f.render.replace("# deb http://deb.debian.org/debian bookworm main contrib\n",
                           "deb http://deb.debian.org/debian bookworm main contrib\n") == f.raw

  test "unchanged applyEntry is a no-op":
    var f = loadSourceFile(p.sourcesList)
    for e in f.entries: f.applyEntry(e)
    check not f.isModified

  test "option name mapping":
    check toDeb822Name("arch") == "Architectures"
    check toDeb822Name("arch+") == "Architectures-Add"
    check toOneLineName("Signed-By") == "signed-by"
    check toOneLineName("Architectures-Remove") == "arch-"

suite "deb822 sources":
  let p = initAptPaths(root)

  test "discovery order":
    let fs = listSourceFiles(p)
    check fs.len == 3
    check fs[0].endsWith("sources.list")
    check fs[1].endsWith("debian.sources")
    check fs[2].endsWith("messy.sources")

  test "entries":
    let es = loadSourceFile(p.sourcesListD / "messy.sources").entries
    check es.len == 2
    check es[0].enabled and es[0].options == @[("X-Custom", "keep me")]
    check not es[1].enabled and es[1].hasInlineKey

  test "applyEntry toggles Enabled minimally":
    var f = loadSourceFile(p.sourcesListD / "messy.sources")
    var e = f.entries[1]
    e.enabled = true
    f.applyEntry(e)
    check f.render == f.raw.replace("Enabled: no\n", "")
    e.enabled = false
    f.applyEntry(e)
    check "Enabled: no" in f.render

  test "unchanged applyEntry is a no-op":
    var f = loadSourceFile(p.sourcesListD / "messy.sources")
    for e in f.entries: f.applyEntry(e)
    check not f.isModified

  test "convert one-line to deb822":
    let outp = convertToDeb822(loadSourceFile(p.sourcesList))
    let d = parseDeb822(outp)
    check d.render == outp
    let conv = parseSourceContent("/x.sources", outp).entries
    check conv.len == 5                       # deb + deb-src merged
    check conv[0].types == @["deb", "deb-src"]
    check not conv[1].enabled
    check conv[2].architectures == @["amd64", "i386"]
    check "# Legacy sources.list" in outp
    check "# old backports" in outp
