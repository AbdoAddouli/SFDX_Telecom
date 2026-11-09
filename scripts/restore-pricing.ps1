param(
    [string]$SnapshotDir = 'pricing-export/rollback',
    [string]$TargetOrg = 'abdo@telecom.com',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([System.IO.Path]::IsPathRooted($SnapshotDir)) {
    $snapshotRoot = $SnapshotDir
} else {
    $snapshotRoot = Join-Path $repoRoot $SnapshotDir
}

$manifestPath = Join-Path $snapshotRoot 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    throw "Rollback manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
if ($manifest.algorithm -ne 'SHA-256') {
    throw "Unsupported rollback hash algorithm: $($manifest.algorithm)"
}
if (-not $manifest.files -or $manifest.files.Count -eq 0) {
    throw "Rollback manifest contains no files: $manifestPath"
}
if ($manifest.targetOrg -and $manifest.targetOrg -ne $TargetOrg) {
    Write-Warning "Snapshot was exported from $($manifest.targetOrg); restoring to $TargetOrg."
}

foreach ($file in $manifest.files) {
    $path = Join-Path $snapshotRoot $file.path
    if (-not (Test-Path $path)) {
        throw "Rollback file missing: $path"
    }
    $actual = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $file.sha256) {
        throw "Rollback hash mismatch for $($file.path): $actual != $($file.sha256)"
    }
}
Write-Output "Verified $($manifest.files.Count) rollback files."

$sourceMetadataDir = Join-Path $snapshotRoot 'customMetadata'
if (-not (Test-Path $sourceMetadataDir)) {
    throw "Rollback metadata directory missing: $sourceMetadataDir"
}

# pricing-export/** is excluded by .forceignore, so deploy from a transient
# folder outside that tree. The folder is removed even when deployment fails.
$tempRoot = Join-Path $repoRoot ('pricing-restore-' + [guid]::NewGuid().ToString('N'))
$tempMetadataDir = Join-Path $tempRoot 'customMetadata'
New-Item -ItemType Directory -Path $tempMetadataDir -Force | Out-Null

try {
    Copy-Item -Path (Join-Path $sourceMetadataDir '*.md-meta.xml') -Destination $tempMetadataDir -Force

    $deployArgs = @(
        'project', 'deploy', 'start',
        '--target-org', $TargetOrg,
        '--source-dir', $tempMetadataDir,
        '--wait', '20',
        '--json'
    )
    if ($DryRun) {
        $deployArgs += '--dry-run'
    }

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = (& sf @deployArgs 2>$null) -join "`n"
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "sf project deploy produced no JSON output (exit $exitCode)."
    }
    $result = $raw | ConvertFrom-Json

    if ($result.name -eq 'NothingToDeploy' -or $result.code -eq 'NothingToDeploy') {
        Write-Output "Snapshot already matches the org; no changes deployed."
        return
    }

    $succeeded = ($result.status -eq 0 -and $result.result.success -eq $true)
    if (-not $succeeded) {
        if ($result.result.details.componentFailures) {
            $result.result.details.componentFailures |
                Select-Object componentType, fullName, problem |
                Format-Table -AutoSize |
                Out-String |
                Write-Output
        }
        throw "Pricing restore failed (exit $exitCode): $($result.message)"
    }

    if ($DryRun) {
        Write-Output "Dry run succeeded; rollback snapshot is deployable."
    } else {
        Write-Output "Pricing restore succeeded from $snapshotRoot."
    }
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}
