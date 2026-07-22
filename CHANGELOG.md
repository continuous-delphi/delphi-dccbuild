# Changelog

All notable changes to this project will be documented in this file.

---

## [0.4.12] - 2026-07-21

- Auto-create output directories (`-ExeOutputDir`, `-DcuOutputDir`,
  `-BplOutputDir`, `-DcpOutputDir`, `-BpiOutputDir`) before invoking the
  compiler.  `dcc32` does not create a missing output dir (it fails with an I/O
  error), unlike MSBuild's DCC targets.  Creation is idempotent and anchors
  relative dirs to the caller's original CWD; a creation failure (invalid path,
  permission, or a file in the way) fails fast with new exit code 6
  [#19](https://github.com/continuous-delphi/delphi-dccbuild/issues/19)

## [0.4.11] - 2026-07-21

- Fix `warnings`/`errors` reading 0 on every module-driven DCC build:
  `Invoke-DccExe` under `-ShowOutput` returned `Output = $null` (streamed
  instead of captured), starving `Get-DccBuildCount`, and
  `delphi-powershell-ci`'s `Invoke-BuildPipeline` always passes `-ShowOutput`.
  `Invoke-DccExe` now tees like `delphi-msbuild.ps1`'s `Invoke-MsbuildExe` --
  output is always captured and additionally streamed to the host under
  `-ShowOutput` -- so the counts and the result object's `.output` are
  populated on every path
  [#18](https://github.com/continuous-delphi/delphi-dccbuild/issues/18)

## [0.4.10] - 2026-07-21

- Add integer `warnings` and `errors` fields to the result object, matching
  `delphi-msbuild.ps1` so `delphi-powershell-ci` reports accurate counts for
  DCC builds instead of defaulting them to 0.  dcc32 has no MSBuild-style
  summary block, so the counts are parsed from diagnostic codes (`W####`;
  `E####` plus fatal `F####`, folded into errors; hints `H####` excluded) --
  counting codes rather than localized severity words
  [#17](https://github.com/continuous-delphi/delphi-dccbuild/issues/17)

## [0.4.8] - 2026-07-21

- Add `-OutputFile <path>` (writes the result object as compressed JSON to a
  file) and `-Format object|json` (default `object`), matching
  `delphi-msbuild.ps1` so `delphi-powershell-ci`'s DCCBuild engine can marshal
  the result end-to-end
  [#16](https://github.com/continuous-delphi/delphi-dccbuild/issues/16)

## [0.4.7] - 2026-07-21

- Run the compiler from the project file's folder by default so relative
  `uses ... in '..\..\Unit.pas'`, `{$I ..\defs.inc}`, and `{$R ..\app.res}`
  references resolve as the project author intended (matching the legacy
  `DelphiBuild.bat`).  Add `-WorkingDirectory` to override the default.
  Relative output/search paths are anchored to the caller's original CWD so
  they land where they did before, and the child process CWD is set via
  `[Environment]::CurrentDirectory` so it works on Windows PowerShell 5.1
  [#15](https://github.com/continuous-delphi/delphi-dccbuild/issues/15)

## [0.3.6] - 2026-07-21

- Add `-SkipRsvars` switch that bypasses the `rsvars.bat` requirement and
  sourcing, running the compiler against the caller's pre-set environment;
  unblocks toolchains that predate `rsvars.bat` (Delphi 2/7/2005) and
  caller-managed environments.  The compiler exe is still required
  [#14](https://github.com/continuous-delphi/delphi-dccbuild/issues/14)

## [0.3.4] - 2026-07-21

- Add `-ExtraArgs` escape hatch that appends arbitrary arguments verbatim
  after the modeled switches, for dcc32 options the script does not model
  (e.g. `-$D0`, `-$L-`, `-JL`, `-V*`); array boundaries and order preserved
  [#13](https://github.com/continuous-delphi/delphi-dccbuild/issues/13)

## [0.3.3] - 2026-07-21

- Add resource and package switches: `-ResourcePath` (`-R`), `-BplOutputDir`
  (`-LE`), `-DcpOutputDir` (`-LN`), `-BpiOutputDir` (`-NB`), and `-LinkPackage`
  (`-LU`).  `-LinkPackage` is strictly opt-in so the static-link default keeps
  standalone exes working
  [#12](https://github.com/continuous-delphi/delphi-dccbuild/issues/12)

## [0.3.2] - 2026-07-21

- Add `-NoConfig` switch that passes `--no-config` to DCC so it does not
  auto-load `<RootDir>\bin\dcc32.cfg`; enables reproducible builds on portable
  or trimmed toolchains whose `.cfg` carries stale library paths
  [#11](https://github.com/continuous-delphi/delphi-dccbuild/issues/11)

## [0.3.1] - 2026-04-25

- Add `WinARM64EC` as a valid DCC platform value, mapped to
  `bin64\dccarm64ec.exe`, with focused tests for compiler name, bin folder,
  and compiler path resolution
- Correct the release template to describe `.dpr` projects and
  `delphi-inspect -DetectLatest -BuildSystem DCC`

## [0.3.0] - 2026-03-17

- Ensure `PowerShell 5.1` compatibility for the delphi-dccbuild.ps1 script
  (Tests remain the newer `pwsh`)  
  [#6](https://github.com/continuous-delphi/delphi-dccbuild/issues/6)

## [0.2.0] - 2026-03-16

- Add `-Namespace` parameter to specify unit scope names for unqualified unit
  resolution via the `-NS` flag; required for modern Delphi projects using
  namespaced RTL units (e.g. `System.SysUtils`, `Vcl.Forms`) when building
  outside the IDE without a project `.cfg` file
  [#4](https://github.com/continuous-delphi/delphi-dccbuild/issues/4)

- Add support for passing compiler defines to DCC
  [#2](https://github.com/continuous-delphi/delphi-dccbuild/issues/2)

## [0.1.0] - 2026-03-16

- RC1 release of `delphi-dccbuild.ps1`

---

<br />
<br />

## `delphi-dccbuild` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi