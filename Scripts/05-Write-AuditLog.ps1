#requires -Version 5.1

<#
.SYNOPSIS
    Writes Entra ID User Lifecycle events to a local audit CSV.

.DESCRIPTION
    Creates and maintains:
        Logs\EntraUserLifecycle_Audit.csv

    The script automatically:
      - Creates the audit log if it does not exist
      - Detects the legacy "ExecutedBy" column
      - Migrates "ExecutedBy" to "PerformedBy"
      - Keeps historical audit records
      - Uses a consistent audit schema
      - Records Microsoft Entra / Microsoft 365 administrator
      - Records Windows user and computer
      - Records tenant ID when available
      - Supports ShowLog and ClearLog
      - Returns a structured result to the orchestrator

.NOTES
    No Microsoft Graph permission is required by this script.
    If a Microsoft Graph session already exists, the authenticated
    account and tenant ID are automatically detected.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "Set Expiry",
        "Detect Expired",
        "Disable",
        "RemoveLicense",
        "Skip",
        "Failure",
        "Notification",
        "Other"
    )]
    [string]$Action,

    [string]$DisplayName = "",

    [string]$UserPrincipalName = "",

    [string]$EmployeeLeaveDate = "",

    [string]$PreviousAccountStatus = "",

    [string]$NewAccountStatus = "",

    [ValidateSet("Success", "Skipped", "Failed")]
    [string]$Result = "Success",

    [string]$Details = "",

    [string]$PerformedBy = "",

    [string]$WindowsUser = "",

    [string]$ComputerName = "",

    [string]$TenantId = "",

    [switch]$ShowLog,

    [switch]$ClearLog
)

# ============================================================
# Paths
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDirectory = Join-Path $ProjectRoot "Logs"
$AuditFile = Join-Path $LogDirectory "EntraUserLifecycle_Audit.csv"

# ============================================================
# Standard Audit Schema
# ============================================================

$AuditColumns = @(
    "EventId",
    "Timestamp",
    "Action",
    "DisplayName",
    "UserPrincipalName",
    "EmployeeLeaveDate",
    "PreviousAccountStatus",
    "NewAccountStatus",
    "Result",
    "Details",
    "PerformedBy",
    "WindowsUser",
    "ComputerName",
    "TenantId",
    "NotificationStatus",
    "NotificationTimestamp"
)

# ============================================================
# Functions
# ============================================================

function Write-Section {
    param(
        [string]$Title
    )

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Ensure-LogDirectory {
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
}

function Get-GraphContextInformation {

    $ContextInfo = @{
        Account  = ""
        TenantId = ""
    }

    try {

        $GetMgContextCommand = Get-Command Get-MgContext -ErrorAction SilentlyContinue

        if ($null -ne $GetMgContextCommand) {

            $Context = Get-MgContext -ErrorAction SilentlyContinue

            if ($null -ne $Context) {

                if ($Context.Account) {
                    $ContextInfo.Account = [string]$Context.Account
                }

                if ($Context.TenantId) {
                    $ContextInfo.TenantId = [string]$Context.TenantId
                }
            }
        }
    }
    catch {
        # Graph context is optional for this script.
    }

    return $ContextInfo
}

function Get-ValueSafely {
    param(
        [object]$Object,
        [string]$PropertyName
    )

    if ($null -eq $Object) {
        return ""
    }

    $Property = $Object.PSObject.Properties[$PropertyName]

    if ($null -ne $Property) {
        return [string]$Property.Value
    }

    return ""
}

function Convert-LegacyAuditLog {

    if (-not (Test-Path $AuditFile)) {
        return $true
    }

    try {

        $ExistingRows = @(Import-Csv -Path $AuditFile -ErrorAction Stop)

        if ($ExistingRows.Count -eq 0) {
            return $true
        }

        $FirstRow = $ExistingRows[0]

        $HasPerformedBy = $null -ne $FirstRow.PSObject.Properties["PerformedBy"]
        $HasExecutedBy  = $null -ne $FirstRow.PSObject.Properties["ExecutedBy"]

        # Already using the new schema.
        if ($HasPerformedBy -and -not $HasExecutedBy) {
            return $true
        }

        Write-Host "Legacy audit schema detected." -ForegroundColor Yellow
        Write-Host "Migrating ExecutedBy -> PerformedBy..." -ForegroundColor Yellow

        $NormalizedRows = foreach ($Row in $ExistingRows) {

            $PerformedByValue = Get-ValueSafely `
                -Object $Row `
                -PropertyName "PerformedBy"

            $ExecutedByValue = Get-ValueSafely `
                -Object $Row `
                -PropertyName "ExecutedBy"

            if ([string]::IsNullOrWhiteSpace($PerformedByValue)) {
                $PerformedByValue = $ExecutedByValue
            }

            $NotificationStatus = Get-ValueSafely `
                -Object $Row `
                -PropertyName "NotificationStatus"

            $NotificationTimestamp = Get-ValueSafely `
                -Object $Row `
                -PropertyName "NotificationTimestamp"

            # Historical rows that do not have notification tracking
            # should not unexpectedly trigger a new notification.
            if ([string]::IsNullOrWhiteSpace($NotificationStatus)) {
                $NotificationStatus = "Sent"
            }

            [PSCustomObject][ordered]@{
                EventId                = Get-ValueSafely $Row "EventId"
                Timestamp              = Get-ValueSafely $Row "Timestamp"
                Action                 = Get-ValueSafely $Row "Action"
                DisplayName            = Get-ValueSafely $Row "DisplayName"
                UserPrincipalName      = Get-ValueSafely $Row "UserPrincipalName"
                EmployeeLeaveDate      = Get-ValueSafely $Row "EmployeeLeaveDate"
                PreviousAccountStatus  = Get-ValueSafely $Row "PreviousAccountStatus"
                NewAccountStatus       = Get-ValueSafely $Row "NewAccountStatus"
                Result                 = Get-ValueSafely $Row "Result"
                Details                = Get-ValueSafely $Row "Details"
                PerformedBy            = $PerformedByValue
                WindowsUser            = Get-ValueSafely $Row "WindowsUser"
                ComputerName           = Get-ValueSafely $Row "ComputerName"
                TenantId               = Get-ValueSafely $Row "TenantId"
                NotificationStatus     = $NotificationStatus
                NotificationTimestamp  = $NotificationTimestamp
            }
        }

        $TempFile = "$AuditFile.tmp"

        $NormalizedRows |
            Export-Csv `
                -Path $TempFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Force `
                -ErrorAction Stop

        Move-Item `
            -Path $TempFile `
            -Destination $AuditFile `
            -Force `
            -ErrorAction Stop

        Write-Host "Audit log migration completed successfully." -ForegroundColor Green

        return $true
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Failed to migrate existing audit log." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        return $false
    }
}

function Initialize-AuditLog {

    Ensure-LogDirectory

    if (-not (Test-Path $AuditFile)) {

        $HeaderObject = [PSCustomObject][ordered]@{}

        foreach ($Column in $AuditColumns) {
            $HeaderObject | Add-Member -NotePropertyName $Column -NotePropertyValue ""
        }

        $HeaderObject |
            Export-Csv `
                -Path $AuditFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Force `
                -ErrorAction Stop

        Write-Host "Created new audit log:" -ForegroundColor Green
        Write-Host $AuditFile

        return $true
    }

    return (Convert-LegacyAuditLog)
}

function Clear-AuditLog {

    Write-Section "Clear Audit Log"

    Write-Host "Audit log:" -ForegroundColor Yellow
    Write-Host $AuditFile
    Write-Host ""

    $Confirmation = Read-Host "Type CLEAR to continue"

    if ($Confirmation -cne "CLEAR") {

        Write-Host ""
        Write-Host "Clear operation cancelled." -ForegroundColor Yellow

        return [PSCustomObject]@{
            Status  = "Skipped"
            Action  = "ClearLog"
            Details = "Clear operation cancelled by administrator."
        }
    }

    try {

        Ensure-LogDirectory

        $HeaderObject = [PSCustomObject][ordered]@{}

        foreach ($Column in $AuditColumns) {
            $HeaderObject | Add-Member -NotePropertyName $Column -NotePropertyValue ""
        }

        $HeaderObject |
            Export-Csv `
                -Path $AuditFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Force `
                -ErrorAction Stop

        Write-Host ""
        Write-Host "Audit log cleared successfully." -ForegroundColor Green

        return [PSCustomObject]@{
            Status  = "Success"
            Action  = "ClearLog"
            Details = "Audit log cleared successfully."
        }
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Failed to clear audit log." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        return [PSCustomObject]@{
            Status  = "Failed"
            Action  = "ClearLog"
            Details = $_.Exception.Message
        }
    }
}

function Show-AuditLog {

    Write-Section "Entra ID User Lifecycle - Audit Log"

    if (-not (Test-Path $AuditFile)) {

        Write-Host "No audit log exists." -ForegroundColor Yellow
        return
    }

    try {

        $Rows = @(Import-Csv -Path $AuditFile -ErrorAction Stop)

        if ($Rows.Count -eq 0) {

            Write-Host "Audit log is empty." -ForegroundColor Yellow
            return
        }

        Write-Host "Audit file:" -ForegroundColor Cyan
        Write-Host $AuditFile
        Write-Host ""

        $Rows |
            Select-Object `
                Timestamp,
                Action,
                DisplayName,
                UserPrincipalName,
                Result,
                PerformedBy,
                ComputerName,
                NotificationStatus |
            Format-Table -AutoSize
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Failed to read audit log." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Write-AuditEvent {

    param(
        [string]$EventId,
        [string]$Timestamp
    )

    try {

        if (-not (Initialize-AuditLog)) {
            throw "Audit log initialization or migration failed."
        }

        $AuditRecord = [PSCustomObject][ordered]@{
            EventId                = $EventId
            Timestamp              = $Timestamp
            Action                 = $Action
            DisplayName            = $DisplayName
            UserPrincipalName      = $UserPrincipalName
            EmployeeLeaveDate      = $EmployeeLeaveDate
            PreviousAccountStatus  = $PreviousAccountStatus
            NewAccountStatus       = $NewAccountStatus
            Result                 = $Result
            Details                = $Details
            PerformedBy            = $PerformedBy
            WindowsUser            = $WindowsUser
            ComputerName           = $ComputerName
            TenantId               = $TenantId
            NotificationStatus     = "Pending"
            NotificationTimestamp  = ""
        }

        # Verify the existing CSV schema before appending.
        $ExistingRows = @(Import-Csv -Path $AuditFile -ErrorAction Stop)

        if ($ExistingRows.Count -gt 0) {

            $ExistingProperties = @(
                $ExistingRows[0].PSObject.Properties.Name
            )

            $MissingColumns = @(
                $AuditColumns |
                    Where-Object {
                        $_ -notin $ExistingProperties
                    }
            )

            if ($MissingColumns.Count -gt 0) {
                throw "Audit log schema is missing column(s): $($MissingColumns -join ', ')"
            }

            if ("ExecutedBy" -in $ExistingProperties) {
                throw "Legacy ExecutedBy column still exists after migration."
            }
        }

        $AuditRecord |
            Export-Csv `
                -Path $AuditFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Append `
                -ErrorAction Stop

        Write-Host ""
        Write-Host "Audit event written successfully." -ForegroundColor Green
        Write-Host ""
        Write-Host "EventId               : $EventId"
        Write-Host "Timestamp             : $Timestamp"
        Write-Host "Action                : $Action"
        Write-Host "DisplayName           : $DisplayName"
        Write-Host "UserPrincipalName     : $UserPrincipalName"
        Write-Host "EmployeeLeaveDate     : $EmployeeLeaveDate"
        Write-Host "PreviousAccountStatus : $PreviousAccountStatus"
        Write-Host "NewAccountStatus      : $NewAccountStatus"
        Write-Host "Result                : $Result"
        Write-Host "Details               : $Details"
        Write-Host "PerformedBy           : $PerformedBy"
        Write-Host "WindowsUser           : $WindowsUser"
        Write-Host "ComputerName          : $ComputerName"
        Write-Host "TenantId              : $TenantId"
        Write-Host "NotificationStatus    : Pending"
        Write-Host ""

        # Structured output consumed by the orchestrator.
        return [PSCustomObject][ordered]@{
            Status           = "Success"
            EventId          = $EventId
            Action           = $Action
            UserPrincipalName = $UserPrincipalName
            PerformedBy      = $PerformedBy
            Details          = "Audit event written successfully."
        }
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Failed to write audit event." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""

        # Important:
        # Throw so the orchestrator can count this as a failure.
        throw
    }
}

# ============================================================
# Main
# ============================================================

try {

    Ensure-LogDirectory

    # --------------------------------------------------------
    # Show existing log
    # --------------------------------------------------------

    if ($ShowLog) {

        Show-AuditLog
        return
    }

    # --------------------------------------------------------
    # Clear existing log
    # --------------------------------------------------------

    if ($ClearLog) {

        $ClearResult = Clear-AuditLog

        Write-Output $ClearResult
        return
    }

    Write-Section "Entra ID User Lifecycle - Audit Log"

    # --------------------------------------------------------
    # Detect Graph context if available
    # --------------------------------------------------------

    $GraphContext = Get-GraphContextInformation

    if ([string]::IsNullOrWhiteSpace($PerformedBy)) {

        if (-not [string]::IsNullOrWhiteSpace($GraphContext.Account)) {
            $PerformedBy = $GraphContext.Account
        }
        else {
            $PerformedBy = "Not Available"
        }
    }

    if ([string]::IsNullOrWhiteSpace($TenantId)) {

        if (-not [string]::IsNullOrWhiteSpace($GraphContext.TenantId)) {
            $TenantId = $GraphContext.TenantId
        }
        else {
            $TenantId = "Not Available"
        }
    }

    if ([string]::IsNullOrWhiteSpace($WindowsUser)) {
        $WindowsUser = "$env:USERDOMAIN\$env:USERNAME"
    }

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        $ComputerName = $env:COMPUTERNAME
    }

    $EventId = [guid]::NewGuid().Guid

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host "Audit event:"
    Write-Host ""
    Write-Host "EventId               : $EventId"
    Write-Host "Timestamp             : $Timestamp"
    Write-Host "Action                : $Action"
    Write-Host "DisplayName           : $DisplayName"
    Write-Host "UserPrincipalName     : $UserPrincipalName"
    Write-Host "EmployeeLeaveDate     : $EmployeeLeaveDate"
    Write-Host "PreviousAccountStatus : $PreviousAccountStatus"
    Write-Host "NewAccountStatus      : $NewAccountStatus"
    Write-Host "Result                : $Result"
    Write-Host "Details               : $Details"
    Write-Host "PerformedBy           : $PerformedBy"
    Write-Host "WindowsUser           : $WindowsUser"
    Write-Host "ComputerName          : $ComputerName"
    Write-Host "TenantId              : $TenantId"
    Write-Host "NotificationStatus    : Pending"
    Write-Host "NotificationTimestamp : "
    Write-Host ""

    $ResultObject = Write-AuditEvent `
        -EventId $EventId `
        -Timestamp $Timestamp

    Write-Output $ResultObject
}
catch {

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Red
    Write-Host " AUDIT OPERATION FAILED" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    throw
}