# delphi-dccbuild.ps1 

![delphi-dccbuild logo](https://continuous-delphi.github.io/assets/logos/delphi-dccbuild-480x270.png)

![CI](https://github.com/continuous-delphi/delphi-dccbuild/actions/workflows/ci.yml/badge.svg)
![Status](https://img.shields.io/badge/status-incubator-orange)
![License](https://img.shields.io/github/license/continuous-delphi/delphi-dccbuild.svg)
![Delphi](https://img.shields.io/badge/delphi-red)
![PowerShell](https://img.shields.io/badge/powershell-blue)
![Continuous Delphi](https://img.shields.io/badge/org-continuous--delphi-red)

Quick-start, or enhance your Delphi build automation with a standalone,
MIT-licensed, CI-ready build tool from
[Continuous-Delphi](https://github.com/continuous-delphi) -
designed for automating builds using the DCC command-line compiler.
See [delphi-msbuild](https://github.com/continuous-delphi/delphi-msbuild)
for a similar tool that utilizes MSBuild.

# Overview

`delphi-dccbuild.ps1` builds a Delphi project using the standalone DCC
command-line compiler (`dcc32.exe`, `dcc64.exe`...).  It sources the
Delphi build environment from `rsvars.bat` before invoking the compiler.
This ensures that `$(BDS)`, `$(BDSCOMMONDIR)`, and related environment
variables are set, which is required for projects that reference those
variables in their search paths and for cross-platform targets that
rely on SDK paths configured by the installer.

It is designed to be used standalone by providing the `ProjectFile` path
and the Delphi `RootDir` (and optionally the Platform and Config settings.)

```powershell
delphi-dccbuild.ps1 `
  -ProjectFile .\src\MyApp.dpr `
  -RootDir     'C:\Program Files (x86)\Embarcadero\Studio\23.0' `
  -Platform    Win32 `
  -Config      Release 
```

You can also pipe the output from `delphi-inspect.ps1` to automatically
detect the `RootDir`.

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
    delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr
```

## PowerShell Compatibility

Runs on the widely available Windows PowerShell 5.1 (`powershell.exe`)
and the newer PowerShell 7+ (`pwsh`).

Note: the test suite requires `pwsh`.

# Usage

```powershell
  pwsh delphi-dccbuild.ps1 -ProjectFile <path> [options]
```

------------------------------------------------------------------------

# Parameters

## -ProjectFile

```text
-ProjectFile <path>
```

Path to the `.dpr` project file.  **Required.**

The path is resolved to an absolute path before being passed to the compiler.

## -RootDir

```text
-RootDir <path>
```

The Delphi installation root directory
(e.g. `C:\Program Files (x86)\Embarcadero\Studio\23.0`).

`rsvars.bat` is expected at `<RootDir>\bin\rsvars.bat`.  The compiler
executable is derived from this path and the requested platform:

- 32-bit compilers: `<RootDir>\bin\dcc32.exe`, `dccosx.exe`, etc.
- 64-bit compilers: `<RootDir>\bin64\dcc64.exe`, `dccosx64.exe`, etc.

If omitted, `-RootDir` is taken from the `.rootDir` property of a
piped `delphi-inspect` result object.  

Note: An explicit `-RootDir` takes precedence over the piped value.

## -Platform

```text
-Platform <platform>    (default: Win32)
```

The target compilation platform.  Determines which DCC compiler
executable is invoked.

Valid values and their corresponding executables:

| Platform        | Compiler exe    | Bin folder |
|-----------------|-----------------|------------|
| `Win32`         | `dcc32.exe`     | `bin`      |
| `Win64`         | `dcc64.exe`     | `bin64`    |
| `macOS32`       | `dccosx.exe`    | `bin`      |
| `macOS64`       | `dccosx64.exe`  | `bin64`    |
| `macOSARM64`    | `dccosxarm64.exe` | `bin64`  |
| `Linux64`       | `dcclinux64.exe`  | `bin64`  |
| `iOS32`         | `dcciosarm.exe`   | `bin`    |
| `iOSSimulator32`| `dccios32.exe`    | `bin`    |
| `iOS64`         | `dcciosarm64.exe` | `bin64`  |
| `iOSSimulator64`| `dcciossimarm64.exe` | `bin64` |
| `Android32`     | `dccaarm.exe`     | `bin`    |
| `Android64`     | `dccaarm64.exe`   | `bin64`  |

## -Config

```text
-Config <value>    (default: Debug)
```

The build configuration name.  Passed to DCC as a conditional define
(`-D<CONFIG>`), uppercased automatically.

Examples: `Debug` becomes `-DDEBUG`; `Release` becomes `-DRELEASE`.

This define is **added** to any existing defines in the project's `.cfg`
file -- it does not replace them.  The `.cfg` file's existing defines
(such as platform symbols set by RAD Studio) are preserved.

Common values are `Debug` and `Release`.  Any string is accepted; the
uppercased value is used as the define symbol.

## -Target

```text
-Target <value>    (default: Build)
```

The compilation mode.

Valid values:

- `Build` -- compile only changed units (default DCC behavior)
- `Rebuild` -- force recompilation of all units (`-B` flag)

Note: `Clean` and `Rebuild` are not available for DCC builds.  To clean DCC output,
delete the DCU output directory manually before invoking a `Rebuild`.

## -Verbosity

```text
-Verbosity <value>    (default: normal)
```

Controls DCC hint and warning output.

Valid values:

- `normal` -- standard DCC output (hints, warnings, and progress)
- `quiet` -- suppress hints and warnings (`-Q` flag); only errors
  and the final summary line are emitted

## -ExeOutputDir

```text
-ExeOutputDir <path>
```

Output directory for the compiled executable or library.  Passed to DCC
as the `-E<path>` flag.

When omitted, DCC uses the default output location defined in the
project's `.cfg` file.  The result object's `.exeOutputDir` is `$null`
when this parameter is not supplied.

## -DcuOutputDir

```text
-DcuOutputDir <path>
```

Output directory for compiled `.dcu` files.  Passed to DCC as the
`-N0<path>` flag (unit output path, index 0).

When omitted, DCC uses the default DCU location from the project's
`.cfg` file.  The result object's `.dcuOutputDir` is `$null` when this
parameter is not supplied.

## -UnitSearchPath

```text
-UnitSearchPath <path[]>
```

Additional unit search paths appended to the DCC unit path.  Accepts an
array of path strings.  Multiple paths are joined with semicolons and
passed as a single `-U<paths>` argument.

These paths are **appended** to the paths already set in the project's
`.cfg` file -- they do not replace them.

When omitted (or an empty array), no `-U` flag is added.  The result
object's `.unitSearchPath` is `$null` when no paths are supplied.

Example:

```
-UnitSearchPath @('C:\Libs\A', 'C:\Libs\B')
 ```

## -IncludePath

```text
-IncludePath <path[]>
```

Additional include file search paths.  Accepts an array of path strings.
Multiple paths are joined with semicolons and passed as a single
`-I<paths>` argument.

When omitted (or an empty array), no `-I` flag is added.  The result
object's `.includePath` is `$null` when no paths are supplied.

Example:

```text
-IncludePath @('C:\Inc\Headers')
```

## -Namespace

```text
-Namespace <string[]>
```

Unit scope names (namespace prefixes) the compiler searches when resolving
unqualified unit names.  Accepts an array of scope name strings.  Multiple
names are joined with semicolons and passed as a single `-NS` argument:

```text
-NSSystem;Vcl;Vcl.Imaging
```

This is important for modern Delphi (XE2+) projects that use namespaced RTL
units such as `System.SysUtils` or `Vcl.Forms`.  When building outside the IDE
without the project's `.cfg` file, the compiler cannot resolve `uses Forms`
unless the `Vcl` scope is listed here.

When omitted (or an empty array), no `-NS` argument is added.  The result
object's `.namespace` is `$null` when no names are supplied.

Example:

```powershell
-Namespace @('System', 'Vcl', 'Vcl.Imaging', 'Data')
```

## -Define

```text
-Define <string[]>
```

One or more additional conditional defines to pass to the DCC compiler.  When
at least one value is supplied, the defines are joined with semicolons and
passed as a single `-D` argument:

```text
-DMYFLAG;USE_JEDI_JCL
```

This is appended to the existing config define (e.g. `-DDEBUG`) that the script
always adds for the `-Config` value; it does not replace it.

When no `-Define` values are supplied (the default), no extra `-D` argument is
added beyond the config define.

Examples:

```powershell
# Single define
delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -RootDir $root -Define CI

# Multiple defines
delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -RootDir $root `
    -Define MYFLAG, USE_JEDI_JCL

# Via pipeline with defines
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
    delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -Define CI, MYFLAG
```

## -ShowOutput   (switch)

```text
-ShowOutput
```

When set:

- DCC output streams directly to stdout in real time.
- The result object's `.output` property is `$null`.
- On compiler failure, a `Write-Error` message is emitted to stderr.

When not set (default):

- DCC output (stdout and stderr combined) is captured.
- The result object's `.output` property contains the full captured text.
- On compiler failure, no additional stderr message is emitted
  (the captured output already contains the compiler diagnostics).

## -DelphiInstallation (pipeline input)

```text
[psobject] (ValueFromPipeline)
```

Accepts a `pscustomobject` from `delphi-inspect.ps1 -DetectLatest`.
The `.rootDir` property is used as the Delphi installation root when
`-RootDir` is not supplied explicitly.

Note: Any object with a `.rootDir` string property is accepted.

------------------------------------------------------------------------

# Result Object

On success or compiler failure (exit codes 0 and 5), a single
`pscustomobject` is written to the pipeline before the script exits.

| Property         | Type     | Description                                                   |
|------------------|----------|---------------------------------------------------------------|
| `projectFile`    | string   | Absolute path to the project file                             |
| `platform`       | string   | Platform value used (e.g. `Win32`)                            |
| `config`         | string   | Config value used (e.g. `Debug`)                              |
| `target`         | string   | Target used (e.g. `Build`)                                    |
| `rootDir`        | string   | Resolved Delphi installation root                             |
| `rsvarsPath`     | string   | Derived path to `rsvars.bat`                                  |
| `compilerPath`   | string   | Full path to the compiler executable                          |
| `exeOutputDir`   | string   | Value of `-ExeOutputDir`; `$null` when not supplied           |
| `dcuOutputDir`   | string   | Value of `-DcuOutputDir`; `$null` when not supplied           |
| `unitSearchPath` | string[] | Value of `-UnitSearchPath`; `$null` when not supplied         |
| `includePath`    | string[] | Value of `-IncludePath`; `$null` when not supplied            |
| `exitCode`       | int      | DCC process exit code                                         |
| `success`        | bool     | `$true` when `exitCode` is 0                                  |
| `output`         | string   | Captured DCC output; `$null` when `-ShowOutput`               |

On errors before the compiler is invoked (exit codes 2, 3, 4) no result
object is emitted.

------------------------------------------------------------------------

# Exit Codes

| Code | Meaning                                                                        |
|------|--------------------------------------------------------------------------------|
| `0`  | Compilation succeeded                                                          |
| `1`  | Unexpected internal error (unhandled exception)                                |
| `2`  | `-ProjectFile` was not supplied                                                |
| `3`  | `rootDir` missing/empty, directory not found, `rsvars.bat` absent, or compiler exe absent |
| `4`  | Project file not found on disk                                                 |
| `5`  | DCC compiler completed but returned a non-zero exit code                       |

------------------------------------------------------------------------

## Example 1) Normal -- pipe from delphi-inspect and build

Discover the latest ready DCC installation and pipe it into a build:

```powershell
$result = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
              delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr

$result.success      # $true
$result.exitCode     # 0
$result.platform     # Win32
$result.config       # Debug
$result.rootDir      # C:\Program Files (x86)\Embarcadero\Studio\23.0
$result.rsvarsPath   # C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat
$result.compilerPath # C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc32.exe
```

The captured DCC output is available in `$result.output` for
post-processing or logging.

## Example 2) Normal -- explicit root dir, Release config, Rebuild

Build without inspect, targeting a specific installation and rebuilding
all units:

```powershell
$result = delphi-dccbuild.ps1 `
              -ProjectFile .\src\MyApp.dpr `
              -RootDir     'C:\Program Files (x86)\Embarcadero\Studio\23.0' `
              -Platform    Win32 `
              -Config      Release `
              -Target      Rebuild
```

The resulting command passed to `dcc32.exe` is:

```bash
dcc32.exe "C:\Work\src\MyApp.dpr" -B -DRELEASE
```

## Example 3) Normal -- Win64 build

Select the 64-bit compiler by setting `-Platform Win64`.  The script
automatically uses `bin64\dcc64.exe`:

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win64 -BuildSystem DCC |
    delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -Platform Win64

$result.compilerPath # C:\...\Studio\23.0\bin64\dcc64.exe
```

## Example 4) Normal -- stream output to console

Use `-ShowOutput` when you want compiler output visible in real time:

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
    delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -ShowOutput -Verbosity quiet
```

Hints and warnings are suppressed (`-Q`); errors and the final build
summary appear on stdout as they are emitted by the compiler.

## Example 5) Normal -- feed result into a downstream step

The result object is always written to the pipeline before exit, so
downstream steps can branch on the build outcome:

```powershell
$buildResult = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
                    delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr

if ($buildResult.success) {
    # run tests, package, deploy, etc.
}
111

## Example 6) Error -- no Delphi installation supplied (exit 3)

Running without a piped object or `-RootDir`:

```powershell
delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr

# stderr: No Delphi root dir supplied. Provide -RootDir or pipe a
#         delphi-inspect result object.
# exit code: 3
# no result object emitted
```

The same exit code (3) is returned if `-RootDir` is supplied but the
directory does not exist, or if the expected compiler executable is
absent under the root:

```powershell
delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -RootDir C:\Missing\Path

# stderr: Delphi root dir not found on disk: C:\Missing\Path
# exit code: 3

delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr -RootDir C:\SomeDir -Platform Win32

# stderr: rsvars.bat not found: C:\SomeDir\bin\rsvars.bat
# exit code: 3
```

When `rsvars.bat` is present but the compiler executable is absent, the
error identifies the missing compiler:

```powershell
# stderr: DCC compiler not found: C:\SomeDir\bin\dcc32.exe
# exit code: 3
```

## Example 7) Error -- project file not found (exit 4)

```powershell
delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
    delphi-dccbuild.ps1 -ProjectFile .\src\Typo.dpr

# stderr: Project file not found: C:\Work\src\Typo.dpr
# exit code: 4
# no result object emitted
```

## Example 8) Error -- compiler failure (exit 5)

When DCC runs but returns a non-zero exit code (syntax errors, missing
units, etc.), the result object **is** emitted with `success = $false`
before the script exits:

```powershell
$result = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC |
              delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr

# exit code: 5
$result.success    # $false
$result.exitCode   # 1 (DCC uses exit 1 for fatal errors)
$result.output     # captured DCC output containing error lines
```

Common DCC error messages in `$result.output`:

- `Fatal: F1027 Unit not found: 'System.pas'` -- library paths in the
  `.cfg` file are missing or stale
- `Fatal: F2613 Unit 'SomeUnit' not found` -- a unit referenced by the
  project is not on the unit search path
- `[DCC Fatal Error] E2010 Incompatible types` -- a source-level
  compilation error

When `-ShowOutput` is used, compiler output has already streamed to
console and `$result.output` is `$null`; a `Write-Error` message is
emitted to stderr instead.

------------------------------------------------------------------------

# Environment Setup and Library Paths

This script sources `rsvars.bat` before invoking the compiler.
This populates the following environment variables in the current
PowerShell process:

- `BDS` -- Delphi installation root; referenced as `$(BDS)` in some
  project `.cfg` files and third-party component search paths
- `BDSCOMMONDIR` -- shared data directory; used by cross-platform
  targets and some component packages
- `BDSBIN` -- Delphi bin directory
- `FrameworkDir` / `FrameworkVersion` -- .NET Framework paths
- `PATH` -- prepended with Delphi bin paths

DCC then reads library paths from two additional sources automatically:

1. The **global per-platform `.cfg` file** in its own `bin` or `bin64`
   directory (e.g. `<RootDir>\bin\dcc32.cfg`).  This file is created
   and maintained by the RAD Studio installer.  It contains the RTL,
   VCL, and other standard unit paths for the platform, typically as
   absolute paths.

2. The **project-local `.cfg` file** in the same directory as the `.dpr`
   file (e.g. `src\MyApp.cfg`).  This file is generated by the IDE and
   contains project-specific unit paths, output directories, and defines.
   Some entries may reference `$(BDS)` or `$(BDSCOMMONDIR)`, which is
   why sourcing `rsvars.bat` matters even for DCC builds.

`delphi-inspect.ps1 -DetectLatest -BuildSystem DCC` checks that both
the compiler executable and its `.cfg` file are present before reporting
`readiness: ready`.  If the global `.cfg` is absent, the build will
fail with `F1027 Unit not found: 'System.pas'`.

------------------------------------------------------------------------

# Comparison with delphi-msbuild.ps1

| Aspect               | delphi-dccbuild.ps1          | delphi-msbuild.ps1              |
|----------------------|------------------------------|---------------------------------|
| Project file type    | `.dpr`                       | `.dproj`                        |
| Build system         | `dcc*.exe`                   | `msbuild.exe`                   |
| Environment setup    | Sources `rsvars.bat`         | Sources `rsvars.bat`            |
| Config parameter     | Added as define (`-DDEBUG`)  | Passed as `/p:Config=Debug`     |
| Target: Rebuild      | `-B` flag                    | `/t:Rebuild`                    |
| Target: Clean        | Not available                | `/t:Clean`                      |
| Verbosity options    | `quiet`, `normal`            | `quiet` through `diagnostic`    |
| Result `rsvarsPath`  | Present                      | Present                         |
| Result `compilerPath`| Present                      | Not present                     |
| Inspect -BuildSystem | `DCC`                        | `MSBuild`                       |

Both scripts use the same `-RootDir` parameter and accept the same
pipeline object shape (`.rootDir` property), so the same
`delphi-inspect.ps1 -DetectLatest` result object works with either.

------------------------------------------------------------------------

# Relationship to delphi-inspect.ps1

Use `delphi-inspect.ps1 -DetectLatest -BuildSystem DCC` to locate the
latest ready DCC installation and pipe the result directly:

```powershell
$install = delphi-inspect.ps1 -DetectLatest -Platform Win32 -BuildSystem DCC
$install | delphi-dccbuild.ps1 -ProjectFile .\src\MyApp.dpr
```

The `delphi-inspect.ps1` readiness check for DCC verifies that the
compiler executable and its `.cfg` file both exist.  If the install
reports `readiness: ready`, the compiler is expected to be functional
for basic builds.  Library path issues inside the `.cfg` (stale paths,
missing packages) are not detected by the readiness check and will only
surface as DCC errors at build time.

## Maturity

This repository is currently `incubator`. Both implementations are under active development.
It will graduate to `stable` once:

- At least one downstream consumer exists.

Until graduation, breaking changes may occur

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

## Part of the Continuous Delphi Organization

This repository follows the Continuous Delphi organization taxonomy. See
[cd-meta-org](https://github.com/continuous-delphi/cd-meta-org) for navigation and governance.

- `docs/org-taxonomy.md` -- naming and tagging conventions
- `docs/versioning-policy.md` -- release and versioning rules
- `docs/repo-lifecycle.md` -- lifecycle states and graduation criteria
