#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration
$Table    = 'test'
$BatchId  = '01'
$PclmType = 'PCLD'

# --- Prepare a valid JSON file for AWS (no BOM)
$exprFile = Join-Path $PSScriptRoot 'expr.json'
$jsonText = @"
{
  ":batchID": { "S": "$BatchId" },
  ":pclmType": { "S": "$PclmType" }
}
"@
# Write it without a BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($exprFile, $jsonText, $utf8NoBom)

# --- Paging loop, writing to items_to_update.txt
$NextToken      = ''
$firstIteration = $true

while ($true) {
    # Build the scan arguments
    $scanArgs = @(
        'dynamodb','scan',
        '--table-name',        $Table,
        '--filter-expression', 'attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType',
        '--expression-attribute-values', "file://$exprFile",
        '--projection-expression',       'ID,ACCOUNTNUMBER',
        '--query',                       'Items[*].[ID.S,ACCOUNTNUMBER.S]',
        '--output',                      'text'
    )
    if (-not [string]::IsNullOrEmpty($NextToken)) {
        $scanArgs += '--starting-token'
        $scanArgs += $NextToken
    }

    # On first iteration use > (to start on line 1), afterwards use >>
    if ($firstIteration) {
        aws @scanArgs > items_to_update.txt
        $firstIteration = $false
    }
    else {
        aws @scanArgs >> items_to_update.txt
    }

    # Fetch NextToken for pagination
    $tokenArgs = @(
        'dynamodb','scan',
        '--table-name',        $Table,
        '--filter-expression', 'attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType',
        '--expression-attribute-values', "file://$exprFile",
        '--projection-expression',       'ID',
        '--query',                       'NextToken',
        '--output',                      'text'
    )
    $rawNext = aws @tokenArgs 2>&1

    # Trim after first newline and strip CRs
    $rawNext = ($rawNext -split "`n")[0]
    $rawNext = $rawNext -replace "`r", ''

    # Normalize literal "None"
    if ($rawNext -eq 'None') {
        $rawNext = ''
    }

    # End of table?
    if ([string]::IsNullOrEmpty($rawNext)) {
        $count = (Get-Content items_to_update.txt | Measure-Object -Line).Lines
        Write-Host "Export complete: $count items written."
        break
    }

    # Prepare for next page
    $NextToken = $rawNext
}

# --- Cleanup
Remove-Item $exprFile