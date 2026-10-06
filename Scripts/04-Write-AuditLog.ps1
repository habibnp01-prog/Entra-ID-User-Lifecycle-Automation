#requires -Version 5.1

<#
.SYNOPSIS
    Writes Entra ID User Lifecycle events to a local audit log.

.DESCRIPTION
    Creates a unique EventId for every lifecycle event and stores
    the event in a CSV audit log.

    Each lifecycle event receives its own permanent EventId.
    This allows downstream notification and reporting processes
    to track the exact event without relying on duplicate detection.

    NotificationStatus is initialized as "Pending" for every
    new lifecycle event.

.PARAMETER Action
    Lifecycle action being recorded.

.PARAMETER DisplayName
    Display name of the affected user.

.PARAMETER UserPrincipalName
    User Principal Name of the affected user.

.PARAMETER EmployeeLeaveDate
    Employee leave/expiry date.

.PARAMETER PreviousAccountStatus
    Account status before the action.

.PARAMETER NewAccountStatus
    Account status after the action.

.PARAMETER Result
    Result of the lifecycle action.

.PARAMETER Details
    Additional information about the event.

.PARAMETER ShowLog
    Displays the current audit log.

.PARAMETER ClearLog
    Clears the current audit log after confirmation.

.EXAMPLE
    .\04-Write-AuditLog.ps1 `
        -Action "Disable" `
        -DisplayName "Test User" `
        -UserPrincipalName "user@contoso.com" `
        -EmployeeLeaveDate "2026-10-01" `
        -PreviousAccountStatus "Enabled" `
        -NewAccountStatus "Disabled" `
        -Result "Success" `
        -Details "User disabled because employee leave date was reached."

.EXAMPLE
    .\04-Write-AuditLog.ps1 -ShowLog

.EXAMPLE
    .\04-Write-AuditLog.ps1 -ClearLog

.NOTES
    Project: Entra-ID-User-Lifecycle-Automation
    Script: 04-Write-AuditLog.ps1
    PowerShell: Windows PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess)]
param(

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "Set Expiry",
        "Detect Expired",
        "Disable",
        "Skip",
        "Failure",
        "Notification",
        "Other"
    )]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$DisplayName,

    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [string]$EmployeeLeaveDate,

    [Parameter(Mandatory = $false)]
    [string]$PreviousAccountStatus,

    [Parameter(Mandatory = $false)]
    [string]$NewAccountStatus,

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "Success",
        "Failed",
        "Skipped",
        "Information"
    )]
    [string]$Result,

    [Parameter(Mandatory = $false)]
    [string]$Details,

    [Parameter(Mandatory = $false)]
    [switch]$ShowLog,

    [Parameter(Mandatory = $false)]
    [switch]$ClearLog
)

# ============================================================
# PROJECT PATHS
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$LogsPath = Join-Path `
    $ProjectRoot `
    "Logs"

$AuditLogFile = Join-Path `
    $LogsPath `
    "EntraUserLifecycle_Audit.csv"

# ============================================================
# CREATE LOG DIRECTORY
# ============================================================

if (-not (Test-Path -Path $LogsPath)) {

    New-Item `
        -ItemType Directory `
        -Path $LogsPath `
        -Force |
        Out-Null
}

# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Entra ID User Lifecycle - Audit Log" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

# ============================================================
# SHOW EXISTING AUDIT LOG
# ============================================================

if ($ShowLog) {

    if (-not (Test-Path -Path $AuditLogFile)) {

        Write-Host "No audit log exists yet." `
            -ForegroundColor Yellow

        exit 0
    }

    Write-Host "Audit log:" `
        -ForegroundColor Green

    Write-Host $AuditLogFile `
        -ForegroundColor Gray

    Write-Host ""

    try {

        Import-Csv `
            -Path $AuditLogFile `
            -ErrorAction Stop |
            Format-Table -AutoSize

    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Unable to read audit log." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        exit 1
    }

    exit 0
}

# ============================================================
# CLEAR AUDIT LOG
# ============================================================

if ($ClearLog) {

    if (-not (Test-Path -Path $AuditLogFile)) {

        Write-Host "Audit log does not exist." `
            -ForegroundColor Yellow

        exit 0
    }

    Write-Host "WARNING: This will permanently clear the audit log." `
        -ForegroundColor Yellow

    Write-Host ""

    $Confirmation = Read-Host `
        "Type CLEAR to continue"

    if ($Confirmation -ne "CLEAR") {

        Write-Host ""
        Write-Host "Operation cancelled." `
            -ForegroundColor Yellow

        exit 0
    }

    if (
        $PSCmdlet.ShouldProcess(
            $AuditLogFile,
            "Clear audit log"
        )
    ) {

        try {

            Remove-Item `
                -Path $AuditLogFile `
                -Force `
                -ErrorAction Stop

            Write-Host ""
            Write-Host "Audit log cleared successfully." `
                -ForegroundColor Green
        }
        catch {

            Write-Host ""
            Write-Host "ERROR: Failed to clear audit log." `
                -ForegroundColor Red

            Write-Host $_.Exception.Message `
                -ForegroundColor Red

            exit 1
        }
    }

    exit 0
}

# ============================================================
# VALIDATE REQUIRED PARAMETERS
# ============================================================

if ([string]::IsNullOrWhiteSpace($Action)) {

    Write-Host "ERROR: -Action is required." `
        -ForegroundColor Red

    exit 1
}

if ([string]::IsNullOrWhiteSpace($Result)) {

    Write-Host "ERROR: -Result is required." `
        -ForegroundColor Red

    exit 1
}

# ============================================================
# GENERATE UNIQUE EVENT ID
# ============================================================

$EventId = [guid]::NewGuid().ToString()

# ============================================================
# TIMESTAMP
# ============================================================

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ============================================================
# EXECUTION CONTEXT
# ============================================================

$ExecutedBy = "$env:USERDOMAIN\$env:USERNAME"

if ([string]::IsNullOrWhiteSpace($ExecutedBy)) {

    $ExecutedBy = $env:USERNAME
}

$ComputerName = $env:COMPUTERNAME

# ============================================================
# MICROSOFT GRAPH TENANT ID
# ============================================================

$TenantId = ""

try {

    $GraphContextCommand = Get-Command `
        Get-MgContext `
        -ErrorAction SilentlyContinue

    if ($GraphContextCommand) {

        $GraphContext = Get-MgContext `
            -ErrorAction SilentlyContinue

        if ($GraphContext) {

            $TenantId = $GraphContext.TenantId
        }
    }
}
catch {

    $TenantId = ""
}

# ============================================================
# CREATE AUDIT ENTRY
# ============================================================

$AuditEntry = [PSCustomObject]@{

    EventId                 = $EventId
    Timestamp               = $Timestamp
    Action                  = $Action
    DisplayName             = $DisplayName
    UserPrincipalName       = $UserPrincipalName
    EmployeeLeaveDate       = $EmployeeLeaveDate
    PreviousAccountStatus   = $PreviousAccountStatus
    NewAccountStatus        = $NewAccountStatus
    Result                  = $Result
    Details                 = $Details
    ExecutedBy              = $ExecutedBy
    ComputerName            = $ComputerName
    TenantId                = $TenantId

    # Notification tracking
    NotificationStatus      = "Pending"
    NotificationTimestamp   = ""
}

# ============================================================
# DISPLAY EVENT
# ============================================================

Write-Host "Audit event:" `
    -ForegroundColor Cyan

Write-Host ""

$AuditEntry |
    Format-List

# ============================================================
# WRITE AUDIT ENTRY
# ============================================================

if (
    $PSCmdlet.ShouldProcess(
        $AuditLogFile,
        "Write lifecycle audit event $EventId"
    )
) {

    try {

        if (Test-Path -Path $AuditLogFile) {

            $AuditEntry |
                Export-Csv `
                    -Path $AuditLogFile `
                    -NoTypeInformation `
                    -Append `
                    -Encoding UTF8 `
                    -Force
        }
        else {

            $AuditEntry |
                Export-Csv `
                    -Path $AuditLogFile `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -Force
        }

        Write-Host ""
        Write-Host "Audit event written successfully." `
            -ForegroundColor Green

        Write-Host ""

        Write-Host "EventId:" `
            -ForegroundColor Gray

        Write-Host $EventId `
            -ForegroundColor White

        Write-Host ""

        Write-Host "Notification Status:" `
            -ForegroundColor Gray

        Write-Host "Pending" `
            -ForegroundColor Yellow

        Write-Host ""

        Write-Host "Audit log:" `
            -ForegroundColor Gray

        Write-Host $AuditLogFile `
            -ForegroundColor Gray
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Failed to write audit event." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red

        exit 1
    }
}

# ============================================================
# FINAL STATUS
# ============================================================

Write-Host ""
Write-Host "Audit operation completed successfully." `
    -ForegroundColor Green

Write-Host ""