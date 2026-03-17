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

  Describe 4 - Get-CompilerPath:
    Produces the correct full path for Win32 (bin\dcc32.exe).
    Produces the correct full path for Win64 (bin64\dcc64.exe).
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

  Describe 8 - Main flow (via Invoke-ToolProcess, no DCC calls):
    Exits 3 when no rootDir is provided (no pipeline, no -RootDir).
    Exits 3 when rootDir directory does not exist on disk.
    Exits 3 when rootDir exists but rsvars.bat is absent.
    Exits 3 when rsvars.bat exists but compiler exe is absent.
    Exits 4 when rsvars.bat and compiler exist but project file does not.
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

}
