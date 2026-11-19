# Production validators run on every host. Dart probes use the real bundled SDK
# and filesystem; they are not a claim that a native Windows build ran here.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/desktop/scripts/Invoke-PreviewBuild.ps1')
. (Join-Path $root 'src/desktop/scripts/Test-WindowsBuildPrerequisites.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-prerequisites-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture)
$passed=0;$failed=0;$skipped=0
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failed++;Write-Host "FAIL $Name : $($_.Exception.Message)"}
}
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Failure([scriptblock]$Body,[string]$Expected){
    $failure='';try{& $Body | Out-Null}catch{$failure=$_.Exception.Message}
    Assert-That ($failure.Contains($Expected)) "Expected '$Expected', received '$failure'."
}
function New-Project([string]$Name,[string]$Manifest="name: prerequisite_fixture`nflutter:`n  uses-material-design: true`n"){
    $path=Join-Path $fixture $Name
    [void](New-Item -ItemType Directory -Path $path -Force)
    Set-Content -LiteralPath (Join-Path $path 'pubspec.yaml') -Value $Manifest -Encoding utf8
    return $path
}
function Assert-ProbeClean([string]$Directory){
    $left=@(Get-ChildItem -LiteralPath $Directory -Directory -Recurse -Force | Where-Object Name -Like '.continuum-symlink-probe-*')
    Assert-That ($left.Count -eq 0) 'Capability probe left an owned temporary directory behind.'
}
try{
    Check 'machine output finds complete JSON after a banner and quoted braces' {
        $parsed=ConvertFrom-ContinuumPrerequisiteJson -Text "SDK initialization [progress]`n{`"status`":`"ready`"}`n{`"frameworkVersion`":`"3.47.9`",`"message`":`"quoted } [ and \`" text`"}`n" -Description 'fixture' -RootKind Object -RequiredProperty frameworkVersion
        Assert-That ($parsed['frameworkVersion'] -ceq '3.47.9') 'Version object was not found.'
        Assert-That ($parsed['message'].Contains('quoted } [')) 'Quoted delimiters broke JSON scanning.'
    }
    Check 'vswhere JSON preserves zero, one and multiple installation arrays' {
        foreach($sample in @(@{text='[]';count=0},@{text='[{"installationPath":"one"}]';count=1},@{text='[{"a":1},{"a":2}]';count=2})){
            $parsed=ConvertFrom-ContinuumPrerequisiteJson -Text $sample.text -Description 'vswhere fixture' -RootKind Array
            Assert-That ($parsed -is [array] -and $parsed.Count -eq $sample.count) "Array count $($sample.count) was collapsed."
        }
    }
    Check 'invalid or excessive machine output is rejected' {
        Assert-Failure {ConvertFrom-ContinuumPrerequisiteJson -Text '{broken}' -Description 'fixture'} 'did not return valid JSON'
        Assert-Failure {ConvertFrom-ContinuumPrerequisiteJson -Text ('x' * (1MB+1)) -Description 'fixture'} 'unexpectedly large output'
    }
    Check 'supported PowerShell and x64 host are required explicitly' {
        Assert-ContinuumBuildHost -OperatingSystemArchitecture X64 -ProcessArchitecture X64 -PowerShellVersion 7.4
        Assert-Failure {Assert-ContinuumBuildHost X64 X64 7.3} '7.4 or newer'
        Assert-Failure {Assert-ContinuumBuildHost Arm64 X64 7.4} 'Windows x64 only'
        Assert-Failure {Assert-ContinuumBuildHost X64 X86 7.4} 'Windows x64 only'
    }
    Check 'source paths accept spaces, Unicode and brackets supported by Flutter' {
        $project=New-Project 'checkout [review] élan 仓库'
        Assert-That ((Assert-ContinuumBuildPath $project) -ceq $project) 'Supported source path was rejected or changed.'
    }
    Check 'MSBuild restricted source path characters fail before commands' {
        foreach($character in "'#!`$^&*=|,;<>?".ToCharArray()){
            Assert-Failure {Assert-ContinuumBuildPath (Join-Path $fixture ('source'+$character+'folder'))} 'MSBuild build cannot use'
        }
    }
    Check 'Flutter and Dart metadata reject incompatible SDKs' {
        $metadata=@{frameworkVersion='3.47.9';dartSdkVersion='3.13.7';flutterRoot=$fixture}
        Assert-That ((Assert-ContinuumFlutterMetadata $metadata 'flutter.bat') -ceq $fixture) 'Pinned SDK was rejected.'
        $metadata.frameworkVersion='3.47.8'
        Assert-Failure {Assert-ContinuumFlutterMetadata $metadata 'flutter.bat'} 'pinned to Flutter 3.47.9'
        $metadata.frameworkVersion='3.47.9';$metadata.dartSdkVersion='3.12.9'
        Assert-Failure {Assert-ContinuumFlutterMetadata $metadata 'flutter.bat'} 'Dart >=3.13.0 <4.0.0'
        $metadata.dartSdkVersion='4.0.0'
        Assert-Failure {Assert-ContinuumFlutterMetadata $metadata 'flutter.bat'} 'Dart >=3.13.0 <4.0.0'
    }
    Check 'default build directory is accepted and custom output has exact remedy' {
        foreach($value in @($null,'','build','./build/')){Assert-ContinuumFlutterBuildDirectory @{'build-dir'=$value} $fixture}
        Assert-Failure {Assert-ContinuumFlutterBuildDirectory @{'build-dir'='custom'} $fixture} 'flutter config --build-dir=build'
        Assert-Failure {Assert-ContinuumFlutterBuildDirectory @{'build-dir'=$fixture} $fixture} 'invalid build-dir'
    }
    Check 'privilege, access, filesystem and unknown link failures retain distinct remedies' {
        $privilege=Get-ContinuumSymlinkFailureMessage @{kind='filesystem';code=1314;target='cache';message='privilege'} $fixture
        Assert-That ($privilege.Contains('start ms-settings:developers') -and $privilege.Contains('same Run-Continuum.cmd')) 'Developer Mode remedy is missing.'
        $access=Get-ContinuumSymlinkFailureMessage @{kind='filesystem';code=5;target='locked-cache';message='native access error'} $fixture
        Assert-That ($access.Contains('locked-cache') -and $access.Contains('native access error') -and -not $access.Contains('Developer Mode')) 'Access error was mislabeled or lost.'
        $filesystem=Get-ContinuumSymlinkFailureMessage @{kind='filesystem';code=1;target='other-drive';message='invalid function'} $fixture
        Assert-That ($filesystem.Contains('same local drive') -and -not $filesystem.Contains('Developer Mode')) 'Filesystem remedy is wrong.'
        $unknown=Get-ContinuumSymlinkFailureMessage @{kind='filesystem';code=999;target='target';message='vendor filesystem reason'} $fixture
        Assert-That ($unknown.Contains('999') -and $unknown.Contains('vendor filesystem reason')) 'Unknown native detail was lost.'
    }
    Check 'writable destination probe changes only its owned temporary file' {
        $marker=Join-Path $fixture 'existing.txt';Set-Content -LiteralPath $marker 'keep'
        Assert-ContinuumDirectoryWritable -Directory (Join-Path $fixture 'not-created/cache') -Purpose 'pub cache'
        Assert-That ((Get-Content -LiteralPath $marker -Raw).Trim() -ceq 'keep') 'Existing file changed.'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $fixture 'not-created'))) 'Probe created persistent cache directories.'
        Assert-That (@(Get-ChildItem -LiteralPath $fixture -Filter '.continuum-write-probe-*').Count -eq 0) 'Write probe leaked.'
    }
    Check 'pub cache resolves absent, empty, relative and absolute settings like Dart pub' {
        $project=New-Project 'cache project';$local=Join-Path $fixture 'profile'
        Assert-That ((Get-ContinuumPubCache $project -ConfiguredCache $null -LocalApplicationData $local) -ceq (Join-Path $local 'Pub/Cache')) 'Default Windows cache is wrong.'
        Assert-That ((Get-ContinuumPubCache $project -ConfiguredCache '' -LocalApplicationData $local) -ceq $project) 'Defined empty PUB_CACHE was treated as absent.'
        Assert-That ((Get-ContinuumPubCache $project -ConfiguredCache 'relative-cache' -LocalApplicationData $local) -ceq (Join-Path $project 'relative-cache')) 'Relative cache did not use pub CWD.'
        Assert-That ((Get-ContinuumPubCache $project -ConfiguredCache $fixture -LocalApplicationData $local) -ceq $fixture) 'Absolute cache changed.'
        Assert-Failure {Get-ContinuumPubCache $project -ConfiguredCache $null -LocalApplicationData $null} 'LOCALAPPDATA is missing'
    }
    Check 'empty NativeDesktop result continues to one valid BuildTools installation' {
        $install=Join-Path $fixture 'Visual Studio Build Tools'
        $cmake=Join-Path $install 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $cmake) -Force)
        Set-Content -LiteralPath $cmake 'inert fixture'
        foreach($relative in @('VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt',
            'VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe','VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/link.exe',
            'VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/lib.exe','VC/Tools/MSVC/14.44.35207/include/vcruntime.h',
            'VC/Tools/MSVC/14.44.35207/lib/x64/libcmt.lib')){
            $path=Join-Path $install $relative
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            Set-Content -LiteralPath $path 'inert fixture'
        }
        Set-Content -LiteralPath (Join-Path $install 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt') '14.44.35207'
        $vendor=Join-Path $fixture 'vswhere.exe';Set-Content -LiteralPath $vendor 'inert fixture'
        $script:vsCalls=[Collections.Generic.List[string]]::new()
        $script:vsResult=@(@{installationPath=$install;isComplete=$true;isLaunchable=$true}) | ConvertTo-Json -AsArray -Compress
        function Invoke-ContinuumBuildProcess {
            param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds)
            $script:vsCalls.Add(($ArgumentList -join ' '))
            return [pscustomobject]@{ExitCode=0;Stderr='';Stdout=if($script:vsCalls.Count -eq 1){'[]'}else{$script:vsResult}}
        }
        $actual=Get-ContinuumVisualStudioInstallation -VswhereExecutable $vendor -WorkingDirectory $fixture
        Assert-That ($actual -ceq $install -and $script:vsCalls.Count -eq 2) 'BuildTools fallback did not select the single installation.'
        Assert-That ($script:vsCalls[0].Contains('Workload.NativeDesktop') -and $script:vsCalls[1].Contains('Workload.VCTools')) 'Flutter workload search order changed.'
    }
    Check 'incomplete and reboot-required Visual Studio installations give separate recovery' {
        $vendor=Join-Path $fixture 'vswhere.exe'
        function Invoke-ContinuumBuildProcess {param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds);[pscustomobject]@{ExitCode=0;Stderr='';Stdout=$script:vsResult}}
        $script:vsResult='[{"isRebootRequired":true}]'
        Assert-Failure {Get-ContinuumVisualStudioInstallation $vendor $fixture} 'Restart Windows'
        $script:vsResult='[{"isComplete":false}]'
        Assert-Failure {Get-ContinuumVisualStudioInstallation $vendor $fixture} 'Finish or repair'
    }
    Check 'a component registration cannot hide missing MSVC compiler files' {
        $vendor=Join-Path $fixture 'vswhere.exe';$install=Join-Path $fixture 'Visual Studio Build Tools'
        $script:vsResult=@(@{installationPath=$install}) | ConvertTo-Json -AsArray -Compress
        function Invoke-ContinuumBuildProcess {param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds);[pscustomobject]@{ExitCode=0;Stderr='';Stdout=$script:vsResult}}
        Remove-Item -LiteralPath (Join-Path $install 'VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe')
        Assert-Failure {Get-ContinuumVisualStudioInstallation $vendor $fixture} 'x64 C++ toolset is incomplete'
    }
    Check 'Windows SDK requires real headers, x64 libraries and resource compiler' {
        $windowsSdk=Join-Path $fixture 'Windows Kits';$version='10.0.26100.0'
        foreach($relative in @("Include/$version/um/Windows.h","Include/$version/shared/winapifamily.h", "Include/$version/ucrt/stdio.h",
            "Lib/$version/um/x64/kernel32.lib","Lib/$version/ucrt/x64/ucrt.lib","bin/$version/x64/rc.exe")){
            $path=Join-Path $windowsSdk $relative
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            Set-Content -LiteralPath $path 'inert fixture'
        }
        Assert-That ((Get-ContinuumWindowsSdkVersion $windowsSdk) -ceq $version) 'Complete Windows SDK fixture was rejected.'
        Remove-Item -LiteralPath (Join-Path $windowsSdk "bin/$version/x64/rc.exe")
        Assert-Failure {Get-ContinuumWindowsSdkVersion $windowsSdk} 'is incomplete'
        Assert-Failure {Get-ContinuumWindowsSdkVersion ''} 'was not found'
    }
    Check 'one preflight report retains link privilege, C++, SDK and WSH failures and stops the build' {
        # Vendor/OS failures are fixtures, not a Windows platform override.
        # The production fixed-order aggregator and message rendering run here.
        $project=New-Project 'aggregate failures'
        $fakeSdk=Join-Path $fixture 'aggregate Flutter SDK'
        foreach($relative in @('bin/cache/dart-sdk/bin/dart.exe','packages/flutter_tools/.dart_tool/package_config.json')){
            $path=Join-Path $fakeSdk $relative
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            Set-Content -LiteralPath $path 'vendor fixture; not executed'
        }
        $script:aggregateSdk=$fakeSdk
        $script:aggregateChecks=[Collections.Generic.List[string]]::new()
        function Get-Command {param($Name,$CommandType,$ErrorAction);[pscustomobject]@{Source=(Join-Path $fixture $Name)}}
        function Invoke-ContinuumBuildProcess {
            param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds)
            $stdout=switch(Split-Path -Leaf $FilePath){
                'git.exe'{'git version 2.50.0'}
                'node.exe'{'v22.0.0'}
                'flutter.bat'{
                    if($ArgumentList -contains '--version'){
                        @{frameworkVersion='3.47.9';dartSdkVersion='3.13.7';flutterRoot=$script:aggregateSdk} | ConvertTo-Json -Compress
                    }else{'{}'}
                }
            }
            [pscustomobject]@{ExitCode=0;Stdout=$stdout;Stderr=''}
        }
        function Get-ContinuumPubCache {param($ProjectDirectory);return $fixture}
        function Invoke-ContinuumSymlinkProbe {
            param($DartExecutable,$PackageConfiguration,$ProjectDirectory,$TargetDirectories,$GlobalWindowsSetting)
            $script:aggregateChecks.Add('links')
            throw (Get-ContinuumSymlinkFailureMessage @{kind='filesystem';code=1314;message='privilege not held';target='cache'} $ProjectDirectory)
        }
        function Get-ContinuumVisualStudioInstallation {
            param($VswhereExecutable,$WorkingDirectory)
            $script:aggregateChecks.Add('visual-studio')
            throw 'Install Desktop development with C++ in Visual Studio Installer.'
        }
        function Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction);return $null}
        function Get-ContinuumWindowsSdkVersion {
            param($Directory)
            $script:aggregateChecks.Add('windows-sdk')
            throw 'Add a Windows SDK through Visual Studio Installer.'
        }
        function Assert-ContinuumWindowsScriptHost {
            param($ProjectDirectory)
            $script:aggregateChecks.Add('script-host')
            throw 'Enable the Windows VBScript optional feature.'
        }
        $buildStarted=$false;$failure=''
        try{
            Get-ContinuumWindowsBuildTools -ProjectDirectory $project -OutputDirectory $fixture | Out-Null
            $buildStarted=$true
        }catch{$failure=$_.Exception.Message}
        Assert-That (-not $buildStarted) 'A build could start after a failed preflight.'
        Assert-That (($script:aggregateChecks -join ',') -ceq 'links,visual-studio,windows-sdk,script-host') 'An early prerequisite failure suppressed independent checks.'
        Assert-That ($failure.Contains('4 issue(s)') -and $failure.Contains('start ms-settings:developers') -and
            $failure.Contains('Desktop development with C++') -and $failure.Contains('Add a Windows SDK') -and
            $failure.Contains('VBScript optional feature')) "Independent remedies were lost: $failure"
    }
    Check 'missing Flutter still reports independent tools and SDK prerequisites' {
        $project=New-Project 'missing build tools'
        function Get-Command {param($Name,$CommandType,$ErrorAction);return $null}
        function Get-ContinuumPubCache {param($ProjectDirectory);return $fixture}
        function Get-ContinuumVisualStudioInstallation {param($VswhereExecutable,$WorkingDirectory);throw 'Visual Studio C++ workload missing.'}
        function Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction);return $null}
        function Get-ContinuumWindowsSdkVersion {param($Directory);throw 'Windows SDK missing.'}
        function Assert-ContinuumWindowsScriptHost {param($ProjectDirectory);throw 'Windows VBScript missing.'}
        $failure='';try{Get-ContinuumWindowsBuildTools -ProjectDirectory $project | Out-Null}catch{$failure=$_.Exception.Message}
        Assert-That ($failure.Contains("'flutter.bat'") -and $failure.Contains("'git.exe'") -and $failure.Contains("'node.exe'") -and
            $failure.Contains('Visual Studio C++ workload missing') -and $failure.Contains('Windows SDK missing') -and
            $failure.Contains('Plugin-link capability could not be checked')) "Missing SDK hid independent checks or claimed an unrun link probe: $failure"
    }
    Check 'WSH probe requires its distinct exit code, disables dialogs and removes only its owned script' {
        $project=New-Project 'script host probe';$hostFile=Join-Path $fixture 'wscript.exe'
        Set-Content -LiteralPath $hostFile 'vendor fixture; never execute'
        $script:wshExit=17;$script:wshScript=''
        function Invoke-ContinuumBuildProcess {
            param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds)
            $script:wshScript=$ArgumentList[-1]
            Assert-That ($ArgumentList -contains '//B' -and $ArgumentList -contains '//T:10' -and $TimeoutSeconds -eq 15) 'WSH can display a blocking dialog or run without a deadline.'
            Assert-That ((Get-Content -LiteralPath $script:wshScript -Raw).Trim() -ceq 'WScript.Quit 17') 'WSH probe ran more than its harmless exit check.'
            [pscustomobject]@{ExitCode=$script:wshExit;Stdout='';Stderr=''}
        }
        Assert-That ((Assert-ContinuumWindowsScriptHost -ProjectDirectory $project -HostExecutable $hostFile) -ceq $hostFile) 'Successful WSH result lost its executable.'
        Assert-That (-not (Test-Path -LiteralPath $script:wshScript)) 'Successful WSH probe leaked its script.'
        $script:wshExit=0
        Assert-Failure {Assert-ContinuumWindowsScriptHost -ProjectDirectory $project -HostExecutable $hostFile} 'VBScript optional feature'
        Assert-That (-not (Test-Path -LiteralPath $script:wshScript)) 'Failed WSH probe leaked its script.'
    }

    $sdk=$env:CONTINUUM_TEST_FLUTTER_SDK
    if(-not $sdk){
        $flutter=Get-Command ($IsWindows ? 'flutter.bat' : 'flutter') -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if($flutter){$sdk=Split-Path -Parent (Split-Path -Parent $flutter.Source)}
    }
    $dart=if($sdk){Join-Path $sdk ('bin/cache/dart-sdk/bin/'+($IsWindows ? 'dart.exe' : 'dart'))}else{''}
    $packages=if($sdk){Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'}else{''}
    if($dart -and (Test-Path -LiteralPath $dart -PathType Leaf) -and (Test-Path -LiteralPath $packages -PathType Leaf)){
        Check 'real Dart creates and removes links with absent environment override and Unicode source paths' {
            $project=New-Project 'probe source [review] élan 仓库'
            $cache=Join-Path $fixture 'pub cache';[void](New-Item -ItemType Directory -Path $cache -Force)
            $marker=Join-Path $cache 'keep.txt';Set-Content -LiteralPath $marker 'unchanged'
            $result=Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -TargetDirectories @($sdk,$cache) -WindowsEnvironment $null
            Assert-That ($result -isnot [array] -and $result.LinkCount -eq 3) 'Actual Dart did not verify all three targets.'
            Assert-That ((Get-Content -LiteralPath $marker -Raw).Trim() -ceq 'unchanged') 'Link probe changed a target.'
            Assert-ProbeClean $project
        }
        Check 'real YAML local true overrides global and environment false' {
            $project=New-Project 'local enabled' "name: fixture`nflutter:`n  config:`n    enable-windows-desktop: true`n"
            $result=Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -GlobalWindowsSetting $false -WindowsEnvironment 'false'
            Assert-That ($result.LinkCount -eq 1) 'Project feature precedence changed.'
            Assert-ProbeClean $project
        }
        Check 'real YAML global true overrides environment false' {
            $project=New-Project 'global enabled'
            $result=Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -GlobalWindowsSetting $true -WindowsEnvironment 'false'
            Assert-That ($result.LinkCount -eq 1) 'Global feature precedence changed.'
            Assert-ProbeClean $project
        }
        Check 'real YAML local, global and environment disabling report the effective source' {
            $project=New-Project 'local disabled' "name: fixture`nflutter:`n  config:`n    enable-windows-desktop: false`n"
            Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -GlobalWindowsSetting $true -WindowsEnvironment 'true'} 'pubspec.yaml'
            Assert-ProbeClean $project
            $project=New-Project 'global disabled'
            Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -GlobalWindowsSetting $false -WindowsEnvironment 'true'} 'flutter config --enable-windows-desktop'
            Assert-ProbeClean $project
            $project=New-Project 'environment disabled'
            Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -WindowsEnvironment 'false'} 'FLUTTER_WINDOWS'
            Assert-ProbeClean $project
        }
        Check 'real YAML invalid feature type retains configuration error and cleans up' {
            $project=New-Project 'invalid config' "name: fixture`nflutter:`n  config:`n    enable-windows-desktop: 'false'`n"
            Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -WindowsEnvironment $null} 'must be a boolean'
            Assert-ProbeClean $project
        }
        Check 'real Dart missing link target retains filesystem detail and cleans up' {
            $project=New-Project 'missing cache'
            Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -TargetDirectories @((Join-Path $fixture 'does-not-exist')) -WindowsEnvironment $null} 'Probe target directory does not exist'
            Assert-ProbeClean $project
        }
        Check 'probe refuses a generated ancestor file before running Dart' {
            $project=New-Project 'blocked generated directory';Set-Content -LiteralPath (Join-Path $project 'windows') 'not a directory'
            Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -WindowsEnvironment $null} 'file or linked directory'
            Assert-ProbeClean $project
        }
        Check 'probe refuses a generated ancestor link without touching its external target' {
            $project=New-Project 'linked generated directory'
            $outside=Join-Path $fixture 'outside';[void](New-Item -ItemType Directory -Path $outside -Force)
            $link=Join-Path $project 'windows'
            try{
                [void](New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop)
                Assert-Failure {Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages -ProjectDirectory $project -WindowsEnvironment $null} 'file or linked directory'
                Assert-That (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'Probe traversed the linked directory.'
            }finally{if(Test-Path -LiteralPath $link){(Get-Item -LiteralPath $link -Force).Delete()}}
        }
    }else{
        $skipped++
        Write-Host 'SKIP real Dart filesystem/config probes: set CONTINUUM_TEST_FLUTTER_SDK to an initialized Flutter 3.47.9 SDK.'
    }
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "Windows build prerequisites: $passed passed, $failed failed, $skipped skipped."
if($failed){throw "$failed prerequisite regression(s) failed."}
