param(
    [string]$ExportDir = 'pricing-export'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([System.IO.Path]::IsPathRooted($ExportDir)) {
    $exportRoot = $ExportDir
} else {
    $exportRoot = Join-Path $repoRoot $ExportDir
}

function Read-JsonFile {
    param([string]$Path)
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Assert-FileHash {
    param(
        [string]$Root,
        [string]$RelativePath,
        [string]$Expected
    )

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path $path)) {
        throw "Manifest references a missing file: $path"
    }
    $actual = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        throw "SHA-256 mismatch for $RelativePath`: $actual != $Expected"
    }
}

function Get-ExpectedRollbackPaths {
    param([string]$Root, [object[]]$ManifestFiles)

    $expected = New-Object 'System.Collections.Generic.HashSet[string]'
    $records = 0

    foreach ($file in $ManifestFiles) {
        $path = Join-Path $Root $file.path
        $payload = Read-JsonFile -Path $path
        if ($file.path -like 'rules/*.json') {
            $expected.Add("customMetadata/Pricing_Rule__mdt.$($payload.developerName).md-meta.xml") | Out-Null
            $records++
        } elseif ($file.path -like 'config-rules/*.json') {
            $expected.Add("customMetadata/Config_Rule__mdt.$($payload.developerName).md-meta.xml") | Out-Null
            $records++
        } elseif ($file.path -like 'procedures/*.json') {
            foreach ($step in @($payload.steps)) {
                $expected.Add("customMetadata/Pricing_Procedure__mdt.$($step.developerName).md-meta.xml") | Out-Null
                $records++
            }
        } else {
            throw "Unexpected export path: $($file.path)"
        }
    }

    return [pscustomobject]@{
        Paths = $expected
        Records = $records
    }
}

$manifestPath = Join-Path $exportRoot 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    throw "Export manifest not found: $manifestPath"
}
$manifest = Read-JsonFile -Path $manifestPath
if ($manifest.algorithm -ne 'SHA-256') {
    throw "Unsupported export hash algorithm: $($manifest.algorithm)"
}
$manifestFiles = @($manifest.files)
if ($manifestFiles.Count -eq 0) {
    throw 'Export manifest contains no files.'
}

$manifestPaths = New-Object 'System.Collections.Generic.HashSet[string]'
$records = 0
foreach ($file in $manifestFiles) {
    if ([string]::IsNullOrWhiteSpace($file.path)) {
        throw 'Export manifest contains an empty path.'
    }
    if (-not $manifestPaths.Add($file.path)) {
        throw "Duplicate export manifest path: $($file.path)"
    }
    Assert-FileHash -Root $exportRoot -RelativePath $file.path -Expected $file.sha256
    $records += [int]$file.recordCount
}

if ([int]$manifest.totals.files -ne $manifestFiles.Count) {
    throw "Manifest total files is $($manifest.totals.files); expected $($manifestFiles.Count)."
}
if ([int]$manifest.totals.records -ne $records) {
    throw "Manifest total records is $($manifest.totals.records); expected $records."
}

$actualJsonPaths = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($directory in @('procedures', 'rules', 'config-rules')) {
    $path = Join-Path $exportRoot $directory
    if (-not (Test-Path $path)) {
        throw "Export directory missing: $path"
    }
    foreach ($file in Get-ChildItem -Path $path -Filter '*.json' -File) {
        $relative = "$directory/$($file.Name)"
        $actualJsonPaths.Add($relative) | Out-Null
        if (-not $manifestPaths.Contains($relative)) {
            throw "Unmanifested export file: $relative"
        }
    }
}
foreach ($path in $manifestPaths) {
    if (-not $actualJsonPaths.Contains($path)) {
        throw "Manifest file is not present on disk: $path"
    }
}

$rollbackRoot = Join-Path $exportRoot 'rollback'
$rollbackManifestPath = Join-Path $rollbackRoot 'manifest.json'
if (-not (Test-Path $rollbackManifestPath)) {
    throw "Rollback manifest not found: $rollbackManifestPath"
}
$rollback = Read-JsonFile -Path $rollbackManifestPath
if ($rollback.algorithm -ne 'SHA-256') {
    throw "Unsupported rollback hash algorithm: $($rollback.algorithm)"
}
$rollbackFiles = @($rollback.files)
if ($rollbackFiles.Count -eq 0) {
    throw 'Rollback manifest contains no files.'
}
if ($manifest.exportedAt -ne $rollback.createdAt) {
    throw "Export and rollback timestamps differ: $($manifest.exportedAt) != $($rollback.createdAt)."
}

$rollbackPaths = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($file in $rollbackFiles) {
    if (-not $rollbackPaths.Add($file.path)) {
        throw "Duplicate rollback manifest path: $($file.path)"
    }
    Assert-FileHash -Root $rollbackRoot -RelativePath $file.path -Expected $file.sha256
}
if ([int]$rollback.totals.files -ne $rollbackFiles.Count) {
    throw "Rollback total files is $($rollback.totals.files); expected $($rollbackFiles.Count)."
}

$expectedRollback = Get-ExpectedRollbackPaths -Root $exportRoot -ManifestFiles $manifestFiles
if ($expectedRollback.Records -ne $records) {
    throw "Expected $($expectedRollback.Records) rollback records from JSON, but the manifest counts $records."
}
if ($expectedRollback.Paths.Count -ne $rollbackPaths.Count) {
    throw "Expected $($expectedRollback.Paths.Count) rollback files, but the rollback manifest lists $($rollbackPaths.Count)."
}
foreach ($path in $expectedRollback.Paths) {
    if (-not $rollbackPaths.Contains($path)) {
        throw "Rollback snapshot is missing $path."
    }
}

Write-Output "Pricing export OK: $($manifestFiles.Count) JSON files / $records records; rollback $($rollbackFiles.Count) files."
