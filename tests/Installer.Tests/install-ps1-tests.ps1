$ErrorActionPreference = 'Stop'

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Installer = Join-Path $RepositoryRoot 'scripts/install.ps1'
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('orchestra-install-ps1-tests-' + [Guid]::NewGuid().ToString('N'))
$FixtureDirectory = Join-Path $TestRoot 'fixture'
$FixtureExecutable = Join-Path $FixtureDirectory 'orchestrate.exe'
$FixtureZip = Join-Path $FixtureDirectory 'orchestrate-win-x64.zip'
$ValidSums = Join-Path $FixtureDirectory 'SHA256SUMS.valid'
$InvalidSums = Join-Path $FixtureDirectory 'SHA256SUMS.invalid'
$OriginalPath = $env:Path
$global:OrchestraTestSums = $ValidSums
$global:OrchestraTestRequestedUrls = [Collections.Generic.List[string]]::new()
$global:OrchestraTestFixtureZip = $FixtureZip

function Fail([string]$Message) { throw "FAIL: $Message" }
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }
function Assert-Contains([string]$Text, [string]$Expected) { Assert-True ($Text.Contains($Expected)) "Expected output to contain '$Expected'. Actual: $Text" }
function Assert-SameFile([string]$Expected, [string]$Actual) {
    Assert-True (Test-Path -LiteralPath $Actual) "Expected '$Actual' to exist."
    Assert-True ((Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Actual -Algorithm SHA256).Hash) "Expected '$Actual' to match the fixture executable."
}

function global:Invoke-WebRequest {
    param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
    $global:OrchestraTestRequestedUrls.Add($Uri)
    if ($Uri.EndsWith('/SHA256SUMS', [StringComparison]::Ordinal)) {
        Copy-Item -LiteralPath $global:OrchestraTestSums -Destination $OutFile
    }
    else {
        Copy-Item -LiteralPath $global:OrchestraTestFixtureZip -Destination $OutFile
    }
}

function Invoke-Installer([string]$Name, [object[]]$Arguments) {
    $global:OrchestraTestRequestedUrls.Clear()
    try {
        $output = (& $Installer @Arguments 2>&1 | Out-String)
        return [pscustomobject]@{ Name = $Name; Status = 0; Output = $output; Urls = @($global:OrchestraTestRequestedUrls) }
    }
    catch {
        return [pscustomobject]@{ Name = $Name; Status = 1; Output = ($_ | Out-String); Urls = @($global:OrchestraTestRequestedUrls) }
    }
}

try {
    [IO.Directory]::CreateDirectory($FixtureDirectory) | Out-Null
    [IO.File]::WriteAllText($FixtureExecutable, 'orchestra-windows-test-payload')
    Compress-Archive -LiteralPath $FixtureExecutable -DestinationPath $FixtureZip
    $hash = (Get-FileHash -LiteralPath $FixtureZip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($ValidSums, "$hash  orchestrate-win-x64.zip`n")
    [IO.File]::WriteAllText($InvalidSums, "$('0' * 64)  orchestrate-win-x64.zip`n")

    $newDirectory = Join-Path $TestRoot 'new/bin'
    $global:OrchestraTestSums = $ValidSums
    $env:Path = $OriginalPath
    $newInstall = Invoke-Installer 'new-install' @('-InstallDir', $newDirectory)
    Assert-True ($newInstall.Status -eq 0) "New install failed: $($newInstall.Output)"
    Assert-SameFile $FixtureExecutable (Join-Path $newDirectory 'orchestrate.exe')
    Assert-Contains $newInstall.Output 'Checksum verified.'
    Assert-Contains $newInstall.Output 'orchestrate install --tools codex --dry-run'
    Assert-True (($newInstall.Urls -join "`n").Contains('https://github.com/jmpompeo/orchestra/releases/latest/download/orchestrate-win-x64.zip')) 'Latest stable asset URL was not requested.'

    $existingDirectory = Join-Path $TestRoot 'existing/bin'
    [IO.Directory]::CreateDirectory($existingDirectory) | Out-Null
    $existingTarget = Join-Path $existingDirectory 'orchestrate.exe'
    [IO.File]::WriteAllText($existingTarget, 'old-payload')
    $env:Path = "$existingDirectory;$existingDirectory;$OriginalPath"
    $upgrade = Invoke-Installer 'upgrade' @('-Version', 'v2.1.0')
    Assert-True ($upgrade.Status -eq 0) "Existing install upgrade failed: $($upgrade.Output)"
    Assert-SameFile $FixtureExecutable $existingTarget
    Assert-Contains $upgrade.Output "Updating the one orchestrate executable found on PATH: $existingTarget"

    $mismatchDirectory = Join-Path $TestRoot 'mismatch/bin'
    [IO.Directory]::CreateDirectory($mismatchDirectory) | Out-Null
    $mismatchTarget = Join-Path $mismatchDirectory 'orchestrate.exe'
    [IO.File]::WriteAllText($mismatchTarget, 'must-remain')
    $beforeHash = (Get-FileHash -LiteralPath $mismatchTarget -Algorithm SHA256).Hash
    $global:OrchestraTestSums = $InvalidSums
    $env:Path = $OriginalPath
    $mismatch = Invoke-Installer 'mismatch' @('-InstallDir', $mismatchDirectory, '-Version', 'v2.1.0')
    Assert-True ($mismatch.Status -eq 1) 'Checksum mismatch unexpectedly succeeded.'
    Assert-Contains $mismatch.Output 'SHA-256 mismatch'
    Assert-True ($beforeHash -eq (Get-FileHash -LiteralPath $mismatchTarget -Algorithm SHA256).Hash) 'Checksum mismatch changed the existing executable.'

    $ambiguousA = Join-Path $TestRoot 'ambiguous/a'
    $ambiguousB = Join-Path $TestRoot 'ambiguous/b'
    [IO.Directory]::CreateDirectory($ambiguousA) | Out-Null
    [IO.Directory]::CreateDirectory($ambiguousB) | Out-Null
    Copy-Item -LiteralPath $FixtureExecutable -Destination (Join-Path $ambiguousA 'orchestrate.exe')
    Copy-Item -LiteralPath $FixtureExecutable -Destination (Join-Path $ambiguousB 'orchestrate.exe')
    $global:OrchestraTestSums = $ValidSums
    $env:Path = "$ambiguousA;$ambiguousB;$OriginalPath"
    $ambiguous = Invoke-Installer 'ambiguous' @('-Version', 'v2.1.0')
    Assert-True ($ambiguous.Status -eq 1) 'Ambiguous PATH unexpectedly succeeded.'
    Assert-Contains $ambiguous.Output 'Found multiple orchestrate.exe entries on PATH'
    Assert-True ($ambiguous.Urls.Count -eq 0) 'Ambiguous PATH attempted a download.'

    $env:Path = $OriginalPath
    $invalidVersion = Invoke-Installer 'invalid-version' @('-Version', 'v2.bad.0', '-InstallDir', (Join-Path $TestRoot 'invalid/bin'))
    Assert-True ($invalidVersion.Status -eq 1) 'Invalid version unexpectedly succeeded.'
    Assert-Contains $invalidVersion.Output 'stable release tag in the form vX.Y.Z'
    Assert-True ($invalidVersion.Urls.Count -eq 0) 'Invalid version attempted a download.'

    Write-Output 'PASS: scripts/install.ps1 network-free installer tests'
}
finally {
    $env:Path = $OriginalPath
    Remove-Item function:global:Invoke-WebRequest -ErrorAction SilentlyContinue
    Remove-Variable OrchestraTestSums, OrchestraTestRequestedUrls, OrchestraTestFixtureZip -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
