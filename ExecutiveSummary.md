# Executive Summary & Project Review

Stage 1 established the data foundation and manipulation engine in `src/core`. All existing tests in `tests/` pass with zero regressions.

```
 deb822:             10/10 tests passing (lossless AST, byte-for-byte round-trips, minimal edits)
 keyrings & pins:     5/5 tests passing (gpg colon parser, cross-referencing, pinning semantics)
 sources & translate: 12/12 tests passing (discovery, one-line parsing, deb822 conversion)
```

## Key Capabilities Available to the UI

1. **Lossless File Handling & Surgical Edits**:
   - `deb822.nim` & `onelinesources.nim`: Edits touch only the affected lines/fields without stripping comments, reordering stanzas, or losing custom spacing.
2. **One-Line to deb822 Translation**:
   - `sources.nim:convertToDeb822`: Converts legacy `.list` files into modern `.sources` stanzas, automatically coalescing adjacent `deb` and `deb-src` lines into `Types: deb deb-src` while preserving comments.
3. **Sandboxed Keyring Inspection & Cross-Referencing**:
   - `keyrings.nim`: Runs GPG in an isolated throwaway `GNUPGHOME` to safely parse keys, detect expirations/revocations, and identify orphaned keys (`/etc/apt/keyrings` files not referenced by any source) or legacy global trust keys (`trusted.gpg.d`).
4. **Semantic Pinning**:
   - `pinning.nim`: Translates raw integer priorities into human-friendly explanations (`priorityMeaning`).
5. **Pre-flight Validation & Diagnostics**:
   - `validate.nim`: Checks for duplicate enabled repos across different files, missing keyrings, URI syntax issues, and Debian codename mismatches against `/etc/os-release`.

> [!NOTE]
> **Build Requirement Note**: Compiling `seaqt` against Qt 6 on Debian (Trixie) requires `qt6-base-private-dev` in addition to `qt6-base-dev` because `libseaqt-runtime.cpp` includes `<private/qobject_p.h>`.

---

## UI Concept: System Configuration Panel Style

The UI will follow the aesthetic and interaction paradigms of native desktop control panels (such as KDE System Settings, YaST, or Synaptic/Software Properties), maintaining safety through **staged edits** and **privilege separation**.

```
+--------------------------------------------------------------------------------------------------+
| AptSourcesCtl - APT Software Sources                                                   [-][o][x] |
+------------------------------------+-------------------------------------------------------------+
|  [Filter / Search...             ] | Debian Trixie (Debian 13)                        [+ Add...] |
| ---------------------------------- |-------------------------------------------------------------|
|  [x] Repositories (8)              | [x] deb http://deb.debian.org/debian trixie main contrib   |
|  [ ] Keyrings & Trust (4)          | [x] deb http://deb.debian.org/debian trixie-security ...    |
|  [ ] Package Pinning (2)           | [!] docker.list (Legacy 1-line)        [Translate to deb822]|
|  [!] Diagnostics (1 Warning)       | ----------------------------------------------------------- |
|                                    | Repository Details / Editor:                                |
|                                    |   File: /etc/apt/sources.list.d/debian.sources              |
|                                    |   Suites: trixie, trixie-updates                            |
|                                    |   Components: [x] main  [x] contrib  [x] non-free-firmware   |
|                                    |   Keyring: /usr/share/keyrings/debian-archive-keyring.pgp   |
+------------------------------------+-------------------------------------------------------------+
| [!] 2 unsaved changes              | [Revert]   [View Diff...]               [Apply Changes (Root)] |
+--------------------------------------------------------------------------------------------------+
```

---

## Feature Breakdown for the New UI

### 1. Main Shell & Navigation (`src/gui/mainwindow.nim`)
- **Navigation Sidebar**: Left sidebar using a `QListWidget` with standard icon badges (`preferences-system`, `security-high`, `dialog-warning`, etc.) to switch between the 4 main modules:
  1. **Repositories** (`SourcesView`)
  2. **Keyrings & Trust** (`KeyringsView`)
  3. **Package Pinning** (`PinningView`)
  4. **System Diagnostics** (`DiagnosticsView`)
- **Action / Status Footer**:
  - Displays session state: *"All changes saved"* or *"2 unsaved modifications"*.
  - **Revert**: Resets pending edits back to disk state.
  - **Review Diff**: Opens a dialog showing unified diffs of all affected files before committing.
  - **Apply Changes**: Elevates privileges using Polkit (`pkexec aptsourcesctl_helper`) to atomically commit files.
  - **Check for Updates**: Quick button to run `apt update` after committing changes.

---

### 2. Repositories View (`src/gui/sourcesview.nim`)
- **Repository List / Tree (`QTreeWidget`)**:
  - Grouped either by origin file (e.g., `debian.sources`, `docker.sources`, `google-chrome.list`) or flat list sorted by status.
  - Columns:
    - **Enabled**: Instant toggle checkbox (sets `Enabled: no` in deb822 or comments out one-line entries).
    - **Format Badge**: `deb822` (green pill/badge) vs `legacy` (amber pill/badge).
    - **Repository Label**: URI + Suite + Components.
    - **Status / Warning Icon**: Tooltip with validation warnings (e.g., duplicate repo, missing keyring).
- **Format Translation Action ("Translate to deb822")**:
  - For any selected `.list` file, a prominent button transforms it into `.sources` format using `convertToDeb822`.
  - Preview dialog shows the exact converted stanza before saving, deleting the old `.list` file and creating the `.sources` file atomically upon Apply.
- **Repository Inspector & Editor (`QFormLayout` / Drawer)**:
  - **Types**: Checkboxes for Binary (`deb`) and Source code (`deb-src`).
  - **URIs**: Primary mirror URL with validation.
  - **Suites**: Comma-separated or tag view (e.g. `trixie`, `trixie-updates`, `trixie-security`).
  - **Components**: Quick checkboxes for Debian standards (`main`, `contrib`, `non-free`, `non-free-firmware`) plus custom input.
  - **Signed-By / Keyring Selector**: Dropdown showing detected keyrings from `/usr/share/keyrings` and `/etc/apt/keyrings`, with an option to select a custom file or inspect inline armored keys.
  - **Architectures**: Multi-selection for target architectures (`amd64`, `i386`, `arm64`, etc.).
- **Add Repository Wizard / Dialog**:
  - **Quick Paste**: Paste a standard `deb ...` line or deb822 stanza, automatically parsed into structured fields.
  - **Debian Preset Template**: Quickly enable standard Debian official suites (Security, Updates, Backports, Proposed-Updates) with a single click.

---

### 3. Keyrings & Trust Manager (`src/gui/keyringsview.nim`)
- **Keyring Overview (`QTableWidget`)**:
  - Displays all detected keys across `/etc/apt/keyrings`, `/usr/share/keyrings`, and deprecated `/etc/apt/trusted.gpg.d`.
  - Status Indicators:
    - **Valid** (Normal trust).
    - **Orphaned** (Warning: Key file exists in `/etc/apt/keyrings` but no repository references it).
    - **Global Trust Warning** (Caution: Key is located in `trusted.gpg.d` or `trusted.gpg`, meaning it authenticates *any* repository on the system rather than being pinned to one source).
    - **Expired / Revoked** (Error state).
- **Key Details Card**:
  - Fingerprint / Key ID with a one-click copy button.
  - User ID / Packager description.
  - Algorithm, key size (e.g. RSA 4096, Ed25519), creation date, and expiration date.
  - **"Used by" Cross-Reference**: Clear list of all repository files and suites that specify this key in their `Signed-By` field.
- **Keyring Actions**:
  - **Import Key**: Download key from HTTPS URL or import from local `.asc` / `.gpg` file directly into `/etc/apt/keyrings/`.
  - **Remove Orphan**: Safe deletion for unused keys.

---

### 4. Package Pinning / Preferences (`src/gui/pinningview.nim`)
- **Rules Table**:
  - Columns: Package pattern, Pin target (e.g. `release a=trixie-backports`, `origin deb.debian.org`), Priority, and Human Explanation.
  - Human explanation column directly utilizes `priorityMeaning(priority)`:
    - Priority `< 0`: *"Never install"*
    - Priority `100..499`: *"Install only if no other version available"*
    - Priority `500..989`: *"Standard repository default"*
    - Priority `990..999`: *"Preferred over installed / target release"*
    - Priority `>= 1000`: *"Force downgrade to pinned version"*
- **Add/Edit Rule Dialog**:
  - Package autocomplete/input.
  - Pin target selector with fields for `release` (archive, codename, component), `origin`, or `version`.
  - Priority spinbox + slider with live explanation preview.
  - Explanation comment field.

---

### 5. Diagnostics & Health View (`src/gui/diagnosticsview.nim`)
- Aggregated dashboard powered by `validateAll()`:
  - **Duplicate Repositories**: Highlights exact duplicated `(type, uri, suite, component)` entries across disparate files.
  - **Missing Signing Keys**: Warns about sources whose `Signed-By` references nonexistent paths.
  - **Release Mismatch**: Flags suites that belong to older releases (e.g., `bookworm` on a `trixie` system) or unpinned newer releases.
  - **Actionable "Fix" Buttons**: Inline shortcut buttons (e.g. *"Disable Duplicate"*, *"Select Keyring"*, *"Migrate to deb822"*).

---

### 6. Safety, Diff Viewer, & Privileged Helper (`src/helper/`)
- **Session & In-Memory Staging**:
  - The UI operates strictly in user-space using in-memory `SourceFile` and `PrefFile` models.
  - Any toggle, edit, or translation creates a dirty state without touching `/etc/apt`.
- **Unified Diff Viewer (`DiffViewerDialog`)**:
  - Before applying changes, shows a syntax-highlighted diff (`f.raw` vs `f.render`).
- **Privileged Helper (`src/helper/aptsourcesctl_helper.nim`)**:
  - Called via `pkexec aptsourcesctl_helper` passing the staged payload.
  - Helper verifies path safety (strictly restricted to `/etc/apt/` subpaths), runs `validateAll`, and performs atomic writes (write to temporary file + rename) with correct file ownership (`root:root`) and permissions (`0644`).

---

## Proposed Project Directory Layout

```
src/
├── aptsourcesctl.nim          # Main GUI executable entry point
├── aptsourcesctl_helper.nim   # Privileged Polkit helper
├── core.nim                   # Core facade export
├── core/                      # [COMPLETED] Core parsers & validators
│   ├── deb822.nim
│   ├── keyrings.nim
│   ├── model.nim
│   ├── onelinesources.nim
│   ├── paths.nim
│   ├── pinning.nim
│   ├── sources.nim
│   └── validate.nim
└── gui/                       # [STAGE 2] Qt 6 seaqt UI components
    ├── appstate.nim           # In-memory document manager & dirty tracking
    ├── diffdialog.nim         # Unified diff review dialog
    ├── diagnosticsview.nim    # Validation & issue reporting view
    ├── keyringsview.nim       # Keyring management & cross-reference view
    ├── mainwindow.nim         # System settings window frame & sidebar navigation
    ├── pinningview.nim        # Preferences & priority rules view
    ├── sourcesview.nim        # Repositories list & deb822 translator
    └── widgets/
        ├── repoeditor.nim     # Repository inspector/editor drawer
        └── statusbar.nim      # Bottom action bar (Revert, Diff, Polkit Apply)
```

# Testing
## Build binaries
nimble build

## Run against mock fixture root
./aptsourcesctl --root=tests/fixtures/root

## Run against system APT configuration
./aptsourcesctl

