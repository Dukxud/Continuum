# Exercise real package copies and cleanup ownership without running a Windows
# build. Import only production function ASTs; keep the Windows guard intact.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$builder=Join-Path $root 'src/desktop/Build-WindowsPreview.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw $errors[0].Message}
foreach($name in @('Copy-ContinuumReleaseFiles','Test-ContinuumPackageParent','New-ContinuumPackageArchive')){
    $definition=$ast.Find({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$false)
    if(-not $definition){throw "Production package function is missing: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
}

$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-package-paths-'+[guid]::NewGuid().ToString('N'))
$passed=0
$failures=[Collections.Generic.List[string]]::new()
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Run-Case([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failures.Add($Name+': '+$_.Exception.Message);Write-Host "FAIL $Name — $($_.Exception.Message)"}
}
function New-FixtureFile([string]$Directory,[string]$Relative,[string]$Contents){
    $path=Join-Path $Directory $Relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path,$Contents)
    return $path
}
function Require-CopyFailure([string]$Source,[string]$Destination){
    $message=''
    try{Copy-ContinuumReleaseFiles -SourceDirectory $Source -DestinationDirectory $Destination}
    catch{$message=$_.Exception.Message}
    Require (-not [string]::IsNullOrWhiteSpace($message)) 'Invalid release input returned success.'
    Require (@(Get-ChildItem -LiteralPath $Destination -Force).Count -eq 0) 'Invalid release input changed the output.'
}
try{
    [void][IO.Directory]::CreateDirectory($fixture)
    $release=Join-Path $fixture 'checkout [review] Ω/Release'
    $destination=Join-Path $fixture 'package [verified] with spaces'
    [void][IO.Directory]::CreateDirectory($destination)
    [void](New-FixtureFile $release 'codex_resume_flutter.exe' 'correct inert runner')
    [void](New-FixtureFile $release 'data/flutter_assets/assets/nested [asset].bin' 'correct nested payload')
    # This sibling matches the old wildcard interpretation of [review]. It
    # must neither replace the intended payload nor leak into the package.
    $lookalike=Join-Path $fixture 'checkout r Ω/Release'
    [void](New-FixtureFile $lookalike 'unrelated.dll' 'wrong sibling')
    Run-Case 'literal spaces brackets and Unicode retain the actual release tree' {
        Copy-ContinuumReleaseFiles -SourceDirectory $release -DestinationDirectory $destination
        Require ([IO.File]::ReadAllText((Join-Path $destination 'codex_resume_flutter.exe')) -ceq 'correct inert runner') 'The intended runner was not copied.'
        Require ([IO.File]::ReadAllText((Join-Path $destination 'data/flutter_assets/assets/nested [asset].bin')) -ceq 'correct nested payload') 'Nested payload changed or was omitted.'
        Require (-not [IO.File]::Exists((Join-Path $destination 'unrelated.dll'))) 'Wildcard-matching sibling content entered the package.'
    }
    Run-Case 'hidden root files and nested hidden directories are retained' {
        $hiddenSource=Join-Path $fixture 'hidden source [keep]'
        $hiddenDestination=Join-Path $fixture 'hidden package [keep]'
        [void][IO.Directory]::CreateDirectory($hiddenDestination)
        $hiddenFile=New-FixtureFile $hiddenSource '.hidden-runtime.dat' 'hidden root data'
        $nestedFile=New-FixtureFile $hiddenSource '.hidden-assets/nested.dat' 'hidden nested data'
        if($IsWindows){
            [IO.File]::SetAttributes($hiddenFile,[IO.FileAttributes]::Hidden)
            [IO.File]::SetAttributes([IO.Path]::GetDirectoryName($nestedFile),[IO.FileAttributes]::Directory -bor [IO.FileAttributes]::Hidden)
        }
        Copy-ContinuumReleaseFiles -SourceDirectory $hiddenSource -DestinationDirectory $hiddenDestination
        Require ([IO.File]::ReadAllText((Join-Path $hiddenDestination '.hidden-runtime.dat')) -ceq 'hidden root data') 'Hidden root payload was omitted.'
        Require ([IO.File]::ReadAllText((Join-Path $hiddenDestination '.hidden-assets/nested.dat')) -ceq 'hidden nested data') 'Hidden nested payload was omitted.'
    }
    $invalidOutput=Join-Path $fixture 'invalid input output'
    [void][IO.Directory]::CreateDirectory($invalidOutput)
    Run-Case 'a missing release cannot become an empty successful package' {
        Require-CopyFailure (Join-Path $fixture 'missing release [never-created]') $invalidOutput
    }
    Run-Case 'an empty release cannot become an empty successful package' {
        $empty=Join-Path $fixture 'empty release'
        [void][IO.Directory]::CreateDirectory($empty)
        Require-CopyFailure $empty $invalidOutput
    }
    Run-Case 'a file cannot be accepted as the release directory' {
        $file=New-FixtureFile $fixture 'not-a-release-directory' 'file input'
        Require-CopyFailure $file $invalidOutput
    }
    Run-Case 'Windows drive-root parents remain owned after trailing-separator normalization' {
        Require (Test-ContinuumPackageParent -ActualParent 'D:\' -ExpectedParent 'D:\') 'Drive root compared unequal to itself.'
        Require (Test-ContinuumPackageParent -ActualParent 'd:/' -ExpectedParent 'D:\') 'Equivalent drive-root separators or case compared unequal.'
    }
    Run-Case 'ordinary output parents accept trailing separators without losing their identity' {
        Require (Test-ContinuumPackageParent -ActualParent 'D:\Build Outputs [review]\' -ExpectedParent 'd:\build outputs [review]') 'Equivalent Windows output parents compared unequal.'
        Require (Test-ContinuumPackageParent -ActualParent '/tmp/preview/' -ExpectedParent '/tmp/preview') 'Equivalent portable output parents compared unequal.'
        Require (Test-ContinuumPackageParent -ActualParent '/' -ExpectedParent '/') 'Portable root compared unequal to itself.'
    }
    Run-Case 'cleanup ownership rejects other drives neighbors and nested output parents' {
        Require (-not (Test-ContinuumPackageParent -ActualParent 'E:\' -ExpectedParent 'D:\')) 'A different drive was accepted.'
        Require (-not (Test-ContinuumPackageParent -ActualParent 'D:\preview-other' -ExpectedParent 'D:\preview')) 'A neighboring output folder was accepted.'
        Require (-not (Test-ContinuumPackageParent -ActualParent 'D:\preview\nested' -ExpectedParent 'D:\preview')) 'A nested folder was accepted as the exact parent.'
    }
    Run-Case 'production archive preserves hidden Unicode and bracketed payload paths' {
        $source=Join-Path $fixture 'archive payload [verified] Ω'
        [void](New-FixtureFile $source 'data/assets/nested [asset] Ω.dat' 'visible Unicode payload')
        $hidden=New-FixtureFile $source '.hidden-runtime.dat' 'hidden root archive payload'
        $hiddenNested=New-FixtureFile $source '.hidden-assets/nested [asset] Ω.dat' 'hidden nested archive payload'
        if($IsWindows){
            [IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Hidden)
            [IO.File]::SetAttributes([IO.Path]::GetDirectoryName($hiddenNested),[IO.FileAttributes]::Directory -bor [IO.FileAttributes]::Hidden)
        }
        $output=Join-Path $fixture 'archive output [review] Ω'
        [void][IO.Directory]::CreateDirectory($output)
        $archive=Join-Path $output 'package [candidate] Ω.zip'
        New-ContinuumPackageArchive -SourceDirectory $source -DestinationPath $archive
        $extracted=Join-Path $fixture 'extracted archive [review] Ω'
        Expand-Archive -LiteralPath $archive -DestinationPath $extracted -ErrorAction Stop
        $package=Join-Path $extracted ([IO.Path]::GetFileName($source))
        Require ([IO.Directory]::Exists($package)) 'Archive lost its package root directory.'
        Require ([IO.File]::ReadAllText((Join-Path $package 'data/assets/nested [asset] Ω.dat')) -ceq 'visible Unicode payload') 'Visible Unicode/bracketed archive payload changed.'
        Require ([IO.File]::ReadAllText((Join-Path $package '.hidden-runtime.dat')) -ceq 'hidden root archive payload') 'Hidden root archive payload was dropped.'
        Require ([IO.File]::ReadAllText((Join-Path $package '.hidden-assets/nested [asset] Ω.dat')) -ceq 'hidden nested archive payload') 'Hidden nested archive payload was dropped.'
        Require (@(Get-ChildItem -LiteralPath $extracted -Force).Count -eq 1) 'Archive extracted outside its one package root.'
    }
    Run-Case 'archive creation refuses to overwrite an existing output file' {
        $source=Join-Path $fixture 'no overwrite source'
        [void](New-FixtureFile $source 'payload.dat' 'new payload')
        $archive=New-FixtureFile $fixture 'existing output [preserve].zip' 'previous output must remain byte-for-byte'
        $before=[IO.File]::ReadAllBytes($archive)
        $message=''
        try{New-ContinuumPackageArchive -SourceDirectory $source -DestinationPath $archive}
        catch{$message=$_.Exception.Message}
        Require (-not [string]::IsNullOrWhiteSpace($message)) 'Existing archive was overwritten without error.'
        Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($archive)) -ceq [Convert]::ToBase64String($before)) 'Existing output contents changed.'
    }
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
Write-Host "Package paths: $passed passed; $($failures.Count) failed."
if($failures.Count){foreach($failure in $failures){Write-Host $failure};exit 1}
