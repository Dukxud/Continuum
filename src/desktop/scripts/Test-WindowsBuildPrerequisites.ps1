# Read-only tool discovery and disposable capability probes for the pinned
# Windows build. No registry/config changes, SDK installation, or elevation.

function ConvertFrom-ContinuumPrerequisiteJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,
          [Parameter(Mandatory)][string]$Description,
          [ValidateSet('Object','Array','Any')][string]$RootKind='Any',
          [string]$RequiredProperty='')
    if($Text.Length -gt 1MB){throw "$Description returned unexpectedly large output; its JSON response cannot be verified."}
    $found=$null;$hasFound=$false;$attempts=0
    # Flutter can print bootstrap/update text before its machine-readable JSON.
    # Locate balanced JSON, respecting quoted braces, instead of assuming that
    # either the first line or the last line is the complete response.
    for($start=0;$start -lt $Text.Length;$start++){
        if($Text[$start] -notin @('{','[')){continue}
        if(++$attempts -gt 64){break}
        $stack=[Collections.Generic.Stack[char]]::new()
        $quoted=$false;$escaped=$false
        for($at=$start;$at -lt $Text.Length;$at++){
            $character=$Text[$at]
            if($quoted){
                if($escaped){$escaped=$false}
                elseif($character -eq '\'){$escaped=$true}
                elseif($character -eq '"'){$quoted=$false}
                continue
            }
            if($character -eq '"'){$quoted=$true;continue}
            if($character -in @('{','[')){$stack.Push($character);continue}
            if($character -notin @('}',']')){continue}
            if(-not $stack.Count){break}
            $opening=$stack.Pop()
            if(($opening -eq '{' -and $character -ne '}') -or
               ($opening -eq '[' -and $character -ne ']')){break}
            if(-not $stack.Count){
                try{
                    $value=$Text.Substring($start,$at-$start+1) | ConvertFrom-Json -AsHashtable -NoEnumerate -Depth 100 -ErrorAction Stop
                    $object=$value -is [Collections.IDictionary]
                    if(($RootKind -eq 'Any' -or ($RootKind -eq 'Object' -and $object) -or
                        ($RootKind -eq 'Array' -and $value -is [array])) -and
                       (-not $RequiredProperty -or ($object -and $value.Contains($RequiredProperty)))){
                        $found=$value;$hasFound=$true
                    }
                    $start=$at
                    break
                }catch{break}
            }
        }
    }
    if($hasFound){return ,$found}
    throw "$Description did not return valid JSON. Run the reported tool directly to inspect its installation."
}

function Assert-ContinuumBuildPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory)
    $project=[IO.Path]::GetFullPath($ProjectDirectory)
    # Exact Flutter 3.47.9 windows/build_windows.dart MSBuild restriction.
    $unsupported="'#!`$^&*=|,;<>?"
    foreach($character in $unsupported.ToCharArray()){
        if($project.Contains($character)){
            throw "The source path contains '$character', which Flutter's Windows/MSBuild build cannot use: $project. Extract the complete source to a path such as C:\dev\Continuum and run Run-Continuum.cmd there. Spaces are supported."
        }
    }
    if(-not (Test-Path -LiteralPath $project -PathType Container)){
        throw "Flutter source directory is missing: $project"
    }
    return $project
}

function Assert-ContinuumBuildHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OperatingSystemArchitecture,
          [Parameter(Mandatory)][string]$ProcessArchitecture,
          [Parameter(Mandatory)][version]$PowerShellVersion)
    if($PowerShellVersion -lt [version]'7.4'){
        throw "Continuum source builds require PowerShell 7.4 or newer; this process is $PowerShellVersion. Install a current x64 PowerShell 7 release, put it on PATH, and reopen Run-Continuum.cmd."
    }
    if($OperatingSystemArchitecture -ine 'X64' -or $ProcessArchitecture -ine 'X64'){
        throw "This Continuum build produces Windows x64 only. Detected OS $OperatingSystemArchitecture and PowerShell process $ProcessArchitecture. Build from x64 PowerShell on x64 Windows. ARM64 and 32-bit builds are not provided by this package."
    }
}

function Assert-ContinuumFlutterMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Metadata,
          [Parameter(Mandatory)][string]$FlutterExecutable)
    $version=[string]$Metadata['frameworkVersion']
    if(-not $version){$version=[string]$Metadata['flutterVersion']}
    if($version -cne '3.47.9'){
        throw "This source is pinned to Flutter 3.47.9; '$FlutterExecutable' reported '$version'. Select the Flutter 3.47.9 SDK bin directory on PATH, then run Run-Continuum.cmd again. The launcher does not upgrade or replace SDKs."
    }
    $dart=[string]$Metadata['dartSdkVersion']
    $match=[regex]::Match($dart,'^(\d+)\.(\d+)\.(\d+)(?:\s|$|-)')
    if(-not $match.Success -or [int]$match.Groups[1].Value -ne 3 -or [int]$match.Groups[2].Value -lt 13){
        throw "The source requires Dart >=3.13.0 <4.0.0, but Flutter reported '$dart'. Use the complete Flutter 3.47.9 SDK, including its bundled Dart SDK."
    }
    $sdk=[string]$Metadata['flutterRoot']
    if(-not $sdk -or -not [IO.Path]::IsPathFullyQualified($sdk) -or
       -not (Test-Path -LiteralPath $sdk -PathType Container)){
        throw 'Flutter did not report an existing absolute SDK root. Check flutter --version --machine and the flutter.bat selected by PATH.'
    }
    return [IO.Path]::GetFullPath($sdk)
}

function Assert-ContinuumFlutterBuildDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Configuration,
          [Parameter(Mandatory)][string]$ProjectDirectory)
    $configured=$Configuration['build-dir']
    if($null -eq $configured -or $configured -ceq ''){return}
    if($configured -isnot [string] -or [IO.Path]::IsPathFullyQualified($configured)){
        throw 'Flutter has an invalid build-dir setting. Run: flutter config --build-dir=build, then reopen Run-Continuum.cmd.'
    }
    $actual=[IO.Path]::GetFullPath((Join-Path $ProjectDirectory $configured))
    $expected=[IO.Path]::GetFullPath((Join-Path $ProjectDirectory 'build'))
    if(-not [string]::Equals($actual.TrimEnd([char[]]@('/','\')),$expected,[StringComparison]::OrdinalIgnoreCase)){
        throw "Flutter's build-dir is '$configured'; this package uses 'build'. Run: flutter config --build-dir=build, then reopen Run-Continuum.cmd. The launcher leaves your Flutter configuration unchanged."
    }
}

function Get-ContinuumExistingDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while(-not (Test-Path -LiteralPath $current -PathType Container)){
        if(Test-Path -LiteralPath $current){throw "A file blocks the required directory: $current"}
        $parent=[IO.Directory]::GetParent($current)
        if(-not $parent){throw "Cannot find an existing parent directory for: $Path"}
        $current=$parent.FullName
    }
    return $current
}

function Assert-ContinuumDirectoryWritable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Purpose)
    $parent=Get-ContinuumExistingDirectory $Directory
    $probe=Join-Path $parent ('.continuum-write-probe-'+[guid]::NewGuid().ToString('N'))
    $created=$false
    try{
        $stream=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $created=$true
        try{$stream.WriteByte(42);$stream.Flush()}finally{$stream.Dispose()}
    }catch{throw "Cannot write the $Purpose directory '$Directory': $($_.Exception.Message). Use a writable local folder and retry Run-Continuum.cmd."}
    finally{if($created){[IO.File]::Delete($probe)}}
}

function Get-ContinuumSymlinkFailureMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Failure,
          [Parameter(Mandatory)][string]$ProjectDirectory)
    $code=$Failure['code']
    $detail=[string]$Failure['message']
    $target=[string]$Failure['target']
    if($Failure['kind'] -eq 'windows-disabled'){
        $origin=[string]$Failure['source']
        if($origin -eq 'pubspec.yaml'){
            return 'Windows desktop builds are disabled by flutter.config.enable-windows-desktop in pubspec.yaml. Set that project option to true or restore the complete source archive, then run Run-Continuum.cmd again.'
        }
        if($origin -eq 'FLUTTER_WINDOWS'){
            return 'Windows desktop builds are disabled by the FLUTTER_WINDOWS environment variable. Remove that override or set it to true, then reopen Run-Continuum.cmd.'
        }
        return 'Windows desktop builds are disabled in Flutter. Run: flutter config --enable-windows-desktop, then reopen Run-Continuum.cmd. The launcher has not changed this setting.'
    }
    if($Failure['kind'] -eq 'configuration'){
        return "Flutter project configuration is invalid: $detail"
    }
    if($code -eq 1314){
        return "Windows denied the symbolic links required by Flutter plugins in '$ProjectDirectory' (error 1314). Open Settings by running: start ms-settings:developers. Enable Developer Mode, then double-click the same Run-Continuum.cmd again. If Windows manages that setting through your organization, ask its administrator to permit symbolic-link creation for your account. No build or OS setting was changed."
    }
    if($code -eq 5){
        return "Windows denied access while testing a Flutter plugin link in '$ProjectDirectory' to '$target' (error 5): $detail. Check folder access, or extract the source to a writable local folder such as C:\dev\Continuum, then run Run-Continuum.cmd again."
    }
    if($code -eq 1){
        return "The filesystem rejected a Flutter plugin link in '$ProjectDirectory' to '$target' (error 1): $detail. Try placing the source, Flutter SDK and pub cache on the same local drive with symbolic-link support, then rerun Run-Continuum.cmd."
    }
    return "Flutter plugin-link capability failed in '$ProjectDirectory' for '$target' (error $code): $detail. Check the reported filesystem/path error before rerunning Run-Continuum.cmd."
}

function Invoke-ContinuumSymlinkProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DartExecutable,
          [Parameter(Mandatory)][string]$PackageConfiguration,
          [Parameter(Mandatory)][string]$ProjectDirectory,
          [string[]]$TargetDirectories=@(),
          $GlobalWindowsSetting=$null,
          [AllowNull()]$WindowsEnvironment=[Environment]::GetEnvironmentVariable('FLUTTER_WINDOWS'))
    $project=[IO.Path]::GetFullPath($ProjectDirectory)
    $parent=$project
    # Test the actual existing ancestor of Flutter's plugin-link directory.
    # A stale file/junction there must not move this probe outside the project.
    foreach($part in @('','windows','flutter','ephemeral','.plugin_symlinks')){
        if($part){$candidate=Join-Path $parent $part}else{$candidate=$parent}
        if(-not (Test-Path -LiteralPath $candidate)){break}
        $item=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw "Flutter's generated Windows path is a file or linked directory: $candidate. Use a complete source folder with ordinary directories before building."
        }
        $parent=$candidate
    }
    $probe=Join-Path $parent ('.continuum-symlink-probe-'+[guid]::NewGuid().ToString('N'))
    $created=$false
    try{
        try{[void](New-Item -ItemType Directory -Path $probe -ErrorAction Stop);$created=$true}
        catch{throw "Cannot create the Flutter capability probe in '$parent': $($_.Exception.Message). Extract the source into a writable local folder and run Run-Continuum.cmd there."}
        $script=Join-Path $probe 'probe.dart'
        $context=Join-Path $probe 'context.json'
        @{
            project=$project;targets=@($TargetDirectories)
            globalWindows=$GlobalWindowsSetting;windowsEnvironment=$WindowsEnvironment
        } | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $context -Encoding utf8
        @'
import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  final contextFile = File(arguments.single);
  final root = contextFile.parent;
  final context = jsonDecode(contextFile.readAsStringSync()) as Map<String, dynamic>;
  final links = <Link>[];
  var target = '';
  void fail(Map<String, Object?> detail) {
    stdout.writeln(jsonEncode({'ok': false, ...detail}));
    exitCode = 1;
  }
  try {
    final manifest = loadYaml(File('${context['project']}/pubspec.yaml').readAsStringSync());
    final flutter = manifest is Map ? manifest['flutter'] : null;
    final config = flutter is Map ? flutter['config'] : null;
    if (config != null && config is! Map) {
      throw const FormatException('flutter.config in pubspec.yaml must be a map.');
    }
    final local = config is Map ? config['enable-windows-desktop'] : null;
    final global = context['globalWindows'];
    if (local != null && local is! bool) {
      throw const FormatException('flutter.config.enable-windows-desktop must be a boolean.');
    }
    if (global != null && global is! bool) {
      throw const FormatException('Global enable-windows-desktop must be a boolean.');
    }
    final environment = context['windowsEnvironment'] as String?;
    final enabled = local as bool? ?? global as bool? ??
        (environment == null ? true : environment.toLowerCase() == 'true');
    if (!enabled) {
      fail({'kind': 'windows-disabled', 'source': local != null ? 'pubspec.yaml' :
          global != null ? 'flutter config' : 'FLUTTER_WINDOWS'});
      return;
    }
    final localTarget = Directory('${root.path}/target')..createSync();
    final targets = <String>[localTarget.path, ...List<String>.from(context['targets'] as List)];
    for (var index = 0; index < targets.length; index++) {
      target = targets[index];
      if (!Directory(target).existsSync()) {
        throw FileSystemException('Probe target directory does not exist', target);
      }
      final link = Link('${root.path}/link-$index');
      links.add(link);
      // Identical filesystem operation to Flutter's plugin symlink creation.
      link.createSync(target, recursive: true);
      if (FileSystemEntity.typeSync(link.path, followLinks: false) != FileSystemEntityType.link ||
          !Directory(link.path).existsSync()) {
        throw FileSystemException('Created plugin link could not be followed', link.path);
      }
    }
    stdout.writeln(jsonEncode({'ok': true, 'links': links.length, 'targets': targets}));
  } on FileSystemException catch (error) {
    fail({'kind': 'filesystem', 'target': target,
        'code': error.osError?.errorCode, 'message': error.toString()});
  } catch (error) {
    fail({'kind': 'configuration', 'message': error.toString()});
  } finally {
    for (final link in links.reversed) {
      if (FileSystemEntity.typeSync(link.path, followLinks: false) == FileSystemEntityType.link) {
        link.deleteSync();
      }
    }
  }
}
'@ | Set-Content -LiteralPath $script -Encoding utf8
        $run=Invoke-ContinuumBuildProcess -FilePath $DartExecutable `
            -ArgumentList @(('--packages='+$PackageConfiguration),$script,$context) `
            -WorkingDirectory $project -TimeoutSeconds 30
        try{$result=ConvertFrom-ContinuumPrerequisiteJson -Text $run.Stdout -Description 'Flutter symbolic-link probe' -RootKind Object -RequiredProperty ok}
        catch{throw "Flutter capability probe could not run (exit $($run.ExitCode)): $($run.Stdout.Trim()) $($run.Stderr.Trim())"}
        if($result -isnot [Collections.IDictionary]){throw 'Flutter symbolic-link probe returned an invalid result.'}
        if($run.ExitCode -ne 0 -or $result['ok'] -ne $true){
            throw (Get-ContinuumSymlinkFailureMessage -Failure $result -ProjectDirectory $project)
        }
        return [pscustomobject]@{LinkCount=[int]$result['links'];Targets=@($result['targets'])}
    }finally{
        if($created -and (Test-Path -LiteralPath $probe)){
            $item=Get-Item -LiteralPath $probe -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                Write-Warning "Capability-probe cleanup refused a changed linked path: $probe"
            }else{
                # An interrupted Dart process may leave one of our links.
                # Remove links themselves before deleting only this owned tree.
                foreach($child in @(Get-ChildItem -LiteralPath $probe -Force)){
                    if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$child.Delete()}
                }
                Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction Stop
            }
        }
    }
}

function Get-ContinuumVisualStudioInstallation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$VswhereExecutable,
          [Parameter(Mandatory)][string]$WorkingDirectory)
    if(-not $VswhereExecutable -or -not (Test-Path -LiteralPath $VswhereExecutable -PathType Leaf)){
        throw 'Visual Studio Installer was not found. Install Visual Studio 2019 or newer (or Build Tools) with Desktop development with C++, MSVC x64/x86 tools, C++ CMake tools and a Windows 10/11 SDK; then retry Run-Continuum.cmd.'
    }
    # Same stable IDE / stable Build Tools / prerelease search as the pinned SDK.
    foreach($prerelease in @($false,$true)){
        foreach($workload in @('Microsoft.VisualStudio.Workload.NativeDesktop','Microsoft.VisualStudio.Workload.VCTools')){
            $arguments=@('-format','json','-products','*','-utf8','-latest','-version','16')
            if($prerelease){$arguments+='-prerelease'}
            $arguments+=@('-requires',$workload,'Microsoft.VisualStudio.Component.VC.Tools.x86.x64','Microsoft.VisualStudio.Component.VC.CMake.Project')
            $run=Invoke-ContinuumBuildProcess -FilePath $VswhereExecutable -ArgumentList $arguments -WorkingDirectory $WorkingDirectory -TimeoutSeconds 30
            if($run.ExitCode -ne 0){throw "Visual Studio detection failed (exit $($run.ExitCode)): $($run.Stderr.Trim())"}
            $installations=ConvertFrom-ContinuumPrerequisiteJson -Text $run.Stdout -Description 'Visual Studio Installer' -RootKind Array
            if($installations -isnot [array]){throw 'Visual Studio Installer returned an invalid installation list.'}
            if(-not $installations.Count){continue}
            $selected=$installations[0]
            if($selected -isnot [Collections.IDictionary]){throw 'Visual Studio Installer returned an invalid installation entry. Repair Visual Studio Installer and retry.'}
            if($selected['isRebootRequired'] -eq $true){throw 'Visual Studio requires a Windows restart to finish installation. Restart Windows, then run Run-Continuum.cmd again.'}
            if($selected['isComplete'] -eq $false -or $selected['isLaunchable'] -eq $false){
                throw 'Visual Studio installation is incomplete or unavailable. Finish or repair it in Visual Studio Installer, then retry Run-Continuum.cmd.'
            }
            $installation=[string]$selected['installationPath']
            if(-not [IO.Path]::IsPathFullyQualified($installation) -or $installation.Contains([char]0xFFFD)){
                throw 'Visual Studio Installer returned an unusable installation path. Repair the installation before building.'
            }
            $cmake=Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
            if(-not (Test-Path -LiteralPath $cmake -PathType Leaf) -or (Get-Item -LiteralPath $cmake).Length -eq 0){
                throw 'Visual Studio reports CMake installed, but cmake.exe is missing. Repair the C++ CMake tools for Windows component in Visual Studio Installer.'
            }
            $defaultTools=Join-Path $installation 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt'
            $toolsVersion=if(Test-Path -LiteralPath $defaultTools -PathType Leaf){[IO.File]::ReadAllText($defaultTools).Trim()}else{''}
            if($toolsVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$'){
                throw 'Visual Studio reports MSVC installed, but its default toolset is missing or invalid. Repair the MSVC x64/x86 build tools component in Visual Studio Installer.'
            }
            $toolsRoot=Join-Path $installation ('VC/Tools/MSVC/'+$toolsVersion)
            foreach($relative in @('bin/Hostx64/x64/cl.exe','bin/Hostx64/x64/link.exe','bin/Hostx64/x64/lib.exe',
                'include/vcruntime.h','lib/x64/libcmt.lib')){
                $required=Join-Path $toolsRoot $relative
                if(-not (Test-Path -LiteralPath $required -PathType Leaf) -or (Get-Item -LiteralPath $required).Length -eq 0){
                    throw "Visual Studio's x64 C++ toolset is incomplete: $required. Repair the MSVC x64/x86 build tools component in Visual Studio Installer."
                }
            }
            return $installation
        }
    }
    throw 'No supported Visual Studio installation has the required C++ workload and CMake tools. In Visual Studio Installer, install Desktop development with C++, MSVC x64/x86 build tools, C++ CMake tools for Windows and a Windows 10/11 SDK; then rerun Run-Continuum.cmd.'
}

function Get-ContinuumWindowsSdkVersion {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Directory)
    $include=if($Directory){Join-Path $Directory 'Include'}else{''}
    $versions=@(if($include -and (Test-Path -LiteralPath $include -PathType Container)){
        Get-ChildItem -LiteralPath $include -Directory | Where-Object Name -Match '^10\.\d+\.\d+\.\d+$' | Sort-Object { [version]$_.Name } -Descending
    })
    if(-not $versions.Count){
        throw 'A Windows 10/11 SDK was not found. Add a Windows SDK through Visual Studio Installer with the Desktop development with C++ workload, then rerun Run-Continuum.cmd.'
    }
    $version=$versions[0].Name
    foreach($relative in @("Include/$version/um/Windows.h","Include/$version/shared/winapifamily.h",
        "Include/$version/ucrt/stdio.h","Lib/$version/um/x64/kernel32.lib",
        "Lib/$version/ucrt/x64/ucrt.lib")){
        $required=Join-Path $Directory $relative
        if(-not (Test-Path -LiteralPath $required -PathType Leaf) -or (Get-Item -LiteralPath $required).Length -eq 0){
            throw "Windows SDK $version is incomplete: $required. Repair that Windows SDK in Visual Studio Installer, then run Run-Continuum.cmd again."
        }
    }
    $resourceCompilers=@((Join-Path $Directory "bin/$version/x64/rc.exe"),(Join-Path $Directory 'bin/x64/rc.exe'))
    if(-not @($resourceCompilers | Where-Object {(Test-Path -LiteralPath $_ -PathType Leaf) -and (Get-Item -LiteralPath $_).Length -gt 0}).Count){
        throw "Windows SDK $version is incomplete: its x64 resource compiler rc.exe is missing. Repair that Windows SDK in Visual Studio Installer, then run Run-Continuum.cmd again."
    }
    return $version
}

function Get-ContinuumPubCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory,
          [AllowNull()]$ConfiguredCache=[Environment]::GetEnvironmentVariable('PUB_CACHE'),
          [AllowNull()]$LocalApplicationData=[Environment]::GetEnvironmentVariable('LOCALAPPDATA'))
    if($null -ne $ConfiguredCache){
        # Dart pub returns a defined PUB_CACHE verbatim. In particular, an empty
        # or relative value resolves against pub's CWD, not the launcher root.
        if([string]$ConfiguredCache -ceq ''){return [IO.Path]::GetFullPath($ProjectDirectory)}
        return [IO.Path]::GetFullPath([string]$ConfiguredCache,$ProjectDirectory)
    }
    if([string]::IsNullOrWhiteSpace([string]$LocalApplicationData)){
        throw 'LOCALAPPDATA is missing; Dart cannot locate its Windows pub cache. Open the launcher in your normal Windows account.'
    }
    return Join-Path ([string]$LocalApplicationData) 'Pub/Cache'
}

function Assert-ContinuumWindowsScriptHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory,[string]$HostExecutable='')
    $remedy='Continuum scheduled jobs require Windows Script Host and the VBScript optional feature. Install or enable that Windows feature through Settings if it is missing; if organizational policy blocks it, ask its administrator to permit it. Reopen the same Run-Continuum.cmd afterward.'
    if(-not $HostExecutable){
        $system=[Environment]::SystemDirectory
        if($system){$HostExecutable=Join-Path $system 'wscript.exe'}
    }
    if(-not $HostExecutable -or -not (Test-Path -LiteralPath $HostExecutable -PathType Leaf)){
        throw "Windows Script Host (wscript.exe) was not found. $remedy"
    }
    $probe=Join-Path $ProjectDirectory ('.continuum-wsh-probe-'+[guid]::NewGuid().ToString('N')+'.vbs')
    $created=$false
    try{
        $stream=[IO.File]::Open($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $created=$true
        try{
            $bytes=[Text.Encoding]::ASCII.GetBytes("WScript.Quit 17`r`n")
            $stream.Write($bytes,0,$bytes.Length)
        }finally{$stream.Dispose()}
        $result=Invoke-ContinuumBuildProcess -FilePath $HostExecutable -ArgumentList @('//B','//Nologo','//T:10',$probe) `
            -WorkingDirectory $ProjectDirectory -TimeoutSeconds 15
        if($result.ExitCode -ne 17){
            throw "The harmless Windows VBScript probe returned exit $($result.ExitCode), expected 17. $($result.Stdout.Trim()) $($result.Stderr.Trim())"
        }
    }catch{throw "Windows Script Host capability check failed: $($_.Exception.Message) $remedy"}
    finally{if($created){[IO.File]::Delete($probe)}}
    return $HostExecutable
}

function Get-ContinuumWindowsBuildTools {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory,[string]$OutputDirectory='')
    # Check independent capabilities even when another prerequisite is absent.
    # The caller cannot start a build until this complete report succeeds.
    $issues=[Collections.Generic.List[string]]::new()
    $project=[IO.Path]::GetFullPath($ProjectDirectory)
    try{$project=Assert-ContinuumBuildPath $project}catch{$issues.Add('[Source path] '+$_.Exception.Message)}
    $tools=@{}
    foreach($name in @('flutter.bat','git.exe','node.exe')){
        $command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if(-not $command){
            $requirement=switch($name){'flutter.bat'{'Flutter 3.47.9'};'git.exe'{'Git 2.28 or newer'};'node.exe'{'Node.js 22 or newer'}}
            $issues.Add("[Required tool] '$name' is missing from PATH. Install $requirement and reopen Run-Continuum.cmd.")
        }else{$tools[$name]=$command.Source}
    }
    if($tools.ContainsKey('git.exe')){
        try{
            $git=Invoke-ContinuumBuildProcess -FilePath $tools['git.exe'] -ArgumentList @('--version') -WorkingDirectory $project
            $gitVersion=[regex]::Match($git.Stdout,'git version (\d+\.\d+\.\d+)')
            if($git.ExitCode -ne 0 -or -not $gitVersion.Success -or [version]$gitVersion.Groups[1].Value -lt [version]'2.28.0'){
                throw "Git 2.28 or newer is required by the source-build checks; '$($tools['git.exe'])' reported '$($git.Stdout.Trim())'. Update Git and reopen Run-Continuum.cmd."
            }
        }catch{$issues.Add('[Git] '+$_.Exception.Message)}
    }
    if($tools.ContainsKey('node.exe')){
        try{
            $node=Invoke-ContinuumBuildProcess -FilePath $tools['node.exe'] -ArgumentList @('--version') -WorkingDirectory $project
            $nodeVersion=[regex]::Match($node.Stdout.Trim(),'^v(\d+)\.\d+\.\d+$')
            if($node.ExitCode -ne 0 -or -not $nodeVersion.Success -or [int]$nodeVersion.Groups[1].Value -lt 22){
                throw "Node.js 22 or newer is required; '$($tools['node.exe'])' reported '$($node.Stdout.Trim())'. Update Node.js and reopen Run-Continuum.cmd."
            }
        }catch{$issues.Add('[Node.js] '+$_.Exception.Message)}
    }
    $sdk=$null;$dart=$null;$packages=$null;$metadata=$null;$configuration=$null;$probe=$null
    if($tools.ContainsKey('flutter.bat')){
        try{
            $version=Invoke-ContinuumBuildProcess -FilePath $tools['flutter.bat'] `
                -ArgumentList @('--suppress-analytics','--version','--machine') -WorkingDirectory $project -TimeoutSeconds 120
            if($version.ExitCode -ne 0){throw "Flutter version check failed (exit $($version.ExitCode)): $($version.Stdout.Trim()) $($version.Stderr.Trim())"}
            $metadata=ConvertFrom-ContinuumPrerequisiteJson -Text $version.Stdout -Description 'Flutter version check' -RootKind Object -RequiredProperty frameworkVersion
            $sdk=Assert-ContinuumFlutterMetadata -Metadata $metadata -FlutterExecutable $tools['flutter.bat']
            $dart=Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe'
            $packages=Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'
            foreach($required in @($dart,$packages)){
                if(-not (Test-Path -LiteralPath $required -PathType Leaf)){
                    throw "Flutter SDK is incomplete: $required. Repair or reinstall the complete Flutter 3.47.9 SDK, then retry."
                }
            }
        }catch{$issues.Add('[Flutter SDK] '+$_.Exception.Message);$sdk=$null;$dart=$null;$packages=$null}
        if($sdk){
            try{
                $configRun=Invoke-ContinuumBuildProcess -FilePath $tools['flutter.bat'] `
                    -ArgumentList @('--suppress-analytics','config','--machine') -WorkingDirectory $project -TimeoutSeconds 60
                if($configRun.ExitCode -ne 0){throw "Flutter configuration check failed (exit $($configRun.ExitCode)): $($configRun.Stdout.Trim()) $($configRun.Stderr.Trim())"}
                $configuration=ConvertFrom-ContinuumPrerequisiteJson -Text $configRun.Stdout -Description 'Flutter configuration check' -RootKind Object
            }catch{$issues.Add('[Flutter configuration] '+$_.Exception.Message)}
            if($null -ne $configuration){
                try{Assert-ContinuumFlutterBuildDirectory -Configuration $configuration -ProjectDirectory $project}
                catch{$issues.Add('[Flutter build directory] '+$_.Exception.Message)}
            }
        }
    }
    $cacheTarget=$null
    try{
        $cache=Get-ContinuumPubCache -ProjectDirectory $project
        Assert-ContinuumDirectoryWritable -Directory $cache -Purpose 'pub cache'
        $cacheTarget=Get-ContinuumExistingDirectory $cache
    }catch{$issues.Add('[Pub cache] '+$_.Exception.Message)}
    if($OutputDirectory){
        try{Assert-ContinuumDirectoryWritable -Directory $OutputDirectory -Purpose 'preview output'}
        catch{$issues.Add('[Preview output] '+$_.Exception.Message)}
    }
    if($sdk -and $null -ne $configuration){
        $targets=@($sdk);if($cacheTarget){$targets+=$cacheTarget}
        try{
            $probe=Invoke-ContinuumSymlinkProbe -DartExecutable $dart -PackageConfiguration $packages `
                -ProjectDirectory $project -TargetDirectories $targets -GlobalWindowsSetting $configuration['enable-windows-desktop']
        }catch{$issues.Add('[Windows plugin links] '+$_.Exception.Message)}
    }
    $visualStudio=$null;$sdkVersion=$null
    try{
        $programFiles=[Environment]::GetFolderPath('ProgramFilesX86')
        $vswhere=if($programFiles){Join-Path $programFiles 'Microsoft Visual Studio/Installer/vswhere.exe'}else{''}
        $visualStudio=Get-ContinuumVisualStudioInstallation -VswhereExecutable $vswhere -WorkingDirectory $project
    }catch{$issues.Add('[Visual Studio C++] '+$_.Exception.Message)}
    try{
        $sdkRegistry='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SDKs\Windows\v10.0'
        $windowsSdk=Get-ItemProperty -LiteralPath $sdkRegistry -Name InstallationFolder -ErrorAction SilentlyContinue
        $sdkVersion=Get-ContinuumWindowsSdkVersion -Directory $(if($windowsSdk){[string]$windowsSdk.InstallationFolder}else{''})
    }catch{$issues.Add('[Windows SDK] '+$_.Exception.Message)}
    $scriptHost=$null
    try{$scriptHost=Assert-ContinuumWindowsScriptHost -ProjectDirectory $project}
    catch{$issues.Add('[Windows Script Host] '+$_.Exception.Message)}
    if($issues.Count){
        $dependent=if(-not $sdk -or $null -eq $configuration){"`nPlugin-link capability could not be checked until the Flutter SDK/configuration issue above is resolved."}else{''}
        throw ("Windows build prerequisites are not ready ($($issues.Count) issue(s)). No build was started. Fix the listed items, then run the same Run-Continuum.cmd again:`n - "+($issues -join "`n - ")+$dependent)
    }
    return [pscustomobject]@{
        FlutterExecutable=$tools['flutter.bat'];DartExecutable=$dart
        PowerShellExecutable=(Join-Path $PSHOME 'pwsh.exe')
        GitExecutable=$tools['git.exe'];NodeExecutable=$tools['node.exe']
        Architecture='x64';VisualStudioInstallation=$visualStudio;WindowsSdkVersion=$sdkVersion
        WindowsScriptHostExecutable=$scriptHost
        FlutterVersion=[string]$metadata['frameworkVersion'];DartVersion=[string]$metadata['dartSdkVersion']
        VerifiedSymlinkTargets=$probe.Targets
    }
}

function Assert-ContinuumWindowsBuildPrerequisites {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory,[string]$OutputDirectory='')
    if(-not $IsWindows){throw 'Continuum Windows source builds require Windows x64.'}
    Assert-ContinuumBuildHost -OperatingSystemArchitecture ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) `
        -ProcessArchitecture ([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()) `
        -PowerShellVersion $PSVersionTable.PSVersion
    return Get-ContinuumWindowsBuildTools -ProjectDirectory $ProjectDirectory -OutputDirectory $OutputDirectory
}
