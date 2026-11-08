import std/[unittest, os, strutils]
import ../src/core

const root = currentSourcePath().parentDir / "fixtures/root"

suite "keyrings":
  let p = initAptPaths(root)

  test "parse gpg colon output":
    let o = "pub:u:255:22:ABCD:1700000000:1900000000::u:::scESC:\n" &
            "fpr:::::::::0123456789ABCDEF:\nuid:u::::1700000000::H::Me <me@x>::::::\n" &
            "sub:u:255:18:EF01:1700000000::::::e:\nfpr:::::::::SUBKEYFPR:\n"
    let ks = parseGpgColons(o)
    check ks.len == 1
    check ks[0].fingerprint == "0123456789ABCDEF"
    check ks[0].uid == "Me <me@x>"
    check ks[0].expires == 1900000000

  test "scan and cross-reference":
    var ks = scanKeyrings(p)
    var all: seq[SourceEntry]
    for f in loadAllSources(p): all.add f.entries
    ks.crossReference(all, p)
    var docker, orphan, debian: KeyringFile
    for k in ks:
      case k.path.extractFilename
      of "docker.asc": docker = k
      of "orphan.gpg": orphan = k
      of "debian-archive-keyring.gpg": debian = k
    check docker.armored and docker.keys.len == 1
    check docker.keys[0].uid == "Test Repo <test@example.invalid>"
    check docker.usedBy.len == 1 and not docker.isOrphan
    check orphan.isOrphan and not orphan.armored
    check debian.keys.len >= 3 and debian.usedBy.len == 2

suite "pinning":
  let p = initAptPaths(root)

  test "load rules":
    let fs = loadAllPrefs(p)
    check fs.len == 1
    check fs[0].render == fs[0].raw
    let rs = fs[0].rules
    check rs.len == 3
    check rs[1].package == "firefox-esr" and rs[1].priority == 990
    check rs[2].priority == -1 and priorityMeaning(-1) == "never install"
    for r in rs: check validateRule(r).len == 0

  test "edit rule":
    var f = loadAllPrefs(p)[0]
    var r = f.rules[0]
    r.priority = 500
    f.applyRule(r)
    check f.render == f.raw.replace("Pin-Priority: 900", "Pin-Priority: 500")

suite "validate":
  let p = initAptPaths(root)

  test "issues across fixture tree":
    var all: seq[SourceEntry]
    for f in loadAllSources(p): all.add f.entries
    let issues = validateAll(all, p, p.releaseCodename)
    check p.releaseCodename == "trixie"
    var msgs: seq[string]
    for i in issues: msgs.add $i.severity & ": " & i.message
    let joined = msgs.join("\n")
    check "error: Signed-By keyring not found: /etc/apt/keyrings/missing.gpg" in joined
    check "warning: suite 'bookworm' is older than this system (trixie)" in joined
    check "duplicates entry" in joined          # trixie main in sources.list and debian.sources
    check "no Signed-By" in joined
    check "keyring not found: /etc/apt/keyrings/docker.asc" notin joined
