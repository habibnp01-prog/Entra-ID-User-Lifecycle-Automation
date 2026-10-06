#requires -Version 5.1

<#
.SYNOPSIS
    Entra ID User Lifecycle Automation - Master Orchestrator

.DESCRIPTION
    Complete lifecycle:

        1. Detect expired users
        2. Confirm and disable expired users
        3. Confirm and remove directly assigned licenses
        4. Write audit events
        5. Send administrator notification

    WHATIF:
        - Detection is performed
        - Detection report is created
        - No Entra changes
        - No licenses removed
        - No audit events
        - No email

    NORMAL:
        - Separate confirmation for account disable
        - Separate confirmation for license removal

    FORCE:
        - Skips both confirmations

.NOTES
    Script 03 results are read from its generated CSV report.
    This avoids relying on console/pipeline output from child scripts.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AdminEmail,

    [switch]$Force,

    [switch]$WhatIf
)

# ============================================================
# Configuration
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot

$ReportsPath = Join-Path $ProjectRoot "Reports"
$LogsPath    = Join-Path $ProjectRoot "Logs"

$Script02 = Join-Path $ScriptRoot "02-Get-ExpiredUsers.ps1"
$Script03 = Join-Path $ScriptRoot "03-Disable-ExpiredUsers.ps1"
$Script04 = Join-Path $ScriptRoot "04-Remove-UserLicenses.ps1"
$Script05 = Join-Path $ScriptRoot "05-Write-AuditLog.ps1"
$Script06 = Join-Path $ScriptRoot "06-Send-AdminNotification.ps1"

$IsWhatIf = $WhatIf.IsPresent

# ============================================================
# Header
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Entra ID User Lifecycle Automation" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Project Root :" -ForegroundColor Gray
Write-Host $ProjectRoot -ForegroundColor White
Write-Host ""

Write-Host "Notification Administrator :" -ForegroundColor Gray
Write-Host $AdminEmail -ForegroundColor White
Write-Host ""

if ($IsWhatIf) {

    Write-Host "Execution Mode : WHATIF / DRY RUN" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "WHATIF MODE ENABLED" -ForegroundColor Yellow
    Write-Host "No user accounts will be modified." -ForegroundColor Yellow
    Write-Host "No licenses will be removed." -ForegroundColor Yellow
    Write-Host "No audit events will be written." -ForegroundColor Yellow
    Write-Host "No notification email will be sent." -ForegroundColor Yellow
}
else {

    if ($Force) {
        Write-Host "Execution Mode : FORCE" -ForegroundColor Red
    }
    else {
        Write-Host "Execution Mode : NORMAL / CONFIRMATION REQUIRED" -ForegroundColor Green
    }
}

# ============================================================
# Helper Functions
# ============================================================

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-ProjectScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {

        throw "Required script is missing: $Path"
    }

    Write-Host "OK: $Name" -ForegroundColor Green
}

function Get-LatestReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [datetime]$StartedAt
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return $null
    }

    $Files = Get-ChildItem `
        -LiteralPath $Directory `
        -Filter $Filter `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -ge $StartedAt.AddSeconds(-10)
        } |
        Sort-Object LastWriteTime -Descending

    if ($Files) {
        return $Files | Select-Object -First 1
    }

    return $null
}

function Get-GraphContextSafe {

    try {

        if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
            return Get-MgContext -ErrorAction SilentlyContinue
        }

        return $null
    }
    catch {
        return $null
    }
}

function Write-AuditEventFromOrchestrator {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [string]$DisplayName,

        [string]$UserPrincipalName,

        [string]$EmployeeLeaveDate,

        [string]$PreviousAccountStatus,

        [string]$NewAccountStatus,

        [string]$Result,

        [string]$Details
    )

    if ($IsWhatIf) {

        Write-Host ""
        Write-Host "WHATIF: Audit event not written." -ForegroundColor Yellow

        return [PSCustomObject]@{
            Status  = "WhatIf"
            EventId = $null
        }
    }

    try {

        $AuditResult = & $Script05 `
            -Action $Action `
            -DisplayName $DisplayName `
            -UserPrincipalName $UserPrincipalName `
            -EmployeeLeaveDate $EmployeeLeaveDate `
            -PreviousAccountStatus $PreviousAccountStatus `
            -NewAccountStatus $NewAccountStatus `
            -Result $Result `
            -Details $Details `
            -ErrorAction Stop

        if ($AuditResult -and $AuditResult.Status -eq "Success") {

            return $AuditResult
        }

        throw "Audit script did not return a successful result."
    }
    catch {

        Write-Host ""
        Write-Host "WARNING: Audit event failed." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        return [PSCustomObject]@{
            Status  = "Failed"
            EventId = $null
        }
    }
}

# ============================================================
# STEP 0 - Validate Scripts
# ============================================================

Write-Section "Validating Project Scripts"

Test-ProjectScript `
    -Path $Script02 `
    -Name "02-Get-ExpiredUsers.ps1"

Test-ProjectScript `
    -Path $Script03 `
    -Name "03-Disable-ExpiredUsers.ps1"

Test-ProjectScript `
    -Path $Script04 `
    -Name "04-Remove-UserLicenses.ps1"

Test-ProjectScript `
    -Path $Script05 `
    -Name "05-Write-AuditLog.ps1"

Test-ProjectScript `
    -Path $Script06 `
    -Name "06-Send-AdminNotification.ps1"

# ============================================================
# STEP 1 - Detect Expired Users
# ============================================================

Write-Section "STEP 1 - Detect Expired Users"

$DetectionStartedAt = Get-Date

try {

    # Script 02 is read-only.
    # Do not pass -WhatIf to it.

    & $Script02 `
        -ErrorAction Stop | Out-Host

    Write-Host ""
    Write-Host "Script 02 completed successfully." -ForegroundColor Green
}
catch {

    throw "Expired user detection failed: $($_.Exception.Message)"
}

# ============================================================
# Locate Detection Report
# ============================================================

$ExpiredReport = Get-LatestReport `
    -Directory $ReportsPath `
    -Filter "ExpiredUsers_*.csv" `
    -StartedAt $DetectionStartedAt

if (-not $ExpiredReport) {

    throw "Unable to locate the expired-user detection report."
}

Write-Host ""
Write-Host "Detection report:" -ForegroundColor Gray
Write-Host $ExpiredReport.FullName -ForegroundColor White

# ============================================================
# Read Detection Report
# ============================================================

$ExpiredUsers = @(
    Import-Csv `
        -LiteralPath $ExpiredReport.FullName `
        -ErrorAction Stop |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName)
        }
)

$ExpiredEnabledUsers = @(
    $ExpiredUsers | Where-Object {
        "$($_.AccountEnabled)" -eq "True" -and
        "$($_.ActionRequired)" -eq "Disable Account"
    }
)

$ExpiredAlreadyDisabledUsers = @(
    $ExpiredUsers | Where-Object {
        "$($_.AccountEnabled)" -eq "False"
    }
)

Write-Host ""
Write-Host "Expired users in report : $($ExpiredUsers.Count)" -ForegroundColor Yellow
Write-Host "Expired + Enabled       : $($ExpiredEnabledUsers.Count)" -ForegroundColor Yellow
Write-Host "Already Disabled        : $($ExpiredAlreadyDisabledUsers.Count)" -ForegroundColor Gray

# ============================================================
# Graph Context
# ============================================================

$GraphContext = Get-GraphContextSafe

if ($GraphContext) {

    Write-Host ""
    Write-Host "Microsoft 365 Administrator :" -ForegroundColor Gray
    Write-Host $GraphContext.Account -ForegroundColor White

    Write-Host ""
    Write-Host "Tenant ID :" -ForegroundColor Gray
    Write-Host $GraphContext.TenantId -ForegroundColor White
}

# ============================================================
# No Users
# ============================================================

if ($ExpiredEnabledUsers.Count -eq 0) {

    Write-Host ""
    Write-Host "No expired and enabled users require disabling." -ForegroundColor Green

    if ($IsWhatIf) {
        Write-Host ""
        Write-Host "WHATIF completed successfully." -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "Lifecycle completed. No changes were required." -ForegroundColor Green
    }

    return
}

# ============================================================
# Display Users
# ============================================================

Write-Section "Users Requiring Action"

$ExpiredEnabledUsers |
    Select-Object `
        DisplayName,
        UserPrincipalName,
        EmployeeLeaveDate,
        DaysExpired,
        ActionRequired |
    Format-Table -AutoSize

# ============================================================
# WHATIF
# ============================================================

if ($IsWhatIf) {

    Write-Section "WHATIF - Disable Preview"

    Write-Host "The following accounts WOULD be disabled:" -ForegroundColor Yellow
    Write-Host ""

    $ExpiredEnabledUsers |
        Select-Object `
            DisplayName,
            UserPrincipalName,
            EmployeeLeaveDate,
            DaysExpired |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "WHATIF SUMMARY" -ForegroundColor Cyan
    Write-Host "---------------" -ForegroundColor Cyan
    Write-Host "Accounts that would be disabled : $($ExpiredEnabledUsers.Count)" -ForegroundColor Yellow
    Write-Host "Licenses that would be removed  : Not executed" -ForegroundColor Yellow
    Write-Host "Audit events written            : 0" -ForegroundColor Yellow
    Write-Host "Notification email sent         : No" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "WHATIF completed successfully." -ForegroundColor Green

    return
}

# ============================================================
# STEP 2 - Disable Confirmation
# ============================================================

Write-Section "STEP 2 - Disable Expired Users"

$DisableApproved = $false

if ($Force) {

    Write-Host "FORCE mode enabled." -ForegroundColor Red
    Write-Host "Disable confirmation skipped." -ForegroundColor Yellow

    $DisableApproved = $true
}
else {

    Write-Host "The following accounts are expired and enabled:" -ForegroundColor Yellow
    Write-Host ""

    $ExpiredEnabledUsers |
        Select-Object `
            DisplayName,
            UserPrincipalName,
            EmployeeLeaveDate,
            DaysExpired |
        Format-Table -AutoSize

    Write-Host ""

    $DisableConfirmation = Read-Host `
        "Disable expired user accounts? (Y/N)"

    if ($DisableConfirmation -match "^(Y|YES)$") {

        $DisableApproved = $true
    }
    else {

        Write-Host ""
        Write-Host "Disable operation cancelled by administrator." -ForegroundColor Yellow
    }
}

# ============================================================
# STEP 2A - Execute Disable
# ============================================================

$DisableResultReport = $null
$DisableReport = $null

if ($DisableApproved) {

    $DisableStartedAt = Get-Date

    try {

        # Script 03 creates the authoritative CSV report.
        # Do not depend on child-script pipeline output.

        & $Script03 `
            -Force `
            -ErrorAction Stop | Out-Host

        Write-Host ""
        Write-Host "Script 03 completed successfully." -ForegroundColor Green
    }
    catch {

        throw "Disable operation failed: $($_.Exception.Message)"
    }

    # --------------------------------------------------------
    # Locate Disable Report
    # --------------------------------------------------------

    $DisableReport = Get-LatestReport `
        -Directory $ReportsPath `
        -Filter "DisableExpiredUsers_*.csv" `
        -StartedAt $DisableStartedAt

    if (-not $DisableReport) {

        throw "Unable to locate the disable operation report."
    }

    Write-Host ""
    Write-Host "Disable operation report:" -ForegroundColor Gray
    Write-Host $DisableReport.FullName -ForegroundColor White

    # --------------------------------------------------------
    # Read Disable Report
    # --------------------------------------------------------

    $DisableResultReport = @(
        Import-Csv `
            -LiteralPath $DisableReport.FullName `
            -ErrorAction Stop
    )

    # Only successful results are eligible for next stage.

    $SuccessfulDisables = @(
        $DisableResultReport | Where-Object {
            "$($_.Result)" -eq "Success"
        }
    )

    $FailedDisables = @(
        $DisableResultReport | Where-Object {
            "$($_.Result)" -eq "Failed"
        }
    )

    Write-Host ""
    Write-Host "Successfully disabled : $($SuccessfulDisables.Count)" -ForegroundColor Green
    Write-Host "Failed                : $($FailedDisables.Count)" -ForegroundColor $(if ($FailedDisables.Count -gt 0) { "Red" } else { "Green" })
}
else {

    $SuccessfulDisables = @()
    $FailedDisables = @()
}

# ============================================================
# STEP 2B - Audit Disable Results
# ============================================================

$AuditSuccessCount = 0
$AuditFailureCount = 0

if ($DisableResultReport.Count -gt 0) {

    Write-Section "Audit - Disable Results"

    foreach ($Result in $DisableResultReport) {

        if ([string]::IsNullOrWhiteSpace($Result.UserPrincipalName)) {
            continue
        }

        $AuditResult = Write-AuditEventFromOrchestrator `
            -Action "Disable" `
            -DisplayName $Result.DisplayName `
            -UserPrincipalName $Result.UserPrincipalName `
            -EmployeeLeaveDate $Result.EmployeeLeaveDate `
            -PreviousAccountStatus $Result.PreviousAccountStatus `
            -NewAccountStatus $Result.NewAccountStatus `
            -Result $Result.Result `
            -Details $Result.Details

        if ($AuditResult.Status -eq "Success") {

            $AuditSuccessCount++
        }
        elseif ($AuditResult.Status -eq "Failed") {

            $AuditFailureCount++
        }
    }
}

# ============================================================
# STEP 3 - License Removal
# ============================================================

Write-Section "STEP 3 - Remove Directly Assigned Licenses"

if ($SuccessfulDisables.Count -eq 0) {

    Write-Host "No successfully disabled users are available for license removal." -ForegroundColor Gray
}
else {

    Write-Host "Successfully disabled users:" -ForegroundColor Green
    Write-Host ""

    $SuccessfulDisables |
        Select-Object `
            DisplayName,
            UserPrincipalName |
        Format-Table -AutoSize

    $LicenseApproved = $false

    if ($Force) {

        Write-Host ""
        Write-Host "FORCE mode enabled." -ForegroundColor Red
        Write-Host "License removal confirmation skipped." -ForegroundColor Yellow

        $LicenseApproved = $true
    }
    else {

        Write-Host ""

        $LicenseConfirmation = Read-Host `
            "Remove directly assigned licenses? (Y/N)"

        if ($LicenseConfirmation -match "^(Y|YES)$") {

            $LicenseApproved = $true
        }
        else {

            Write-Host ""
            Write-Host "License removal cancelled by administrator." -ForegroundColor Yellow
        }
    }

    # --------------------------------------------------------
    # Execute License Removal
    # --------------------------------------------------------

    if ($LicenseApproved) {

        foreach ($DisabledUser in $SuccessfulDisables) {

            try {

                Write-Host ""
                Write-Host "Removing licenses from:" -ForegroundColor Cyan
                Write-Host $DisabledUser.UserPrincipalName -ForegroundColor White

                & $Script04 `
                    -UserPrincipalName $DisabledUser.UserPrincipalName `
                    -Force `
                    -ErrorAction Stop | Out-Host

                Write-Host ""
                Write-Host "License operation completed." -ForegroundColor Green

                $LicenseDetails = "Directly assigned licenses removed."

                $AuditResult = Write-AuditEventFromOrchestrator `
                    -Action "RemoveLicense" `
                    -DisplayName $DisabledUser.DisplayName `
                    -UserPrincipalName $DisabledUser.UserPrincipalName `
                    -EmployeeLeaveDate $DisabledUser.EmployeeLeaveDate `
                    -PreviousAccountStatus "Disabled" `
                    -NewAccountStatus "Disabled" `
                    -Result "Success" `
                    -Details $LicenseDetails

                if ($AuditResult.Status -eq "Success") {

                    $AuditSuccessCount++
                }
                elseif ($AuditResult.Status -eq "Failed") {

                    $AuditFailureCount++
                }
            }
            catch {

                Write-Host ""
                Write-Host "License removal failed." -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red

                $AuditResult = Write-AuditEventFromOrchestrator `
                    -Action "RemoveLicense" `
                    -DisplayName $DisabledUser.DisplayName `
                    -UserPrincipalName $DisabledUser.UserPrincipalName `
                    -EmployeeLeaveDate $DisabledUser.EmployeeLeaveDate `
                    -PreviousAccountStatus "Disabled" `
                    -NewAccountStatus "Disabled" `
                    -Result "Failed" `
                    -Details $_.Exception.Message

                if ($AuditResult.Status -eq "Success") {

                    $AuditSuccessCount++
                }
                elseif ($AuditResult.Status -eq "Failed") {

                    $AuditFailureCount++
                }
            }
        }
    }
}

# ============================================================
# STEP 4 - Audit Summary
# ============================================================

Write-Section "STEP 4 - Audit"

Write-Host "Audit events successfully written : $AuditSuccessCount" -ForegroundColor Green
Write-Host "Audit events failed               : $AuditFailureCount" -ForegroundColor $(if ($AuditFailureCount -gt 0) { "Red" } else { "Green" })

# ============================================================
# STEP 5 - Notification
# ============================================================

Write-Section "STEP 5 - Administrator Notification"

try {

    & $Script06 `
        -AdminEmail $AdminEmail `
        -IncludeAllSuccessfulActions `
        -ErrorAction Stop | Out-Host

    Write-Host ""
    Write-Host "Administrator notification completed successfully." -ForegroundColor Green
}
catch {

    Write-Host ""
    Write-Host "WARNING: Administrator notification failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Section "FINAL SUMMARY"

Write-Host "Detection report                 : $($ExpiredReport.Name)" -ForegroundColor White
Write-Host "Expired users                    : $($ExpiredUsers.Count)" -ForegroundColor Yellow
Write-Host "Expired + Enabled                : $($ExpiredEnabledUsers.Count)" -ForegroundColor Yellow
Write-Host "Already disabled                 : $($ExpiredAlreadyDisabledUsers.Count)" -ForegroundColor Gray

$SuccessfulDisableCount = $SuccessfulDisables.Count

Write-Host ""
Write-Host "Execution mode                  : LIVE" -ForegroundColor Green
Write-Host "Users successfully disabled     : $SuccessfulDisableCount" -ForegroundColor Green
Write-Host "Audit events written            : $AuditSuccessCount" -ForegroundColor Green
Write-Host "Audit events failed             : $AuditFailureCount" -ForegroundColor $(if ($AuditFailureCount -gt 0) { "Red" } else { "Green" })
Write-Host "Notification attempted          : Yes" -ForegroundColor Green

Write-Host ""
Write-Host "Lifecycle execution completed." -ForegroundColor Green
Write-Host ""