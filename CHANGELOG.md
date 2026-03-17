# Changelog

All notable changes to this project will be documented in this file.

---

## [0.3.0] - Unreleased

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
