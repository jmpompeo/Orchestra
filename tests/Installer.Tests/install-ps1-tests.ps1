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
$global:OrchestraTestExpectedArchiveUrl = $null
$global:OrchestraTestExpectedSumsUrl = $null
$script:OrchestraTestFailures = [Collections.Generic.List[string]]::new()

function Fail([string]$Message) { throw "FAIL: $Message" }
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }
function Assert-Contains([string]$Text, [string]$Expected) { Assert-True ($Text.Contains($Expected)) "Expected output to contain '$Expected'. Actual: $Text" }
function Assert-SameFile([string]$Expected, [string]$Actual) {
    Assert-True (Test-Path -LiteralPath $Actual) "Expected '$Actual' to exist."
    Assert-True ((Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Actual -Algorithm SHA256).Hash) "Expected '$Actual' to match the fixture executable."
}

function Assert-RequestedUrl([object[]]$Urls, [string]$Expected, [string]$Message) {
    Assert-True ($Urls -contains $Expected) $Message
}

function global:Invoke-WebRequest {
    param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
    $global:OrchestraTestRequestedUrls.Add($Uri)
    if ($Uri -eq $global:OrchestraTestExpectedSumsUrl) {
        Copy-Item -LiteralPath $global:OrchestraTestSums -Destination $OutFile
    }
    elseif ($Uri -eq $global:OrchestraTestExpectedArchiveUrl) {
        Copy-Item -LiteralPath $global:OrchestraTestFixtureZip -Destination $OutFile
    }
    else {
        throw "Unexpected download URL '$Uri'. Expected '$global:OrchestraTestExpectedArchiveUrl' or '$global:OrchestraTestExpectedSumsUrl'."
    }
}

function Invoke-Installer([string]$Name, [hashtable]$Parameters) {
    $global:OrchestraTestRequestedUrls.Clear()
    $global:OrchestraTestExpectedArchiveUrl = $null
    $global:OrchestraTestExpectedSumsUrl = $null
    $releaseUrl = $null
    if (-not $Parameters.ContainsKey('Version')) {
        $releaseUrl = 'https://github.com/jmpompeo/orchestra/releases/latest/download'
    }
    elseif ($Parameters.Version -match '^v\d+\.\d+\.\d+$') {
        $releaseUrl = "https://github.com/jmpompeo/orchestra/releases/download/$($Parameters.Version)"
    }
    if ($null -ne $releaseUrl) {
        $global:OrchestraTestExpectedArchiveUrl = "$releaseUrl/orchestrate-win-x64.zip"
        $global:OrchestraTestExpectedSumsUrl = "$releaseUrl/SHA256SUMS"
    }
    try {
        $output = (& $Installer @Parameters *>&1 | Out-String)
        return [pscustomobject]@{ Name = $Name; Status = 0; Output = $output; Urls = @($global:OrchestraTestRequestedUrls) }
    }
    catch {
        return [pscustomobject]@{ Name = $Name; Status = 1; Output = ($_ | Out-String); Urls = @($global:OrchestraTestRequestedUrls) }
    }
}

function Invoke-TestCase([string]$Name, [string]$SumsPath, [scriptblock]$Body) {
    $env:Path = $OriginalPath
    $global:OrchestraTestSums = $SumsPath
    $global:OrchestraTestRequestedUrls.Clear()
    $global:OrchestraTestExpectedArchiveUrl = $null
    $global:OrchestraTestExpectedSumsUrl = $null
    try {
        & $Body
        Write-Output "PASS: $Name"
    }
    catch {
        $detail = ($_ | Out-String).Trim()
        $script:OrchestraTestFailures.Add("${Name}: $detail")
        Write-Host "FAIL: ${Name}: $detail"
    }
    finally {
        $env:Path = $OriginalPath
        $global:OrchestraTestSums = $ValidSums
        $global:OrchestraTestRequestedUrls.Clear()
        $global:OrchestraTestExpectedArchiveUrl = $null
        $global:OrchestraTestExpectedSumsUrl = $null
    }
}

try {
    $edition = if ($null -eq $PSVersionTable.PSEdition) { 'Desktop' } else { $PSVersionTable.PSEdition }
    Write-Output "PowerShell: edition=$edition; version=$($PSVersionTable.PSVersion)"

    [IO.Directory]::CreateDirectory($FixtureDirectory) | Out-Null
    [IO.File]::WriteAllText($FixtureExecutable, 'orchestra-windows-test-payload')
    Compress-Archive -LiteralPath $FixtureExecutable -DestinationPath $FixtureZip
    $hash = (Get-FileHash -LiteralPath $FixtureZip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($ValidSums, "$hash  orchestrate-win-x64.zip`n")
    [IO.File]::WriteAllText($InvalidSums, "$('0' * 64)  orchestrate-win-x64.zip`n")

    Invoke-TestCase 'new-install' $ValidSums {
        $newDirectory = Join-Path $TestRoot 'new/bin'
        $newInstall = Invoke-Installer 'new-install' @{ InstallDir = $newDirectory }
        Assert-True ($newInstall.Status -eq 0) "New install failed: $($newInstall.Output)"
        Assert-SameFile $FixtureExecutable (Join-Path $newDirectory 'orchestrate.exe')
        Assert-Contains $newInstall.Output 'Checksum verified.'
        Assert-Contains $newInstall.Output 'orchestrate install --tools codex --dry-run'
        Assert-RequestedUrl $newInstall.Urls 'https://github.com/jmpompeo/orchestra/releases/latest/download/orchestrate-win-x64.zip' 'Latest stable asset URL was not requested.'
        Assert-RequestedUrl $newInstall.Urls 'https://github.com/jmpompeo/orchestra/releases/latest/download/SHA256SUMS' 'Latest stable checksum URL was not requested.'
        Assert-True ($newInstall.Urls.Count -eq 2) "New install made an unexpected number of download requests: $($newInstall.Urls.Count)."
    }

    Invoke-TestCase 'malformed-path' $ValidSums {
        $malformedPathDirectory = Join-Path $TestRoot 'malformed-path/bin'
        $env:Path = '"C:\malformed<path>";' + $OriginalPath
        $malformedPathInstall = Invoke-Installer 'malformed-path' @{ InstallDir = $malformedPathDirectory }
        Assert-True ($malformedPathInstall.Status -eq 0) "Install with malformed PATH entry failed: $($malformedPathInstall.Output)"
        Assert-SameFile $FixtureExecutable (Join-Path $malformedPathDirectory 'orchestrate.exe')
        Assert-Contains $malformedPathInstall.Output 'orchestrate install --tools codex --dry-run'
    }

    Invoke-TestCase 'upgrade' $ValidSums {
        $existingDirectory = Join-Path $TestRoot 'existing/bin'
        [IO.Directory]::CreateDirectory($existingDirectory) | Out-Null
        $existingTarget = Join-Path $existingDirectory 'orchestrate.exe'
        [IO.File]::WriteAllText($existingTarget, 'old-payload')
        $env:Path = "$existingDirectory;$existingDirectory;$OriginalPath"
        $upgrade = Invoke-Installer 'upgrade' @{ Version = 'v2.1.0' }
        Assert-True ($upgrade.Status -eq 0) "Existing install upgrade failed: $($upgrade.Output)"
        Assert-RequestedUrl $upgrade.Urls 'https://github.com/jmpompeo/orchestra/releases/download/v2.1.0/orchestrate-win-x64.zip' 'Explicit-version asset URL was not requested.'
        Assert-RequestedUrl $upgrade.Urls 'https://github.com/jmpompeo/orchestra/releases/download/v2.1.0/SHA256SUMS' 'Explicit-version checksum URL was not requested.'
        Assert-True ($upgrade.Urls.Count -eq 2) "Explicit-version upgrade made an unexpected number of download requests: $($upgrade.Urls.Count)."
        Assert-SameFile $FixtureExecutable $existingTarget
        Assert-Contains $upgrade.Output "Updating the one orchestrate executable found on PATH: $existingTarget"
    }

    Invoke-TestCase 'checksum-mismatch' $InvalidSums {
        $mismatchDirectory = Join-Path $TestRoot 'mismatch/bin'
        [IO.Directory]::CreateDirectory($mismatchDirectory) | Out-Null
        $mismatchTarget = Join-Path $mismatchDirectory 'orchestrate.exe'
        [IO.File]::WriteAllText($mismatchTarget, 'must-remain')
        $beforeHash = (Get-FileHash -LiteralPath $mismatchTarget -Algorithm SHA256).Hash
        $mismatch = Invoke-Installer 'mismatch' @{ InstallDir = $mismatchDirectory; Version = 'v2.1.0' }
        Assert-True ($mismatch.Status -eq 1) 'Checksum mismatch unexpectedly succeeded.'
        Assert-Contains $mismatch.Output 'SHA-256 mismatch'
        Assert-True ($beforeHash -eq (Get-FileHash -LiteralPath $mismatchTarget -Algorithm SHA256).Hash) 'Checksum mismatch changed the existing executable.'
    }

    Invoke-TestCase 'ambiguous-path' $ValidSums {
        $ambiguousA = Join-Path $TestRoot 'ambiguous/a'
        $ambiguousB = Join-Path $TestRoot 'ambiguous/b'
        [IO.Directory]::CreateDirectory($ambiguousA) | Out-Null
        [IO.Directory]::CreateDirectory($ambiguousB) | Out-Null
        Copy-Item -LiteralPath $FixtureExecutable -Destination (Join-Path $ambiguousA 'orchestrate.exe')
        Copy-Item -LiteralPath $FixtureExecutable -Destination (Join-Path $ambiguousB 'orchestrate.exe')
        $env:Path = "$ambiguousA;$ambiguousB;$OriginalPath"
        $ambiguous = Invoke-Installer 'ambiguous' @{ Version = 'v2.1.0' }
        Assert-True ($ambiguous.Status -eq 1) 'Ambiguous PATH unexpectedly succeeded.'
        Assert-Contains $ambiguous.Output 'Found multiple orchestrate.exe entries on PATH'
        Assert-True ($ambiguous.Urls.Count -eq 0) 'Ambiguous PATH attempted a download.'
    }

    Invoke-TestCase 'invalid-version' $ValidSums {
        $invalidVersion = Invoke-Installer 'invalid-version' @{ Version = 'v2.bad.0'; InstallDir = (Join-Path $TestRoot 'invalid/bin') }
        Assert-True ($invalidVersion.Status -eq 1) 'Invalid version unexpectedly succeeded.'
        Assert-Contains $invalidVersion.Output 'stable release tag in the form vX.Y.Z'
        Assert-True ($invalidVersion.Urls.Count -eq 0) 'Invalid version attempted a download.'
    }

    if ($script:OrchestraTestFailures.Count -gt 0) {
        $summary = ($script:OrchestraTestFailures | ForEach-Object { "`n- $_" }) -join ''
        Fail "$($script:OrchestraTestFailures.Count) Windows installer test(s) failed:$summary"
    }

    Write-Output 'PASS: scripts/install.ps1 network-free installer tests'
}
finally {
    $env:Path = $OriginalPath
    Remove-Item function:global:Invoke-WebRequest -ErrorAction SilentlyContinue
    Remove-Variable OrchestraTestSums, OrchestraTestRequestedUrls, OrchestraTestFixtureZip, OrchestraTestExpectedArchiveUrl, OrchestraTestExpectedSumsUrl -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
