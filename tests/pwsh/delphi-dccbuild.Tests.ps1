#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.7.0' }
<#
.SYNOPSIS
  Tests for delphi-dccbuild.ps1

.DESCRIPTION
  Covers the pure helper functions and mockable build flow.
  No tests invoke DCC or any external compiler.

  Describe 1 - Resolve-RootDir:
    Explicit -RootDir takes precedence over pipeline object.
    Pipeline .rootDir used when no explicit param.
    Returns null when neither source provides a value.
    Returns null when pipeline object has null/empty/absent rootDir.

  Describe 2 - Get-CompilerName:
    Returns correct DCC base name for each platform family.

  Describe 3 - Get-CompilerBinFolder:
    Returns bin64 for 64-bit compiler names; bin for all others.
    Returns bin64 for dccarm64ec.

  Describe 4 - Get-CompilerPath:
    Produces the correct full path for Win32 (bin\dcc32.exe).
    Produces the correct full path for Win64 (bin64\dcc64.exe).
    Produces the correct full path for WinARM64EC (bin64\dccarm64ec.exe).
    Produces the correct full path for Android32 (bin\dccaarm.exe).

  Describe 5 - Get-RsvarsPath:
    Derives bin\rsvars.bat path from rootDir.

  Describe 6 - Invoke-RsvarsEnvironment:
    Applies KEY=VALUE lines to process environment.
    Throws when Get-RsvarsEnvLines returns zero parseable lines.
    Propagates throw from Get-RsvarsEnvLines.

  Describe 7 - Invoke-DccProject:
    Passes ProjectFile as first argument to Invoke-DccExe.
    Passes -B flag when Target is Rebuild.
    Does not pass -B flag when Target is Build.
    Passes uppercased -D<Config> define.
    Passes -Q when Verbosity is quiet.
    Does not pass -Q when Verbosity is normal.
    Forwards -ShowOutput switch to Invoke-DccExe.
    Returns the result object from Invoke-DccExe.
    ExeOutputDir adds -E flag; omitted adds nothing.
    DcuOutputDir adds -N0 flag.
    UnitSearchPath single entry adds -U flag; multiple joined with semicolons.
    IncludePath single entry adds -I flag; multiple joined with semicolons.
    Namespace single entry adds a -NS flag with that value.
    Namespace multiple entries are joined with semicolons into a single -NS flag.
    Namespace omitted adds no -NS argument.
    Define omitted adds no extra -D argument beyond the config define.
    Define single entry adds a -D flag with that value.
    Define multiple entries are joined with semicolons into a single -D flag.
    NoConfig switch adds --no-config; omitted adds nothing.
    ResourcePath single/multiple adds -R (semicolon-joined); omitted adds nothing.
    BplOutputDir/DcpOutputDir/BpiOutputDir add -LE/-LN/-NB; omitted add nothing.
    LinkPackage single/multiple adds -LU (semicolon-joined); omitted adds nothing (static default).
    ExtraArgs appended verbatim after modeled switches; boundaries/order preserved; omitted adds nothing.

  Describe 8 - Main flow (via Invoke-ToolProcess, no DCC calls):
    Exits 3 when no rootDir is provided (no pipeline, no -RootDir).
    Exits 3 when rootDir directory does not exist on disk.
    Exits 3 when rootDir exists but rsvars.bat is absent.
    Exits 3 when rsvars.bat exists but compiler exe is absent.
    Exits 4 when rsvars.bat and compiler exist but project file does not.
    -SkipRsvars bypasses the rsvars.bat requirement (exit 4, not 3; no rsvars in stderr).
    -SkipRsvars still requires the compiler exe (exit 3 citing dcc32).

  Describe 9 - Resolve-WorkingDirectory:
    Defaults to the resolved project file's folder when WorkingDirectory empty/whitespace.
    Returns an explicit absolute WorkingDirectory unchanged.
    Resolves an explicit relative WorkingDirectory to absolute against the process CWD.

  Describe 10 - Resolve-DccPath / Resolve-DccPaths:
    Empty/whitespace passes through; absolute unchanged; relative resolved against process CWD.
    Empty array -> empty array; multi-entry array resolves each entry.

  Describe 11 - Invoke-DccProject working directory and relative-path anchoring:
    WorkingDirectory is forwarded to Invoke-DccExe.
    Relative -ExeOutputDir anchors to the caller CWD, not the project dir.

  Describe 12 - Invoke-DccExe working directory (invokes cmd.exe to observe child CWD):
    Child process runs in the requested working directory; [Environment]::CurrentDirectory restored.
    Working directory restored even when the child exits non-zero.
    Omitting WorkingDirectory leaves the process CWD untouched.

  Describe 13 - Write-DccResult (-OutputFile / -Format):
    Omitting both emits the PSCustomObject to the pipeline (default, unchanged).
    -Format json emits a single compressed JSON line to the pipeline.
    -Format json round-trips to an object whose fields match the source.
    -OutputFile writes the result as compressed JSON to the given path.
    -OutputFile is written even when -Format object is used (default).
    -OutputFile JSON round-trips to an object whose fields match the source.
#>

Describe 'Resolve-RootDir' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'returns explicit RootDir when provided' {
    $result = Resolve-RootDir -ExplicitRootDir 'C:\Explicit\Root' -Installation $null
    $result | Should -Be 'C:\Explicit\Root'
  }

  It 'explicit RootDir takes precedence over pipeline .rootDir' {
    $inst = [pscustomobject]@{ rootDir = 'C:\From\Pipeline' }
    $result = Resolve-RootDir -ExplicitRootDir 'C:\Explicit\Root' -Installation $inst
    $result | Should -Be 'C:\Explicit\Root'
  }

  It 'returns pipeline .rootDir when no explicit param' {
    $inst = [pscustomobject]@{ rootDir = 'C:\From\Pipeline' }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -Be 'C:\From\Pipeline'
  }

  It 'returns null when neither source provides a value' {
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $null
    $result | Should -BeNull
  }

  It 'returns null when pipeline object has null rootDir' {
    $inst = [pscustomobject]@{ rootDir = $null }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -BeNull
  }

  It 'returns null when pipeline object has empty rootDir' {
    $inst = [pscustomobject]@{ rootDir = '   ' }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -BeNull
  }

  It 'returns null when pipeline object has no rootDir property' {
    $inst = [pscustomobject]@{ verDefine = 'VER360' }
    $result = Resolve-RootDir -ExplicitRootDir '' -Installation $inst
    $result | Should -BeNull
  }

}

Describe 'Get-CompilerName' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'returns dcc32 for Win32' {
    Get-CompilerName -Platform 'Win32' | Should -Be 'dcc32'
  }

  It 'returns dcc64 for Win64' {
    Get-CompilerName -Platform 'Win64' | Should -Be 'dcc64'
  }

  It 'returns dccarm64ec for WinARM64EC' {
    Get-CompilerName -Platform 'WinARM64EC' | Should -Be 'dccarm64ec'
  }

  It 'returns dccosx for macOS32' {
    Get-CompilerName -Platform 'macOS32' | Should -Be 'dccosx'
  }

  It 'returns dccosx64 for macOS64' {
    Get-CompilerName -Platform 'macOS64' | Should -Be 'dccosx64'
  }

  It 'returns dccosxarm64 for macOSARM64' {
    Get-CompilerName -Platform 'macOSARM64' | Should -Be 'dccosxarm64'
  }

  It 'returns dcclinux64 for Linux64' {
    Get-CompilerName -Platform 'Linux64' | Should -Be 'dcclinux64'
  }

  It 'returns dccaarm for Android32' {
    Get-CompilerName -Platform 'Android32' | Should -Be 'dccaarm'
  }

  It 'returns dccaarm64 for Android64' {
    Get-CompilerName -Platform 'Android64' | Should -Be 'dccaarm64'
  }

}

Describe 'Get-CompilerBinFolder' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'returns bin for dcc32' {
    Get-CompilerBinFolder -CompilerName 'dcc32' | Should -Be 'bin'
  }

  It 'returns bin64 for dcc64' {
    Get-CompilerBinFolder -CompilerName 'dcc64' | Should -Be 'bin64'
  }

  It 'returns bin64 for dccarm64ec' {
    Get-CompilerBinFolder -CompilerName 'dccarm64ec' | Should -Be 'bin64'
  }

  It 'returns bin for dccosx (macOS32)' {
    Get-CompilerBinFolder -CompilerName 'dccosx' | Should -Be 'bin'
  }

  It 'returns bin64 for dccosx64 (macOS64)' {
    Get-CompilerBinFolder -CompilerName 'dccosx64' | Should -Be 'bin64'
  }

  It 'returns bin64 for dccosxarm64 (macOSARM64)' {
    Get-CompilerBinFolder -CompilerName 'dccosxarm64' | Should -Be 'bin64'
  }

  It 'returns bin64 for dcclinux64' {
    Get-CompilerBinFolder -CompilerName 'dcclinux64' | Should -Be 'bin64'
  }

  It 'returns bin for dccaarm (Android32)' {
    Get-CompilerBinFolder -CompilerName 'dccaarm' | Should -Be 'bin'
  }

  It 'returns bin64 for dccaarm64 (Android64)' {
    Get-CompilerBinFolder -CompilerName 'dccaarm64' | Should -Be 'bin64'
  }

}

Describe 'Get-CompilerPath' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'produces bin/dcc32.exe for Win32' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-CompilerPath -RootDir $root -Platform 'Win32'
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin', 'dcc32.exe'))
  }

  It 'produces bin64/dcc64.exe for Win64' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-CompilerPath -RootDir $root -Platform 'Win64'
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin64', 'dcc64.exe'))
  }

  It 'produces bin64/dccarm64ec.exe for WinARM64EC' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-CompilerPath -RootDir $root -Platform 'WinARM64EC'
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin64', 'dccarm64ec.exe'))
  }

  It 'produces bin/dccaarm.exe for Android32' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-CompilerPath -RootDir $root -Platform 'Android32'
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin', 'dccaarm.exe'))
  }

  It 'produces bin64/dccaarm64.exe for Android64' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-CompilerPath -RootDir $root -Platform 'Android64'
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin64', 'dccaarm64.exe'))
  }

}

Describe 'Get-RsvarsPath' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'produces the rsvars.bat path under the bin subdirectory' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $result = Get-RsvarsPath -RootDir $root
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin', 'rsvars.bat'))
  }

  It 'handles trailing separator in rootDir' {
    $root   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'fake-delphi', '23.0')
    $sep    = [System.IO.Path]::DirectorySeparatorChar
    $result = Get-RsvarsPath -RootDir "${root}${sep}"
    $result | Should -Be ([System.IO.Path]::Combine($root, 'bin', 'rsvars.bat'))
  }

}

Describe 'Invoke-RsvarsEnvironment' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  Context 'applies environment variables from Get-RsvarsEnvLines output' {

    BeforeAll {
      Mock Get-RsvarsEnvLines {
        return @(
          'BDS=C:\RAD\Studio\23.0',
          'BDSCOMMONDIR=C:\Users\Public\Documents\Embarcadero\Studio\23.0'
        )
      }
      Invoke-RsvarsEnvironment -RsvarsPath 'C:\RAD\Studio\23.0\bin\rsvars.bat'
    }

    It 'sets BDS in process environment' {
      [Environment]::GetEnvironmentVariable('BDS', 'Process') | Should -Be 'C:\RAD\Studio\23.0'
    }

    It 'sets BDSCOMMONDIR in process environment' {
      [Environment]::GetEnvironmentVariable('BDSCOMMONDIR', 'Process') |
        Should -Be 'C:\Users\Public\Documents\Embarcadero\Studio\23.0'
    }

    It 'calls Get-RsvarsEnvLines with the rsvars path' {
      Mock Get-RsvarsEnvLines { return @('BDS=C:\RAD\Studio\23.0') }
      Invoke-RsvarsEnvironment -RsvarsPath 'C:\RAD\Studio\23.0\bin\rsvars.bat'
      Should -Invoke Get-RsvarsEnvLines -ParameterFilter {
        $RsvarsPath -eq 'C:\RAD\Studio\23.0\bin\rsvars.bat'
      } -Times 1 -Exactly
    }

  }

  Context 'throws when Get-RsvarsEnvLines returns no parseable lines' {

    BeforeAll {
      Mock Get-RsvarsEnvLines { return @() }
    }

    It 'throws with a descriptive message' {
      { Invoke-RsvarsEnvironment -RsvarsPath 'C:\fake\rsvars.bat' } |
        Should -Throw -ExpectedMessage '*no environment variables*'
    }

  }

  Context 'propagates throw from Get-RsvarsEnvLines' {

    BeforeAll {
      Mock Get-RsvarsEnvLines { throw 'rsvars.bat exited with code 1 : C:\bad\rsvars.bat' }
    }

    It 'throws the error from Get-RsvarsEnvLines' {
      { Invoke-RsvarsEnvironment -RsvarsPath 'C:\bad\rsvars.bat' } |
        Should -Throw -ExpectedMessage '*rsvars.bat exited with code 1*'
    }

  }

}

Describe 'Invoke-DccProject' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  Context 'Build target with Debug config, normal verbosity' {

    BeforeAll {
      $script:capturedCompilerPath = $null
      $script:capturedArgs         = $null
      $script:capturedShowOutput   = $false
      Mock Invoke-DccExe {
        $script:capturedCompilerPath = $CompilerPath
        $script:capturedArgs         = $Arguments
        $script:capturedShowOutput   = [bool]$ShowOutput
        return [pscustomobject]@{ ExitCode = 0; Output = 'ok' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'passes ProjectFile as first argument' {
      $script:capturedArgs[0] | Should -Be 'C:\Projects\MyApp.dpr'
    }

    It 'passes -DDEBUG define' {
      $script:capturedArgs | Should -Contain '-DDEBUG'
    }

    It 'does not pass -B for Build target' {
      $script:capturedArgs | Should -Not -Contain '-B'
    }

    It 'does not pass -Q for normal verbosity' {
      $script:capturedArgs | Should -Not -Contain '-Q'
    }

    It 'passes the compiler path to Invoke-DccExe' {
      $script:capturedCompilerPath | Should -Be 'C:\RAD\Studio\23.0\bin\dcc32.exe'
    }

  }

  Context 'Rebuild target' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Rebuild' `
        -Verbosity    'normal'
    }

    It 'passes -B for Rebuild target' {
      $script:capturedArgs | Should -Contain '-B'
    }

  }

  Context 'Release config' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Release' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'passes -DRELEASE define' {
      $script:capturedArgs | Should -Contain '-DRELEASE'
    }

    It 'does not pass -DDEBUG define' {
      $script:capturedArgs | Should -Not -Contain '-DDEBUG'
    }

  }

  Context 'lowercase config is uppercased in define' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'release' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'define is uppercased to -DRELEASE' {
      $script:capturedArgs | Should -Contain '-DRELEASE'
    }

  }

  Context 'quiet verbosity' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'quiet'
    }

    It 'passes -Q for quiet verbosity' {
      $script:capturedArgs | Should -Contain '-Q'
    }

  }

  Context 'ShowOutput switch is forwarded' {

    BeforeAll {
      $script:capturedShowOutput = $false
      Mock Invoke-DccExe {
        $script:capturedShowOutput = [bool]$ShowOutput
        return [pscustomobject]@{ ExitCode = 0; Output = $null }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ShowOutput
    }

    It 'passes ShowOutput=$true to Invoke-DccExe' {
      $script:capturedShowOutput | Should -Be $true
    }

  }

  Context 'returns the result object from Invoke-DccExe' {

    BeforeAll {
      Mock Invoke-DccExe {
        return [pscustomobject]@{ ExitCode = 7; Output = 'compiler error text' }
      }
      $script:result = Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'result ExitCode matches Invoke-DccExe return' {
      $script:result.ExitCode | Should -Be 7
    }

    It 'result Output matches Invoke-DccExe return' {
      $script:result.Output | Should -Be 'compiler error text'
    }

  }

  Context 'ExeOutputDir adds -E flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ExeOutputDir 'C:\Build\bin'
    }

    It 'includes the -E flag with the ExeOutputDir value' {
      ($script:capturedArgs -contains '-EC:\Build\bin') | Should -Be $true
    }

  }

  Context 'ExeOutputDir omitted adds no -E flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'no argument starts with -E' {
      $script:capturedArgs | Where-Object { $_ -like '-E*' } | Should -BeNullOrEmpty
    }

  }

  Context 'DcuOutputDir adds -N0 flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -DcuOutputDir 'C:\Build\dcu'
    }

    It 'includes the -N0 flag with the DcuOutputDir value' {
      ($script:capturedArgs -contains '-N0C:\Build\dcu') | Should -Be $true
    }

  }

  Context 'UnitSearchPath single entry adds -U flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath    'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile     'C:\Projects\MyApp.dpr' `
        -Config          'Debug' `
        -Target          'Build' `
        -Verbosity       'normal' `
        -UnitSearchPath  @('C:\Libs\MyLib')
    }

    It 'includes the -U flag with the single path' {
      ($script:capturedArgs -contains '-UC:\Libs\MyLib') | Should -Be $true
    }

  }

  Context 'UnitSearchPath multiple entries are joined with semicolons' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath    'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile     'C:\Projects\MyApp.dpr' `
        -Config          'Debug' `
        -Target          'Build' `
        -Verbosity       'normal' `
        -UnitSearchPath  @('C:\Libs\A', 'C:\Libs\B')
    }

    It 'passes semicolon-separated -U argument' {
      ($script:capturedArgs -contains '-UC:\Libs\A;C:\Libs\B') | Should -Be $true
    }

  }

  Context 'IncludePath single entry adds -I flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -IncludePath  @('C:\Inc\Headers')
    }

    It 'includes the -I flag with the single path' {
      ($script:capturedArgs -contains '-IC:\Inc\Headers') | Should -Be $true
    }

  }

  Context 'IncludePath multiple entries are joined with semicolons' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -IncludePath  @('C:\Inc\A', 'C:\Inc\B')
    }

    It 'passes semicolon-separated -I argument' {
      ($script:capturedArgs -contains '-IC:\Inc\A;C:\Inc\B') | Should -Be $true
    }

  }

  Context 'Namespace single entry adds a -NS flag with that value' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -Namespace    @('System')
    }

    It 'includes -NSSystem' {
      $script:capturedArgs | Should -Contain '-NSSystem'
    }

  }

  Context 'Namespace multiple entries are joined with semicolons into a single -NS flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -Namespace    @('System', 'Vcl', 'Vcl.Imaging')
    }

    It 'includes -NSSystem;Vcl;Vcl.Imaging as a single argument' {
      $script:capturedArgs | Should -Contain '-NSSystem;Vcl;Vcl.Imaging'
    }

  }

  Context 'Namespace omitted adds no -NS argument' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'no argument starts with -NS' {
      ($script:capturedArgs | Where-Object { $_ -like '-NS*' }) | Should -BeNullOrEmpty
    }

  }

  Context 'Define omitted adds no extra -D argument beyond the config define' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'contains exactly one -D argument (the config define)' {
      @($script:capturedArgs | Where-Object { $_ -like '-D*' }).Count | Should -Be 1
    }

    It 'the only -D argument is -DDEBUG' {
      $script:capturedArgs | Should -Contain '-DDEBUG'
    }

  }

  Context 'Define single entry adds a -D flag with that value' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -Define       @('MYFLAG')
    }

    It 'includes -DMYFLAG' {
      $script:capturedArgs | Should -Contain '-DMYFLAG'
    }

  }

  Context 'Define multiple entries are joined with semicolons into a single -D flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -Define       @('MYFLAG', 'USE_JEDI_JCL')
    }

    It 'includes -DMYFLAG;USE_JEDI_JCL as a single argument' {
      $script:capturedArgs | Should -Contain '-DMYFLAG;USE_JEDI_JCL'
    }

  }

  Context 'NoConfig switch adds --no-config' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -NoConfig
    }

    It 'includes the --no-config argument' {
      $script:capturedArgs | Should -Contain '--no-config'
    }

  }

  Context 'NoConfig omitted adds no --no-config' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'no argument equals --no-config' {
      $script:capturedArgs | Should -Not -Contain '--no-config'
    }

  }

  Context 'ResourcePath single entry adds -R flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath  'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile   'C:\Projects\MyApp.dpr' `
        -Config        'Debug' `
        -Target        'Build' `
        -Verbosity     'normal' `
        -ResourcePath  @('C:\Res\Icons')
    }

    It 'includes the -R flag with the single path' {
      ($script:capturedArgs -contains '-RC:\Res\Icons') | Should -Be $true
    }

  }

  Context 'ResourcePath multiple entries are joined with semicolons' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath  'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile   'C:\Projects\MyApp.dpr' `
        -Config        'Debug' `
        -Target        'Build' `
        -Verbosity     'normal' `
        -ResourcePath  @('C:\Res\A', 'C:\Res\B')
    }

    It 'passes semicolon-separated -R argument' {
      ($script:capturedArgs -contains '-RC:\Res\A;C:\Res\B') | Should -Be $true
    }

  }

  Context 'ResourcePath omitted adds no -R flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'no argument starts with -R' {
      $script:capturedArgs | Where-Object { $_ -like '-R*' } | Should -BeNullOrEmpty
    }

  }

  Context 'BplOutputDir adds -LE flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyPkg.dpk' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -BplOutputDir 'C:\Build\bpl'
    }

    It 'includes the -LE flag with the BplOutputDir value' {
      ($script:capturedArgs -contains '-LEC:\Build\bpl') | Should -Be $true
    }

  }

  Context 'DcpOutputDir adds -LN flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyPkg.dpk' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -DcpOutputDir 'C:\Build\dcp'
    }

    It 'includes the -LN flag with the DcpOutputDir value' {
      ($script:capturedArgs -contains '-LNC:\Build\dcp') | Should -Be $true
    }

  }

  Context 'BpiOutputDir adds -NB flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyPkg.dpk' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -BpiOutputDir 'C:\Build\bpi'
    }

    It 'includes the -NB flag with the BpiOutputDir value' {
      ($script:capturedArgs -contains '-NBC:\Build\bpi') | Should -Be $true
    }

  }

  Context 'package output dirs omitted add no -LE/-LN/-NB flags' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'no argument starts with -LE' {
      $script:capturedArgs | Where-Object { $_ -like '-LE*' } | Should -BeNullOrEmpty
    }

    It 'no argument starts with -LN' {
      $script:capturedArgs | Where-Object { $_ -like '-LN*' } | Should -BeNullOrEmpty
    }

    It 'no argument starts with -NB' {
      $script:capturedArgs | Where-Object { $_ -like '-NB*' } | Should -BeNullOrEmpty
    }

  }

  Context 'LinkPackage single entry adds -LU flag' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -LinkPackage  @('rtl')
    }

    It 'includes -LUrtl' {
      $script:capturedArgs | Should -Contain '-LUrtl'
    }

  }

  Context 'LinkPackage multiple entries are joined with semicolons' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -LinkPackage  @('rtl', 'vcl')
    }

    It 'includes -LUrtl;vcl as a single argument' {
      $script:capturedArgs | Should -Contain '-LUrtl;vcl'
    }

  }

  Context 'LinkPackage omitted adds no -LU flag (static link is the default)' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'no argument starts with -LU' {
      $script:capturedArgs | Where-Object { $_ -like '-LU*' } | Should -BeNullOrEmpty
    }

  }

  Context 'ExtraArgs single entry is appended verbatim' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ExtraArgs    @('-$D0')
    }

    It 'includes the -$D0 argument as-is' {
      $script:capturedArgs | Should -Contain '-$D0'
    }

  }

  Context 'ExtraArgs multiple entries preserve array boundaries' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ExtraArgs    @('-$D0', '-$L-', '-$C-', '-$Y-')
    }

    It 'passes each element as a distinct argument (no joining)' {
      $script:capturedArgs | Should -Contain '-$D0'
      $script:capturedArgs | Should -Contain '-$L-'
      $script:capturedArgs | Should -Contain '-$C-'
      $script:capturedArgs | Should -Contain '-$Y-'
    }

  }

  Context 'ExtraArgs element containing a space is not split' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ExtraArgs    @('-Vraw with space')
    }

    It 'keeps the spaced value as a single argument' {
      $script:capturedArgs | Should -Contain '-Vraw with space'
    }

  }

  Context 'ExtraArgs are positioned after the modeled switches' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -Define       @('MYFLAG') `
        -ExtraArgs    @('-JL')
    }

    It 'the -JL extra arg appears after the modeled -DMYFLAG define' {
      $extraIdx = [array]::IndexOf($script:capturedArgs, '-JL')
      $defIdx   = [array]::IndexOf($script:capturedArgs, '-DMYFLAG')
      $extraIdx | Should -BeGreaterThan $defIdx
    }

  }

  Context 'ExtraArgs preserve their relative order' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal' `
        -ExtraArgs    @('-JL', '-V')
    }

    It '-JL precedes -V in the captured args' {
      $jlIdx = [array]::IndexOf($script:capturedArgs, '-JL')
      $vIdx  = [array]::IndexOf($script:capturedArgs, '-V')
      $jlIdx | Should -BeGreaterOrEqual 0
      $vIdx  | Should -BeGreaterThan $jlIdx
    }

  }

  Context 'ExtraArgs omitted adds nothing' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath 'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile  'C:\Projects\MyApp.dpr' `
        -Config       'Debug' `
        -Target       'Build' `
        -Verbosity    'normal'
    }

    It 'captured args contain only the project file and modeled switches' {
      # Project file + -DDEBUG only for this minimal invocation
      @($script:capturedArgs).Count | Should -Be 2
      $script:capturedArgs[0] | Should -Be 'C:\Projects\MyApp.dpr'
      $script:capturedArgs | Should -Contain '-DDEBUG'
    }

  }

}

Describe 'Main flow -- pre-compiler validation (no DCC invoked)' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:scriptPath = Get-DccBuildScriptPath
  }

  Context 'exits 3 when no rootDir is provided and no pipeline input' {

    BeforeAll {
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dpr'
      )
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr contains helpful message' {
      $script:result.StdErr -join ' ' | Should -Match 'root dir'
    }

  }

  Context 'exits 3 when rootDir directory does not exist on disk' {

    BeforeAll {
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dpr',
        '-RootDir',     'C:\DoesNotExist\AtAll\9999'
      )
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions the missing directory' {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

  Context 'exits 3 when rootDir exists but rsvars.bat is absent' {

    BeforeAll {
      # Use a real directory that exists on all platforms but has no rsvars.bat
      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dpr',
        '-RootDir',     ([System.IO.Path]::GetTempPath()),
        '-Platform',    'Win32'
      )
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions rsvars.bat' {
      $script:result.StdErr -join ' ' | Should -Match 'rsvars\.bat'
    }

  }

  Context 'exits 3 when rsvars.bat exists but compiler exe is absent' {

    BeforeAll {
      # Seed rsvars.bat but not dcc32.exe
      $script:tempRoot    = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-dccbuild-rsvars-test'
      $script:tempBin     = Join-Path $script:tempRoot 'bin'
      $null = New-Item -ItemType Directory -Path $script:tempBin -Force
      $null = New-Item -ItemType File -Path (Join-Path $script:tempBin 'rsvars.bat') -Force

      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dpr',
        '-RootDir',     $script:tempRoot,
        '-Platform',    'Win32'
      )
    }

    AfterAll {
      Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions the compiler name' {
      $script:result.StdErr -join ' ' | Should -Match 'dcc32'
    }

  }

  Context 'exits 4 when rsvars.bat and compiler exist but project file does not' {

    BeforeAll {
      # Seed both rsvars.bat and dcc32.exe so all installation checks pass
      $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-dccbuild-test'
      $script:tempBin  = Join-Path $script:tempRoot 'bin'
      $null = New-Item -ItemType Directory -Path $script:tempBin -Force
      $null = New-Item -ItemType File -Path (Join-Path $script:tempBin 'rsvars.bat') -Force
      $null = New-Item -ItemType File -Path (Join-Path $script:tempBin 'dcc32.exe') -Force

      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\DoesNotExist.dpr',
        '-RootDir',     $script:tempRoot,
        '-Platform',    'Win32'
      )
    }

    AfterAll {
      Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exit code is 4' {
      $script:result.ExitCode | Should -Be 4
    }

    It 'stderr mentions the missing project file' {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

  Context '-SkipRsvars bypasses the rsvars.bat requirement' {

    BeforeAll {
      # Seed dcc32.exe but deliberately NO rsvars.bat.  Without -SkipRsvars this
      # would exit 3 (rsvars absent); with it, validation proceeds past rsvars
      # to the project-file check, so a missing project file yields exit 4.
      $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-dccbuild-skiprsvars-test'
      $script:tempBin  = Join-Path $script:tempRoot 'bin'
      $null = New-Item -ItemType Directory -Path $script:tempBin -Force
      $null = New-Item -ItemType File -Path (Join-Path $script:tempBin 'dcc32.exe') -Force

      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\DoesNotExist.dpr',
        '-RootDir',     $script:tempRoot,
        '-Platform',    'Win32',
        '-SkipRsvars'
      )
    }

    AfterAll {
      Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exit code is 4 (reached the project-file check, not blocked on rsvars)' {
      $script:result.ExitCode | Should -Be 4
    }

    It 'stderr does not mention rsvars.bat' {
      $script:result.StdErr -join ' ' | Should -Not -Match 'rsvars\.bat'
    }

    It 'stderr mentions the missing project file' {
      $script:result.StdErr -join ' ' | Should -Match 'not found'
    }

  }

  Context '-SkipRsvars still requires the compiler exe' {

    BeforeAll {
      # No rsvars.bat and no dcc32.exe.  -SkipRsvars bypasses rsvars but the
      # compiler must still exist, so this exits 3 citing the compiler.
      $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'delphi-dccbuild-skiprsvars-nocc-test'
      $script:tempBin  = Join-Path $script:tempRoot 'bin'
      $null = New-Item -ItemType Directory -Path $script:tempBin -Force

      $script:result = Invoke-ToolProcess -ScriptPath $script:scriptPath -Arguments @(
        '-ProjectFile', 'C:\Fake\MyApp.dpr',
        '-RootDir',     $script:tempRoot,
        '-Platform',    'Win32',
        '-SkipRsvars'
      )
    }

    AfterAll {
      Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exit code is 3' {
      $script:result.ExitCode | Should -Be 3
    }

    It 'stderr mentions the compiler name' {
      $script:result.StdErr -join ' ' | Should -Match 'dcc32'
    }

  }

}

Describe 'Resolve-WorkingDirectory' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'defaults to the folder of the resolved project file when WorkingDirectory is empty' {
    $proj = [System.IO.Path]::Combine('C:\', 'Projects', 'Sub', 'MyApp.dpr')
    $result = Resolve-WorkingDirectory -WorkingDirectory '' -ProjectFile $proj
    $result | Should -Be ([System.IO.Path]::Combine('C:\', 'Projects', 'Sub'))
  }

  It 'defaults to the project folder when WorkingDirectory is whitespace' {
    $proj = [System.IO.Path]::Combine('C:\', 'Projects', 'Sub', 'MyApp.dpr')
    $result = Resolve-WorkingDirectory -WorkingDirectory '   ' -ProjectFile $proj
    $result | Should -Be ([System.IO.Path]::Combine('C:\', 'Projects', 'Sub'))
  }

  It 'returns an explicit absolute WorkingDirectory unchanged' {
    $dir = [System.IO.Path]::Combine('C:\', 'Other', 'Work')
    $proj = [System.IO.Path]::Combine('C:\', 'Projects', 'Sub', 'MyApp.dpr')
    $result = Resolve-WorkingDirectory -WorkingDirectory $dir -ProjectFile $proj
    $result | Should -Be $dir
  }

  It 'resolves an explicit relative WorkingDirectory to absolute against the process CWD' {
    $anchor = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dccbuild-wd-anchor')
    $null = New-Item -ItemType Directory -Path $anchor -Force
    $originalEnvCwd = [System.Environment]::CurrentDirectory
    try {
      [System.Environment]::CurrentDirectory = $anchor
      $result = Resolve-WorkingDirectory -WorkingDirectory 'relsub' -ProjectFile 'C:\Projects\MyApp.dpr'
      $result | Should -Be ([System.IO.Path]::Combine([System.IO.Path]::GetFullPath($anchor), 'relsub'))
    }
    finally {
      [System.Environment]::CurrentDirectory = $originalEnvCwd
      Remove-Item -LiteralPath $anchor -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

}

Describe 'Resolve-DccPath / Resolve-DccPaths' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  It 'passes an empty string through unchanged' {
    Resolve-DccPath -Path '' | Should -Be ''
  }

  It 'passes whitespace through unchanged' {
    Resolve-DccPath -Path '   ' | Should -Be '   '
  }

  It 'returns an absolute path unchanged' {
    $abs = [System.IO.Path]::Combine('C:\', 'Abs', 'Path')
    Resolve-DccPath -Path $abs | Should -Be $abs
  }

  It 'resolves a relative path to absolute against the process CWD' {
    $anchor = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dccbuild-path-anchor')
    $null = New-Item -ItemType Directory -Path $anchor -Force
    $originalEnvCwd = [System.Environment]::CurrentDirectory
    try {
      [System.Environment]::CurrentDirectory = $anchor
      Resolve-DccPath -Path 'out\bin' |
        Should -Be ([System.IO.Path]::Combine([System.IO.Path]::GetFullPath($anchor), 'out', 'bin'))
    }
    finally {
      [System.Environment]::CurrentDirectory = $originalEnvCwd
      Remove-Item -LiteralPath $anchor -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It 'returns an empty array for an empty input array' {
    $result = @(Resolve-DccPaths -Paths @())
    $result.Count | Should -Be 0
  }

  It 'resolves each entry of a multi-entry array' {
    $a = [System.IO.Path]::Combine('C:\', 'Libs', 'A')
    $b = [System.IO.Path]::Combine('C:\', 'Libs', 'B')
    $result = @(Resolve-DccPaths -Paths @($a, $b))
    $result.Count | Should -Be 2
    $result[0] | Should -Be $a
    $result[1] | Should -Be $b
  }

}

Describe 'Invoke-DccProject -- working directory and relative-path anchoring' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  Context 'WorkingDirectory is forwarded to Invoke-DccExe' {

    BeforeAll {
      $script:capturedWorkingDir = $null
      Mock Invoke-DccExe {
        $script:capturedWorkingDir = $WorkingDirectory
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      Invoke-DccProject `
        -CompilerPath     'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile      'C:\Projects\MyApp.dpr' `
        -Config           'Debug' `
        -Target           'Build' `
        -Verbosity        'normal' `
        -WorkingDirectory 'C:\Work\Dir'
    }

    It 'passes the WorkingDirectory to Invoke-DccExe' {
      $script:capturedWorkingDir | Should -Be 'C:\Work\Dir'
    }

  }

  Context 'relative ExeOutputDir is anchored to the caller CWD, not the project dir' {

    BeforeAll {
      $script:capturedArgs = $null
      Mock Invoke-DccExe {
        $script:capturedArgs = $Arguments
        return [pscustomobject]@{ ExitCode = 0; Output = '' }
      }

      $script:anchor = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dccbuild-exeout-anchor')
      $null = New-Item -ItemType Directory -Path $script:anchor -Force
      $script:originalEnvCwd = [System.Environment]::CurrentDirectory
      [System.Environment]::CurrentDirectory = $script:anchor

      Invoke-DccProject `
        -CompilerPath     'C:\RAD\Studio\23.0\bin\dcc32.exe' `
        -ProjectFile      'C:\Projects\Deep\MyApp.dpr' `
        -Config           'Debug' `
        -Target           'Build' `
        -Verbosity        'normal' `
        -ExeOutputDir     'out\bin' `
        -WorkingDirectory 'C:\Projects\Deep'
    }

    AfterAll {
      [System.Environment]::CurrentDirectory = $script:originalEnvCwd
      Remove-Item -LiteralPath $script:anchor -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'emits -E resolved against the caller CWD (temp anchor), not the project folder' {
      $expected = '-E' + [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($script:anchor), 'out', 'bin')
      $script:capturedArgs | Should -Contain $expected
    }

    It 'does not anchor the output under the project folder' {
      ($script:capturedArgs | Where-Object { $_ -like '*Projects\Deep\out*' }) | Should -BeNullOrEmpty
    }

  }

}

Describe 'Invoke-DccExe -- working directory is applied to the child process and restored' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)
  }

  # These tests invoke cmd.exe (not a Delphi compiler) purely to observe the
  # working directory a native child process actually inherits -- the exact
  # Windows PowerShell 5.1 behavior the -WorkingDirectory feature depends on.
  Context 'child process runs in the requested working directory' -Skip:(-not $IsWindows) {

    BeforeAll {
      $script:workDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dccbuild-exe-cwd')
      $null = New-Item -ItemType Directory -Path $script:workDir -Force
      $script:expectedDir = [System.IO.Path]::GetFullPath($script:workDir).TrimEnd('\')
      $script:originalEnvCwd = [System.Environment]::CurrentDirectory

      # `cmd /c cd` prints the child's current directory.
      $script:result = Invoke-DccExe -CompilerPath $env:ComSpec -Arguments @('/c', 'cd') -WorkingDirectory $script:workDir
    }

    AfterAll {
      Remove-Item -LiteralPath $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exits 0' {
      $script:result.ExitCode | Should -Be 0
    }

    It 'the child reported the requested working directory' {
      $script:result.Output.Trim() | Should -Be $script:expectedDir
    }

    It 'restores [Environment]::CurrentDirectory afterward' {
      [System.Environment]::CurrentDirectory | Should -Be $script:originalEnvCwd
    }

  }

  Context 'working directory is restored even when the child exits non-zero' -Skip:(-not $IsWindows) {

    BeforeAll {
      $script:workDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dccbuild-exe-cwd-fail')
      $null = New-Item -ItemType Directory -Path $script:workDir -Force
      $script:originalEnvCwd = [System.Environment]::CurrentDirectory

      $script:result = Invoke-DccExe -CompilerPath $env:ComSpec -Arguments @('/c', 'exit 7') -WorkingDirectory $script:workDir
    }

    AfterAll {
      Remove-Item -LiteralPath $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'propagates the non-zero exit code' {
      $script:result.ExitCode | Should -Be 7
    }

    It 'still restores [Environment]::CurrentDirectory' {
      [System.Environment]::CurrentDirectory | Should -Be $script:originalEnvCwd
    }

  }

  Context 'omitting WorkingDirectory leaves the process CWD untouched' -Skip:(-not $IsWindows) {

    BeforeAll {
      $script:originalEnvCwd = [System.Environment]::CurrentDirectory
      $script:result = Invoke-DccExe -CompilerPath $env:ComSpec -Arguments @('/c', 'exit 0')
    }

    It 'exits 0' {
      $script:result.ExitCode | Should -Be 0
    }

    It 'does not change [Environment]::CurrentDirectory' {
      [System.Environment]::CurrentDirectory | Should -Be $script:originalEnvCwd
    }

  }

}

Describe 'Write-DccResult -- OutputFile / Format' {

  BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    . (Get-DccBuildScriptPath)

    $script:sampleResult = [pscustomobject]@{
      scriptVersion = '0.4.8'
      projectFile   = 'C:\Projects\MyApp.dpr'
      platform      = 'Win32'
      config        = 'Debug'
      exitCode      = 0
      success       = $true
      output        = 'compile ok'
    }
  }

  Context 'default (Format object, no OutputFile) emits the object to the pipeline' {

    BeforeAll {
      $script:out = Write-DccResult -ResultObject $script:sampleResult -OutputFile '' -Format 'object'
    }

    It 'emits a single object (not a JSON string)' {
      @($script:out).Count | Should -Be 1
      $script:out | Should -BeOfType [System.Management.Automation.PSCustomObject]
    }

    It 'the emitted object retains its fields' {
      $script:out.projectFile | Should -Be 'C:\Projects\MyApp.dpr'
      $script:out.exitCode    | Should -Be 0
      $script:out.success     | Should -BeTrue
    }

  }

  Context 'Format json emits a single compressed JSON line' {

    BeforeAll {
      $script:out = Write-DccResult -ResultObject $script:sampleResult -OutputFile '' -Format 'json'
    }

    It 'emits a string, not an object' {
      $script:out | Should -BeOfType [string]
    }

    It 'is a single compressed line (no embedded newlines)' {
      @($script:out).Count | Should -Be 1
      $script:out | Should -Not -Match "`n"
    }

    It 'round-trips to an object whose fields match the source' {
      $parsed = $script:out | ConvertFrom-Json
      $parsed.projectFile | Should -Be 'C:\Projects\MyApp.dpr'
      $parsed.platform    | Should -Be 'Win32'
      $parsed.exitCode    | Should -Be 0
      $parsed.success     | Should -BeTrue
    }

  }

  Context 'OutputFile writes the result as JSON to the given path' {

    BeforeAll {
      $script:tempFile = Join-Path ([System.IO.Path]::GetTempPath()) 'dccbuild-outputfile-test.json'
      Remove-Item -LiteralPath $script:tempFile -Force -ErrorAction SilentlyContinue

      # Format object (default) so we also confirm the file is written
      # independently of the pipeline format.
      $script:out = Write-DccResult -ResultObject $script:sampleResult -OutputFile $script:tempFile -Format 'object'
    }

    AfterAll {
      Remove-Item -LiteralPath $script:tempFile -Force -ErrorAction SilentlyContinue
    }

    It 'creates the output file' {
      Test-Path -LiteralPath $script:tempFile | Should -BeTrue
    }

    It 'the file contents round-trip to an object whose fields match the source' {
      $parsed = Get-Content -LiteralPath $script:tempFile -Raw | ConvertFrom-Json
      $parsed.projectFile | Should -Be 'C:\Projects\MyApp.dpr'
      $parsed.config      | Should -Be 'Debug'
      $parsed.success     | Should -BeTrue
    }

    It 'the file is a single compressed JSON line' {
      $lines = Get-Content -LiteralPath $script:tempFile
      @($lines).Count | Should -Be 1
    }

    It 'still emits the object to the pipeline (Format object)' {
      $script:out | Should -BeOfType [System.Management.Automation.PSCustomObject]
      $script:out.projectFile | Should -Be 'C:\Projects\MyApp.dpr'
    }

  }

}
