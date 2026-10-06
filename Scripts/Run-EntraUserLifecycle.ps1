#requires -Version 5.1

<#
.SYNOPSIS
    Orchestrates the Microsoft Entra ID User Lifecycle Automation workflow.

.DESCRIPTION
    This script coordinates the complete daily lifecycle workflow:

        02 - Detect expired users
        03 - Disable expired users
        04 - Write audit events
        05 - Send administrator notification

    Script 01 is intentionally NOT called by this orchestrator.
    User expiry dates are assigned manually or through another HR-driven
    process using 01-Set-UserExpiryDate.ps1.

    Supports -WhatIf for safe end-to-end testing.

.PARAMETER AdminEmail
    Administrator email address used by Script 05.

.PARAMETER WhatIf
    Runs the workflow in dry-run mode.

    Script 02 runs normally because it is read-only.
    Script 03 runs with -WhatIf.
    Scripts 04 and 05 are NOT executed because no real lifecycle
    action has taken place.

.EXAMPLE
    .\Run-EntraUserLifecycle.ps1 `
        -AdminEmail "admin@contoso.com" `
        -WhatIf

.EXAMPLE
    .\Run-EntraUserLifecycle.ps1 `
        -AdminEmail "admin@contoso.com"

.NOTES
    Project:
        Entra-ID-User-Lifecycle-Automation

    PowerShell:
        Windows PowerShell 5.1+

    IMPORTANT:
        The current implementation uses interactive Microsoft Graph
        authentication.

        For unattended Scheduled Task execution, this should later
        be upgraded to Microsoft Graph application authentication
        using an App Registration and certificate.
#>

[CmdletBinding(SupportsShouldProcess)]
param(

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$AdminEmail
)

# ============================================================
# Project Paths
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$Script02 = Join-Path `
    $PSScriptRoot `
    "02-Get-ExpiredUsers.ps1"

$Script03 = Join-Path `
    $PSScriptRoot `
    "03-Disable-ExpiredUsers.ps1"

$Script04 = Join-Path `
    $PSScriptRoot `
    "04-Write-AuditLog.ps1"

$Script05 = Join-Path `
    $PSScriptRoot `
    "05-Send-AdminNotification.ps1"

$ReportsPath = Join-Path `
    $ProjectRoot `
    "Reports"

# ============================================================
# Header
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Entra ID User Lifecycle Automation" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Project Root :" `
    -ForegroundColor Gray

Write-Host $ProjectRoot `
    -ForegroundColor White

Write-Host ""

Write-Host "Administrator :" `
    -ForegroundColor Gray

Write-Host $AdminEmail `
    -ForegroundColor White

Write-Host ""

# ============================================================
# Execution Mode
# ============================================================

if ($WhatIfPreference) {

    Write-Host "Execution Mode : DRY-RUN" `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "No user accounts will be modified." `
        -ForegroundColor Yellow

    Write-Host "No audit events will be created." `
        -ForegroundColor Yellow

    Write-Host "No email notifications will be sent." `
        -ForegroundColor Yellow
}
else {

    Write-Host "Execution Mode : LIVE" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Expired enabled accounts may be disabled." `
        -ForegroundColor Yellow
}

# ============================================================
# Validate Required Scripts
# ============================================================

Write-Host ""
Write-Host "Validating project scripts..." `
    -ForegroundColor Cyan

$RequiredScripts = @(
    $Script02,
    $Script03,
    $Script04,
    $Script05
)

foreach ($Script in $RequiredScripts) {

    if (-not (Test-Path -Path $Script -PathType Leaf)) {

        Write-Host ""
        Write-Host "ERROR: Required script not found:" `
            -ForegroundColor Red

        Write-Host $Script `
            -ForegroundColor Red

        return
    }

    Write-Host "OK: $([System.IO.Path]::GetFileName($Script))" `
        -ForegroundColor Green
}

# ============================================================
# Validate Reports Directory
# ============================================================

if (-not (Test-Path -Path $ReportsPath)) {

    try {

        New-Item `
            -ItemType Directory `
            -Path $ReportsPath `
            -Force `
            -ErrorAction Stop | Out-Null
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Unable to create Reports directory." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        return
    }
}

# ============================================================
# Capture Existing Disable Reports
# ============================================================

$ExistingDisableReports = @()

$ExistingDisableReports = @(
    Get-ChildItem `
        -Path $ReportsPath `
        -Filter "DisableExpiredUsers_*.csv" `
        -File `
        -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
)

# ============================================================
# STEP 1
# Detect Expired Users
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " STEP 1 - Detect Expired Users" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

try {

    & $Script02

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: Script 02 failed." `
            -ForegroundColor Red

        return
    }
}
catch {

    Write-Host ""
    Write-Host "ERROR: Script 02 execution failed." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

# ============================================================
# STEP 2
# Disable Expired Users
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " STEP 2 - Disable Expired Users" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

try {

    if ($WhatIfPreference) {

        & $Script03 -Force -WhatIf
    }
    else {

        & $Script03 -Force
    }

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: Script 03 failed." `
            -ForegroundColor Red

        return
    }
}
catch {

    Write-Host ""
    Write-Host "ERROR: Script 03 execution failed." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

# ============================================================
# DRY-RUN STOP
# ============================================================

if ($WhatIfPreference) {

    Write-Host ""
    Write-Host "=============================================" `
        -ForegroundColor Yellow

    Write-Host " DRY-RUN COMPLETE" `
        -ForegroundColor Yellow

    Write-Host "=============================================" `
        -ForegroundColor Yellow

    Write-Host ""

    Write-Host "Workflow tested:" `
        -ForegroundColor Cyan

    Write-Host "  02 - Detect expired users" `
        -ForegroundColor Gray

    Write-Host "  03 - Evaluate disable actions" `
        -ForegroundColor Gray

    Write-Host ""

    Write-Host "Skipped intentionally:" `
        -ForegroundColor Cyan

    Write-Host "  04 - Write audit events" `
        -ForegroundColor Gray

    Write-Host "  05 - Send administrator notification" `
        -ForegroundColor Gray

    Write-Host ""

    Write-Host "No user accounts were modified." `
        -ForegroundColor Green

    Write-Host "No email was sent." `
        -ForegroundColor Green

    return
}

# ============================================================
# STEP 3
# Find Newly Generated Disable Report
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " STEP 3 - Process Disable Results" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

$CurrentDisableReports = @(
    Get-ChildItem `
        -Path $ReportsPath `
        -Filter "DisableExpiredUsers_*.csv" `
        -File `
        -ErrorAction SilentlyContinue
)

$NewDisableReports = @(
    $CurrentDisableReports |
    Where-Object {
        $_.FullName -notin $ExistingDisableReports
    } |
    Sort-Object LastWriteTime -Descending
)

if ($NewDisableReports.Count -eq 0) {

    Write-Host "No new disable report was generated." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "This normally means there were no expired" `
        -ForegroundColor Gray

    Write-Host "enabled accounts requiring action." `
        -ForegroundColor Gray

    Write-Host ""

    Write-Host "Skipping audit and notification." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Lifecycle workflow completed." `
        -ForegroundColor Green

    return
}

$LatestDisableReport = $NewDisableReports |
    Select-Object -First 1

Write-Host "New disable report found:" `
    -ForegroundColor Green

Write-Host $LatestDisableReport.FullName `
    -ForegroundColor Gray

# ============================================================
# Import Disable Results
# ============================================================

try {

    $DisableResults = @(
        Import-Csv `
            -Path $LatestDisableReport.FullName `
            -ErrorAction Stop
    )
}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to read disable report." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

Write-Host ""
Write-Host "Disable result entries: $($DisableResults.Count)" `
    -ForegroundColor Cyan

# ============================================================
# STEP 4
# Write Audit Events
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " STEP 4 - Write Audit Events" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

$AuditSuccessCount = 0
$AuditFailureCount = 0

foreach ($Result in $DisableResults) {

    # --------------------------------------------------------
    # Determine Audit Values
    # --------------------------------------------------------

    $AuditAction = "Disable"
    $AuditResult = "Success"
    $NewStatus = "Disabled"

    if ($Result.Result -eq "WhatIf - No Change") {

        $AuditAction = "Skip"
        $AuditResult = "Skipped"
        $NewStatus = $Result.PreviousStatus
    }
    elseif ($Result.Result -ne "Success") {

        $AuditAction = "Failure"
        $AuditResult = "Failed"
        $NewStatus = $Result.PreviousStatus
    }

    try {

        & $Script04 `
            -Action $AuditAction `
            -DisplayName $Result.DisplayName `
            -UserPrincipalName $Result.UserPrincipalName `
            -EmployeeLeaveDate $Result.EmployeeLeaveDate `
            -PreviousAccountStatus $Result.PreviousStatus `
            -NewAccountStatus $NewStatus `
            -Result $AuditResult `
            -Details $Result.Result

        if ($LASTEXITCODE -eq 0) {

            $AuditSuccessCount++
        }
        else {

            $AuditFailureCount++
        }
    }
    catch {

        $AuditFailureCount++

        Write-Host ""
        Write-Host "ERROR: Audit event failed for:" `
            -ForegroundColor Red

        Write-Host $Result.UserPrincipalName `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Audit events written : $AuditSuccessCount" `
    -ForegroundColor Green

Write-Host "Audit events failed  : $AuditFailureCount" `
    -ForegroundColor Yellow

# ============================================================
# STEP 5
# Send Administrator Notification
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " STEP 5 - Send Administrator Notification" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

try {

    & $Script05 `
        -AdminEmail $AdminEmail

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "WARNING: Notification script returned an error." `
            -ForegroundColor Yellow
    }
}
catch {

    Write-Host ""
    Write-Host "WARNING: Notification failed." `
        -ForegroundColor Yellow

    Write-Host $_.Exception.Message `
        -ForegroundColor Yellow
}

# ============================================================
# Final Summary
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Lifecycle Automation Summary" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Execution Mode       : LIVE"
Write-Host "Disable Report       : $($LatestDisableReport.Name)"
Write-Host "Disable Results      : $($DisableResults.Count)"
Write-Host "Audit Events Written : $AuditSuccessCount"
Write-Host "Audit Events Failed  : $AuditFailureCount"

Write-Host ""

if ($AuditFailureCount -gt 0) {

    Write-Host "WARNING: One or more audit events failed." `
        -ForegroundColor Yellow
}

Write-Host "Lifecycle workflow completed." `
    -ForegroundColor Green

Write-Host ""