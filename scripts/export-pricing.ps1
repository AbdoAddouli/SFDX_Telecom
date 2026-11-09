param(
    [string]$TargetOrg = 'abdo@telecom.com'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outRoot = Join-Path $repoRoot 'pricing-export'

function Invoke-SfQuery {
    param([string]$Query)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = (& sf data query --target-org $TargetOrg --query $Query --result-format json 2>$null) -join "`n"
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -ne 0) {
        throw "sf data query failed for: $Query"
    }

    $parsed = $raw | ConvertFrom-Json
    if ($parsed.status -ne 0) {
        throw "Salesforce returned an error for: $Query"
    }
    return @($parsed.result.records)
}

function ConvertTo-SafeFilePart {
    param([string]$Value)

    $safe = $Value -replace '[^A-Za-z0-9._-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'unnamed'
    }
    return $safe
}

function Write-JsonFile {
    param(
        [string]$RelativePath,
        [object]$Payload,
        [int]$RecordCount
    )

    $fullPath = Join-Path $outRoot $RelativePath
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Payload | ConvertTo-Json -Depth 12
    Set-Content -Path $fullPath -Value $json -Encoding utf8

    $hash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{
        path = $RelativePath
        recordCount = $RecordCount
        sha256 = $hash
    }
}

$procedures = Invoke-SfQuery 'SELECT DeveloperName, MasterLabel, Procedure_Name__c, Step_Number__c, Step_Name__c, Apex_Class__c, On_Error__c, Active__c FROM Pricing_Procedure__mdt ORDER BY Procedure_Name__c, Step_Number__c'

$rules = Invoke-SfQuery 'SELECT DeveloperName, MasterLabel, Rule_Type__c, Product__c, Requires_Product__c, Commitment_Code__c, Segment__c, Adjustment_Type__c, Adjustment_Value__c, Priority__c, Effective_From__c, Effective_To__c, Active__c FROM Pricing_Rule__mdt ORDER BY DeveloperName'

$configRules = Invoke-SfQuery 'SELECT DeveloperName, MasterLabel, Rule_Kind__c, Product__c, Companion_Product__c, Applies_When_Commitment__c, Message__c, Severity__c, Active__c FROM Config_Rule__mdt ORDER BY DeveloperName'

if (Test-Path $outRoot) {
    Remove-Item -Path $outRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

$files = New-Object System.Collections.Generic.List[object]

$procedureGroups = $procedures | Group-Object -Property Procedure_Name__c
foreach ($group in ($procedureGroups | Sort-Object Name)) {
    $steps = @(
        $group.Group |
            Sort-Object { [double]$_.Step_Number__c } |
            ForEach-Object {
                [ordered]@{
                    developerName = $_.DeveloperName
                    label = $_.MasterLabel
                    procedureName = $_.Procedure_Name__c
                    stepNumber = $_.Step_Number__c
                    stepName = $_.Step_Name__c
                    apexClass = $_.Apex_Class__c
                    onError = $_.On_Error__c
                    active = $_.Active__c
                }
            }
    )

    $payload = [ordered]@{
        procedure = $group.Name
        steps = $steps
    }
    $relativePath = "procedures/$(ConvertTo-SafeFilePart $group.Name).json"
    $files.Add((Write-JsonFile -RelativePath $relativePath -Payload $payload -RecordCount $steps.Count))
}

foreach ($rule in ($rules | Sort-Object DeveloperName)) {
    $payload = [ordered]@{
        developerName = $rule.DeveloperName
        label = $rule.MasterLabel
        ruleType = $rule.Rule_Type__c
        product = $rule.Product__c
        requiresProduct = $rule.Requires_Product__c
        commitmentCode = $rule.Commitment_Code__c
        segment = $rule.Segment__c
        adjustmentType = $rule.Adjustment_Type__c
        adjustmentValue = $rule.Adjustment_Value__c
        priority = $rule.Priority__c
        effectiveFrom = $rule.Effective_From__c
        effectiveTo = $rule.Effective_To__c
        active = $rule.Active__c
    }
    $relativePath = "rules/$(ConvertTo-SafeFilePart $rule.DeveloperName).json"
    $files.Add((Write-JsonFile -RelativePath $relativePath -Payload $payload -RecordCount 1))
}

foreach ($rule in ($configRules | Sort-Object DeveloperName)) {
    $payload = [ordered]@{
        developerName = $rule.DeveloperName
        label = $rule.MasterLabel
        ruleKind = $rule.Rule_Kind__c
        product = $rule.Product__c
        companionProduct = $rule.Companion_Product__c
        appliesWhenCommitment = $rule.Applies_When_Commitment__c
        message = $rule.Message__c
        severity = $rule.Severity__c
        active = $rule.Active__c
    }
    $relativePath = "config-rules/$(ConvertTo-SafeFilePart $rule.DeveloperName).json"
    $files.Add((Write-JsonFile -RelativePath $relativePath -Payload $payload -RecordCount 1))
}

$totalRecords = 0
foreach ($file in $files) {
    $totalRecords += [int]$file.recordCount
}

$manifest = [ordered]@{
    formatVersion = 1
    exportedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    targetOrg = $TargetOrg
    source = 'sf data query --result-format json'
    algorithm = 'SHA-256'
    files = $files.ToArray()
    totals = [ordered]@{
        files = $files.Count
        records = $totalRecords
    }
}

$manifestPath = Join-Path $outRoot 'manifest.json'
Set-Content -Path $manifestPath -Value ($manifest | ConvertTo-Json -Depth 8) -Encoding utf8

# Keep a deployable snapshot of the source-controlled metadata that backs the
# export. The JSON files are the audit view; this folder is the rollback artefact.
$rollbackRoot = Join-Path $outRoot 'rollback'
$rollbackMetadata = Join-Path $rollbackRoot 'customMetadata'
New-Item -ItemType Directory -Path $rollbackMetadata -Force | Out-Null

$rollbackRecords = New-Object System.Collections.Generic.List[object]
foreach ($procedure in $procedures) {
    $rollbackRecords.Add([pscustomobject]@{
        type = 'Pricing_Procedure__mdt'
        developerName = $procedure.DeveloperName
    })
}
foreach ($rule in $rules) {
    $rollbackRecords.Add([pscustomobject]@{
        type = 'Pricing_Rule__mdt'
        developerName = $rule.DeveloperName
    })
}
foreach ($rule in $configRules) {
    $rollbackRecords.Add([pscustomobject]@{
        type = 'Config_Rule__mdt'
        developerName = $rule.DeveloperName
    })
}

$sourceMetadataRoot = Join-Path $repoRoot 'force-app/main/default/customMetadata'
$rollbackFiles = New-Object System.Collections.Generic.List[object]
foreach ($record in $rollbackRecords) {
    $fileName = "$($record.type).$($record.developerName).md-meta.xml"
    $sourcePath = Join-Path $sourceMetadataRoot $fileName
    if (-not (Test-Path $sourcePath)) {
        throw "Rollback source missing: $sourcePath"
    }

    $destPath = Join-Path $rollbackMetadata $fileName
    Copy-Item -Path $sourcePath -Destination $destPath -Force
    $hash = (Get-FileHash -Path $destPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $rollbackFiles.Add([ordered]@{
        path = "customMetadata/$fileName"
        sha256 = $hash
    })
}

$rollbackManifest = [ordered]@{
    formatVersion = 1
    createdAt = $manifest.exportedAt
    targetOrg = $TargetOrg
    source = 'force-app/main/default/customMetadata'
    algorithm = 'SHA-256'
    files = $rollbackFiles.ToArray()
    totals = [ordered]@{
        files = $rollbackFiles.Count
    }
}

$rollbackManifestPath = Join-Path $rollbackRoot 'manifest.json'
Set-Content -Path $rollbackManifestPath -Value ($rollbackManifest | ConvertTo-Json -Depth 8) -Encoding utf8

Write-Output "Exported $($files.Count) files / $totalRecords records to $outRoot"
Write-Output "Rollback snapshot: $($rollbackFiles.Count) files in $rollbackRoot"
