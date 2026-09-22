[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repository = 'jmpompeo/orchestra'

function Fail([string]$Message) {
    throw "Error: $Message"
}

function Test-StableVersion([string]$Value) {
    return $Value -match '^v\d+\.\d+\.\d+$'
}

function Get-CurrentUserSid() {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Get-OwnerSid([string]$Path) {
    try {
        $owner = (Get-Acl -LiteralPath $Path).Owner
        return (New-Object Security.Principal.NTAccount($owner)).Translate([Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        Fail "Could not determine the owner of '$Path'. Choose a user-owned -InstallDir."
    }
}

function Test-IsSystemPath([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $roots = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
        if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-IsReparsePoint([string]$Path) {
    return (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-ExistingItem([string]$Path) {
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Assert-NoReparseAncestors([string]$Path) {
    $ancestor = [IO.Path]::GetFullPath($Path)
    while ($true) {
        $item = Get-ExistingItem $ancestor
        if ($null -ne $item -and (Test-IsReparsePoint $ancestor)) {
            Fail "Refusing install directory '$Path' because '$ancestor' is a reparse point. Choose a real user-owned directory with -InstallDir."
        }
        $parent = [IO.Directory]::GetParent($ancestor)
        if ($null -eq $parent) { break }
        $ancestor = $parent.FullName
    }
}

function Assert-SafeInstallDirectory([string]$Path, [string]$CurrentSid) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-IsSystemPath $fullPath) {
        Fail "Refusing system install directory '$fullPath'. Use a user-owned -InstallDir, for example `"`$env:LOCALAPPDATA\Programs\Orchestra\bin`"."
    }
    Assert-NoReparseAncestors $fullPath
    if ($null -eq (Get-ExistingItem $fullPath)) {
        [IO.Directory]::CreateDirectory($fullPath) | Out-Null
    }
    $item = Get-Item -LiteralPath $fullPath -Force
    if (-not ($item -is [IO.DirectoryInfo])) {
        Fail "Install path '$fullPath' is not a directory. Choose a directory with -InstallDir."
    }
    if (Test-IsReparsePoint $fullPath) {
        Fail "Refusing install directory '$fullPath' because it is a reparse point. Choose a real user-owned directory with -InstallDir."
    }
    if ((Get-OwnerSid $fullPath) -ne $CurrentSid) {
        Fail "Refusing install directory '$fullPath' because it is not owned by the current user. Choose a user-owned -InstallDir."
    }
    try {
        $probe = Join-Path $fullPath ('.orchestra-write-probe-' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllBytes($probe, [byte[]]@())
        [IO.File]::Delete($probe)
    }
    catch {
        Fail "Install directory '$fullPath' is not writable. Choose a writable user-owned -InstallDir."
    }
    return $fullPath
}

function Assert-SafeTarget([string]$Path, [string]$CurrentSid) {
    $item = Get-ExistingItem $Path
    if ($null -eq $item) { return $false }
    if (Test-IsReparsePoint $Path) {
        Fail "Refusing '$Path' because it is a reparse point. Remove it manually or choose a different -InstallDir."
    }
    if (-not ($item -is [IO.FileInfo])) {
        Fail "Refusing '$Path' because it is not a regular file. Remove it manually or choose a different -InstallDir."
    }
    if ((Get-OwnerSid $Path) -ne $CurrentSid) {
        Fail "Refusing to replace '$Path' because it is not owned by the current user. Use a user-owned -InstallDir."
    }
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        $stream.Dispose()
    }
    catch {
        Fail "Refusing to replace '$Path' because it is not writable. Fix its permissions or choose a different -InstallDir."
    }
    return $true
}

function Get-PathCandidates() {
    $results = @()
    foreach ($entry in ($env:Path -split ';')) {
        $directory = if ([string]::IsNullOrWhiteSpace($entry)) { (Get-Location).Path } else { $entry }
        $candidate = Join-Path $directory 'orchestrate.exe'
        if ($null -ne (Get-ExistingItem $candidate)) {
            $fullCandidate = [IO.Path]::GetFullPath($candidate)
            if ($results -notcontains $fullCandidate) { $results += $fullCandidate }
        }
    }
    return @($results)
}

function Download([string]$Url, [string]$Output) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Output
    }
    catch {
        Fail "Download failed: $Url. Check your network connection and that the requested release exists."
    }
}

if ($PSBoundParameters.ContainsKey('Version') -and -not (Test-StableVersion $Version)) {
    Fail '-Version must be a stable release tag in the form vX.Y.Z (for example, v2.1.0).'
}
if (-not [Environment]::Is64BitOperatingSystem) {
    Fail 'Unsupported platform. Orchestra bootstrap releases support Windows x64 only. Download the matching release manually if your platform is not supported.'
}
$architecture = if ([string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) { $env:PROCESSOR_ARCHITECTURE } else { $env:PROCESSOR_ARCHITEW6432 }
if ($architecture -notin @('AMD64', 'x86_64')) {
    Fail 'Unsupported platform. Orchestra bootstrap releases support Windows x64 only. Download the matching release manually if your platform is not supported.'
}

$rid = 'win-x64'
$asset = "orchestrate-$rid.zip"
$currentSid = Get-CurrentUserSid
$pathCandidates = @(Get-PathCandidates)

if (-not $PSBoundParameters.ContainsKey('InstallDir')) {
    $resolved = Get-Command orchestrate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathCandidates.Count -gt 1) {
        $listed = ($pathCandidates | ForEach-Object { "`n  $_" }) -join ''
        Fail "Found multiple orchestrate.exe entries on PATH:$listed`nRefusing to guess which executable to replace. Remove or rename the unwanted entries, or rerun with -InstallDir PATH to install a new executable explicitly."
    }
    if ($null -ne $resolved -and $resolved.CommandType -ne 'Application') {
        Fail "'orchestrate' resolves to a $($resolved.CommandType), not a PATH executable. Remove the alias/function or rerun with -InstallDir PATH."
    }
    if ($null -ne $resolved -and [IO.Path]::GetExtension($resolved.Path) -ne '.exe') {
        Fail "'orchestrate' resolves to '$($resolved.Path)', not the supported orchestrate.exe executable. Remove or rename it, or rerun with -InstallDir PATH."
    }
    if ($pathCandidates.Count -eq 1) {
        $InstallDir = Split-Path -Parent $pathCandidates[0]
        Write-Host "Updating the one orchestrate executable found on PATH: $($pathCandidates[0])"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            Fail 'LOCALAPPDATA is not set. Pass -InstallDir PATH to choose a user-owned install directory.'
        }
        $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Orchestra\bin'
        Write-Host "No orchestrate.exe executable was found on PATH; installing to $(Join-Path $InstallDir 'orchestrate.exe')."
    }
}
else {
    Write-Host "Installing to explicitly requested path: $(Join-Path $InstallDir 'orchestrate.exe')"
}

$InstallDir = Assert-SafeInstallDirectory $InstallDir $currentSid
$target = Join-Path $InstallDir 'orchestrate.exe'
$targetExists = Assert-SafeTarget $target $currentSid

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ('orchestra-install-' + [Guid]::NewGuid().ToString('N'))
$staged = $null
[IO.Directory]::CreateDirectory($tmpRoot) | Out-Null
try {
    $zipFile = Join-Path $tmpRoot $asset
    $sumsFile = Join-Path $tmpRoot 'SHA256SUMS'
    if ($PSBoundParameters.ContainsKey('Version')) {
        $releaseUrl = "https://github.com/$Repository/releases/download/$Version"
    }
    else {
        $releaseUrl = "https://github.com/$Repository/releases/latest/download"
    }

    Write-Host "Downloading $asset and SHA256SUMS anonymously from the public GitHub release."
    Download "$releaseUrl/$asset" $zipFile
    Download "$releaseUrl/SHA256SUMS" $sumsFile

    $escapedAsset = [regex]::Escape($asset)
    $hashes = @(
        Get-Content -LiteralPath $sumsFile | ForEach-Object {
            if ($_ -match ('^\s*([A-Fa-f0-9]{64})\s+\*?' + $escapedAsset + '\s*$')) { $matches[1].ToLowerInvariant() }
        }
    )
    if ($hashes.Count -ne 1) {
        Fail "SHA256SUMS must contain exactly one SHA-256 entry for '$asset'; found $($hashes.Count). Refusing to extract the archive."
    }
    $actualHash = (Get-FileHash -LiteralPath $zipFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $hashes[0]) {
        Fail "SHA-256 mismatch for '$asset'. The download was not installed; retry later or inspect the public release assets."
    }
    Write-Host 'Checksum verified.'

    $recheckedInstallDir = Assert-SafeInstallDirectory $InstallDir $currentSid
    if (-not $recheckedInstallDir.Equals($InstallDir, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "Install directory changed during download. Refusing to install; rerun with a stable user-owned -InstallDir."
    }
    Assert-SafeTarget $target $currentSid | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipFile)
    try {
        $entries = @($archive.Entries | Where-Object { $_.FullName -eq 'orchestrate.exe' })
        if ($entries.Count -ne 1) {
            Fail "Verified archive must contain exactly one top-level 'orchestrate.exe' executable; found $($entries.Count). Refusing to install."
        }
        $staged = Join-Path $InstallDir ('.orchestrate-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        $input = $entries[0].Open()
        try {
            $output = [IO.File]::Open($staged, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose() }
        }
        finally { $input.Dispose() }
    }
    finally { $archive.Dispose() }

    # Recheck immediately before an atomic same-directory operation.
    $recheckedInstallDir = Assert-SafeInstallDirectory $InstallDir $currentSid
    if (-not $recheckedInstallDir.Equals($InstallDir, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "Install directory changed during download. Refusing to install; rerun with a stable user-owned -InstallDir."
    }
    $targetExists = Assert-SafeTarget $target $currentSid
    if ($targetExists) {
        [IO.File]::Replace($staged, $target, $null)
    }
    else {
        [IO.File]::Move($staged, $target)
    }
    Write-Host "Installed $target"
}
finally {
    if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
    if ($null -ne $staged -and (Test-Path -LiteralPath $staged)) { Remove-Item -LiteralPath $staged -Force }
}

$pathEntries = @($env:Path -split ';' | ForEach-Object { [IO.Path]::GetFullPath($(if ([string]::IsNullOrWhiteSpace($_)) { (Get-Location).Path } else { $_ })) })
if ($pathEntries -contains $InstallDir) {
    Write-Host 'Next steps:'
    Write-Host '  orchestrate install --tools codex --dry-run'
    Write-Host '  orchestrate install --tools codex'
}
else {
    Write-Host "Next step: add '$InstallDir' to PATH in User Environment Variables and open a new PowerShell session. Then preview and apply your selected configuration:"
    Write-Host '  orchestrate install --tools codex --dry-run'
    Write-Host '  orchestrate install --tools codex'
}
