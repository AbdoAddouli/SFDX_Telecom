# Seeds the ATS catalogue from DATA_MODEL.md section 15.
# Idempotent: Product2 and Eligibility__c are upserted by external ID;
# PricebookEntry rows are matched on (Pricebook2Id, Product2Id).
# Prices are seeded in the standard price book first (the platform requires a
# standard price before a custom price), then mirrored into the active pricebook.
param(
    [string]$TargetOrg = "abdo@telecom.com",
    [string]$PricebookName = ""
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$seed = Join-Path $root "data\seed"

function Get-SfJson {
    param([string[]]$SfArgs)
    $raw = & sf @SfArgs --target-org $TargetOrg --json 2>$null | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "sf $($SfArgs -join ' ') returned no output."
    }
    $parsed = $raw | ConvertFrom-Json
    if ($parsed.status -ne 0) {
        throw "sf $($SfArgs -join ' ') failed: $($parsed.message)"
    }
    return $parsed.result
}

Write-Host "Upserting products from data\seed\products.csv..."
$productResult = Get-SfJson @(
    "data", "upsert", "bulk",
    "--sobject", "Product2",
    "--file", (Join-Path $seed "products.csv"),
    "--external-id", "ATS_Product_Code__c",
    "--line-ending", "LF",
    "--wait", "10"
)
if ($productResult.jobInfo.numberRecordsFailed -ne 0) {
    throw "Product2 upsert had $($productResult.jobInfo.numberRecordsFailed) failed rows."
}
Write-Host "  products processed=$($productResult.jobInfo.numberRecordsProcessed) failed=$($productResult.jobInfo.numberRecordsFailed)"

Write-Host "Upserting eligibility from data\seed\eligibility.csv..."
$eligibilityResult = Get-SfJson @(
    "data", "upsert", "bulk",
    "--sobject", "Eligibility__c",
    "--file", (Join-Path $seed "eligibility.csv"),
    "--external-id", "Postal_Code__c",
    "--line-ending", "LF",
    "--wait", "10"
)
if ($eligibilityResult.jobInfo.numberRecordsFailed -ne 0) {
    throw "Eligibility__c upsert had $($eligibilityResult.jobInfo.numberRecordsFailed) failed rows."
}
Write-Host "  eligibility processed=$($eligibilityResult.jobInfo.numberRecordsProcessed) failed=$($eligibilityResult.jobInfo.numberRecordsFailed)"

Write-Host "Resolving pricebooks..."
$standardQuery = "SELECT Id, Name, IsActive, IsStandard FROM Pricebook2 WHERE IsStandard = true LIMIT 1"
$standardPricebook = (Get-SfJson @("data", "query", "--query", $standardQuery)).records | Select-Object -First 1
if (-not $standardPricebook) {
    throw "No standard Pricebook2 found."
}

$pricebookWhere = "IsActive = true"
if ($PricebookName) {
    $pricebookWhere += " AND Name = '$PricebookName'"
}
$activeQuery = "SELECT Id, Name, IsActive, IsStandard FROM Pricebook2 WHERE $pricebookWhere ORDER BY IsStandard DESC, Name LIMIT 1"
$activePricebook = (Get-SfJson @("data", "query", "--query", $activeQuery)).records | Select-Object -First 1
if (-not $activePricebook) {
    throw "No active Pricebook2 found (filter: $pricebookWhere)."
}
Write-Host "  standard=$($standardPricebook.Name) ($($standardPricebook.Id))"
Write-Host "  active=$($activePricebook.Name) ($($activePricebook.Id))"

# Align the ATS effective-dating flags with the active ATS pricebook.
if (-not $activePricebook.IsStandard) {
    Get-SfJson @(
        "data", "update", "record",
        "--sobject", "Pricebook2",
        "--record-id", $activePricebook.Id,
        "--values", "Is_Active__c=true Effective_From__c=2026-01-01"
    ) | Out-Null
}

$priceRows = Import-Csv (Join-Path $seed "pricebook-entries.csv")
$codes = $priceRows | ForEach-Object { $_.ATS_Product_Code__c }
$codeList = ($codes | ForEach-Object { "'$_'" }) -join ","

$productQuery = "SELECT Id, ATS_Product_Code__c FROM Product2 WHERE ATS_Product_Code__c IN ($codeList)"
$products = (Get-SfJson @("data", "query", "--query", $productQuery)).records
$productByCode = @{}
foreach ($product in $products) {
    $productByCode[$product.ATS_Product_Code__c] = $product
}

$missingProducts = $codes | Where-Object { -not $productByCode.ContainsKey($_) }
if ($missingProducts) {
    throw "Products missing after upsert: $($missingProducts -join ', ')"
}

$productIdList = ($codes | ForEach-Object { "'$($productByCode[$_].Id)'" }) -join ","
$pricebooks = @($standardPricebook)
if ($activePricebook.Id -ne $standardPricebook.Id) {
    $pricebooks += $activePricebook
}

foreach ($pricebook in $pricebooks) {
    $kind = if ($pricebook.IsStandard) { "standard" } else { "active" }
    Write-Host "Syncing $kind pricebook $($pricebook.Name)..."

    $entryQuery = "SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = '$($pricebook.Id)' AND Product2Id IN ($productIdList)"
    $existingEntries = (Get-SfJson @("data", "query", "--query", $entryQuery)).records
    $entryByProductId = @{}
    foreach ($entry in $existingEntries) {
        $entryByProductId[$entry.Product2Id] = $entry
    }

    $created = 0
    $updated = 0
    $unchanged = 0
    foreach ($row in $priceRows) {
        $product = $productByCode[$row.ATS_Product_Code__c]
        $existing = $entryByProductId[$product.Id]
        if (-not $existing) {
            Get-SfJson @(
                "data", "create", "record",
                "--sobject", "PricebookEntry",
                "--values", "Pricebook2Id=$($pricebook.Id) Product2Id=$($product.Id) UnitPrice=$($row.UnitPrice) IsActive=true UseStandardPrice=false"
            ) | Out-Null
            $created++
        }
        elseif ([decimal]$existing.UnitPrice -ne [decimal]$row.UnitPrice) {
            Get-SfJson @(
                "data", "update", "record",
                "--sobject", "PricebookEntry",
                "--record-id", $existing.Id,
                "--values", "UnitPrice=$($row.UnitPrice)"
            ) | Out-Null
            $updated++
        }
        else {
            $unchanged++
        }
    }
    Write-Host "  $kind entries created=$created updated=$updated unchanged=$unchanged"
}

Write-Host "Seed complete."
