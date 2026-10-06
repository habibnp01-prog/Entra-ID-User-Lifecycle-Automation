#requires -Version 5.1

<#
.SYNOPSIS
    Sends administrator notifications for Entra ID lifecycle events.

.DESCRIPTION
    Reads the Entra ID User Lifecycle audit log and sends an HTML
    notification for successful lifecycle events that have not yet
    been notified.

    Each audit event is identified by its permanent EventId.

    After an email is successfully sent, only the exact EventIds
    included in that successful notification are marked as Sent.

    Supports -WhatIf for safe dry-run testing.

.PARAMETER AdminEmail
    Email address of the administrator who should receive the notification.

.PARAMETER IncludeAllSuccessfulActions
    Includes all successful lifecycle actions instead of only
    successful Disable actions.

.EXAMPLE
    .\05-Send-AdminNotification.ps1 `
        -AdminEmail "admin@contoso.com" `
        -WhatIf

.EXAMPLE
    .\05-Send-AdminNotification.ps1 `
        -AdminEmail "admin@contoso.com"

.EXAMPLE
    .\05-Send-AdminNotification.ps1 `
        -AdminEmail "admin@contoso.com" `
        -IncludeAllSuccessfulActions

.NOTES
    Project: Entra-ID-User-Lifecycle-Automation
    Script: 05-Send-AdminNotification.ps1
    PowerShell: Windows PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess)]
param(

    [Parameter(Mandatory = $true)]
    [string]$AdminEmail,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAllSuccessfulActions
)

# ============================================================
# CONFIGURATION
# ============================================================

$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users",
    "Microsoft.Graph.Users.Actions"
)

$GraphScopes = @(
    "User.Read.All",
    "Mail.Send"
)

# ============================================================
# PROJECT PATHS
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$LogsPath = Join-Path `
    $ProjectRoot `
    "Logs"

$ReportsPath = Join-Path `
    $ProjectRoot `
    "Reports"

$AuditLogFile = Join-Path `
    $LogsPath `
    "EntraUserLifecycle_Audit.csv"

# ============================================================
# CREATE REPORT DIRECTORY
# ============================================================

if (-not (Test-Path -Path $ReportsPath)) {

    New-Item `
        -ItemType Directory `
        -Path $ReportsPath `
        -Force |
        Out-Null
}

$NotificationReportFile = Join-Path `
    $ReportsPath `
    (
        "Notification_{0}.csv" -f (
            Get-Date -Format "yyyyMMdd_HHmmss"
        )
    )

# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Entra ID User Lifecycle - Notification" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

# ============================================================
# VALIDATE ADMIN EMAIL
# ============================================================

if (
    $AdminEmail -notmatch
    '^[^@\s]+@[^@\s]+\.[^@\s]+$'
) {

    Write-Host ""
    Write-Host "ERROR: Invalid administrator email address." `
        -ForegroundColor Red

    exit 1
}

Write-Host "Notification recipient:" `
    -ForegroundColor Gray

Write-Host $AdminEmail `
    -ForegroundColor White

# ============================================================
# MODULE LOADER
# ============================================================

function Import-GraphModuleRobust {

    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {

        # ----------------------------------------------------
        # Already loaded
        # ----------------------------------------------------

        $LoadedModule = Get-Module `
            -Name $ModuleName

        if ($LoadedModule) {

            Write-Host `
                "Module already loaded: $ModuleName $($LoadedModule.Version)" `
                -ForegroundColor Green

            return
        }

        # ----------------------------------------------------
        # Normal module discovery
        # ----------------------------------------------------

        $AvailableModule = Get-Module `
            -ListAvailable `
            -Name $ModuleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($AvailableModule) {

            Import-Module `
                -Name $AvailableModule.Path `
                -Force `
                -ErrorAction Stop

            Write-Host `
                "Loaded module: $ModuleName $($AvailableModule.Version)" `
                -ForegroundColor Green

            return
        }

        # ----------------------------------------------------
        # Installed module location
        # ----------------------------------------------------

        $InstalledModule = Get-InstalledModule `
            -Name $ModuleName `
            -ErrorAction SilentlyContinue

        if ($InstalledModule) {

            $ModulePath = Join-Path `
                $InstalledModule.InstalledLocation `
                "$ModuleName.psd1"

            if (Test-Path -Path $ModulePath) {

                Import-Module `
                    -Name $ModulePath `
                    -Force `
                    -ErrorAction Stop

                Write-Host `
                    "Loaded module from installed location: $ModuleName $($InstalledModule.Version)" `
                    -ForegroundColor Green

                return
            }
        }

        # ----------------------------------------------------
        # User PowerShell module path
        # ----------------------------------------------------

        $UserModuleRoot = Join-Path `
            $HOME `
            "Documents\PowerShell\Modules\$ModuleName"

        if (Test-Path -Path $UserModuleRoot) {

            $VersionDirectories = Get-ChildItem `
                -Path $UserModuleRoot `
                -Directory `
                -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending

            foreach ($VersionDirectory in $VersionDirectories) {

                $ManifestPath = Join-Path `
                    $VersionDirectory.FullName `
                    "$ModuleName.psd1"

                if (Test-Path -Path $ManifestPath) {

                    Import-Module `
                        -Name $ManifestPath `
                        -Force `
                        -ErrorAction Stop

                    Write-Host `
                        "Loaded module from user PowerShell path: $ModuleName $($VersionDirectory.Name)" `
                        -ForegroundColor Green

                    return
                }
            }
        }

        throw `
            "Required Microsoft Graph module '$ModuleName' could not be found."
    }
    catch {

        Write-Host ""
        Write-Host `
            "ERROR: Failed to load module '$ModuleName'." `
            -ForegroundColor Red

        Write-Host `
            $_.Exception.Message `
            -ForegroundColor Red

        throw
    }
}

# ============================================================
# LOAD GRAPH MODULES
# ============================================================

Write-Host ""
Write-Host "Loading Microsoft Graph modules..." `
    -ForegroundColor Yellow

foreach ($Module in $RequiredModules) {

    Import-GraphModuleRobust `
        -ModuleName $Module
}

# ============================================================
# VERIFY GRAPH COMMANDS
# ============================================================

Write-Host ""
Write-Host "Verifying Microsoft Graph commands..." `
    -ForegroundColor Yellow

$RequiredCommands = @(
    "Connect-MgGraph",
    "Get-MgContext",
    "Send-MgUserMail"
)

foreach ($Command in $RequiredCommands) {

    $CommandObject = Get-Command `
        $Command `
        -ErrorAction SilentlyContinue

    if (-not $CommandObject) {

        Write-Host ""
        Write-Host `
            "ERROR: Required Microsoft Graph command '$Command' is not available." `
            -ForegroundColor Red

        exit 1
    }

    Write-Host `
        "$Command : OK" `
        -ForegroundColor Green
}

# ============================================================
# CHECK AUDIT LOG
# ============================================================

if (-not (Test-Path -Path $AuditLogFile)) {

    Write-Host ""
    Write-Host "ERROR: Audit log was not found." `
        -ForegroundColor Red

    Write-Host ""
    Write-Host "Expected location:" `
        -ForegroundColor Yellow

    Write-Host $AuditLogFile `
        -ForegroundColor Gray

    exit 1
}

Write-Host ""
Write-Host "Audit log found:" `
    -ForegroundColor Green

Write-Host $AuditLogFile `
    -ForegroundColor Gray

# ============================================================
# READ AUDIT LOG
# ============================================================

try {

    $AuditEntries = @(
        Import-Csv `
            -Path $AuditLogFile `
            -ErrorAction Stop
    )
}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to read audit log." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "Audit entries found: $($AuditEntries.Count)" `
    -ForegroundColor Cyan

if ($AuditEntries.Count -eq 0) {

    Write-Host ""
    Write-Host "No audit entries available for notification." `
        -ForegroundColor Yellow

    exit 0
}

# ============================================================
# VALIDATE AUDIT SCHEMA
# ============================================================

$RequiredAuditColumns = @(
    "EventId",
    "Timestamp",
    "Action",
    "DisplayName",
    "UserPrincipalName",
    "EmployeeLeaveDate",
    "PreviousAccountStatus",
    "NewAccountStatus",
    "Result",
    "NotificationStatus",
    "NotificationTimestamp"
)

$AuditPropertyNames = @(
    $AuditEntries[0].PSObject.Properties.Name
)

$MissingColumns = @(
    $RequiredAuditColumns | Where-Object {
        $_ -notin $AuditPropertyNames
    }
)

if ($MissingColumns.Count -gt 0) {

    Write-Host ""
    Write-Host "ERROR: Audit log uses an older or incompatible schema." `
        -ForegroundColor Red

    Write-Host ""
    Write-Host "Missing columns:" `
        -ForegroundColor Yellow

    foreach ($Column in $MissingColumns) {

        Write-Host "  - $Column" `
            -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Run the new Script 04 and create a new audit event." `
        -ForegroundColor Yellow

    exit 1
}

# ============================================================
# FIND SUCCESSFUL UNNOTIFIED EVENTS
# ============================================================

if ($IncludeAllSuccessfulActions) {

    $NotificationEntries = @(
        $AuditEntries | Where-Object {

            $_.Result -eq "Success" -and
            $_.NotificationStatus -ne "Sent" -and
            -not [string]::IsNullOrWhiteSpace($_.EventId)
        }
    )
}
else {

    $NotificationEntries = @(
        $AuditEntries | Where-Object {

            $_.Action -eq "Disable" -and
            $_.Result -eq "Success" -and
            $_.NotificationStatus -ne "Sent" -and
            -not [string]::IsNullOrWhiteSpace($_.EventId)
        }
    )
}

Write-Host ""
Write-Host `
    "Unnotified successful actions: $($NotificationEntries.Count)" `
    -ForegroundColor Cyan

# ============================================================
# NO NEW EVENTS
# ============================================================

if ($NotificationEntries.Count -eq 0) {

    Write-Host ""
    Write-Host `
        "No new lifecycle actions require notification." `
        -ForegroundColor Green

    exit 0
}

# ============================================================
# SORT EVENTS
# ============================================================

$NotificationEntries = @(
    $NotificationEntries |
        Sort-Object Timestamp
)

Write-Host ""
Write-Host `
    "Actions selected for notification: $($NotificationEntries.Count)" `
    -ForegroundColor Green

# ============================================================
# DISPLAY EVENTS
# ============================================================

Write-Host ""

$NotificationEntries |
    Select-Object `
        EventId,
        Timestamp,
        Action,
        DisplayName,
        UserPrincipalName,
        EmployeeLeaveDate,
        PreviousAccountStatus,
        NewAccountStatus,
        Result,
        NotificationStatus |
    Format-Table -AutoSize

# ============================================================
# CREATE HTML EMAIL ROWS
# ============================================================

$EmailRows = ""

foreach ($Entry in $NotificationEntries) {

    $EmailRows += @"
<tr>
    <td>$($Entry.EventId)</td>
    <td>$($Entry.Timestamp)</td>
    <td>$($Entry.Action)</td>
    <td>$($Entry.DisplayName)</td>
    <td>$($Entry.UserPrincipalName)</td>
    <td>$($Entry.EmployeeLeaveDate)</td>
    <td>$($Entry.PreviousAccountStatus)</td>
    <td>$($Entry.NewAccountStatus)</td>
    <td>$($Entry.Result)</td>
</tr>
"@
}

# ============================================================
# CREATE HTML EMAIL
# ============================================================

$EmailBody = @"
<html>

<head>

<style>

body {
    font-family: Arial, Helvetica, sans-serif;
    font-size: 14px;
    color: #222222;
}

h2 {
    margin-bottom: 10px;
}

p {
    margin-bottom: 15px;
}

table {
    border-collapse: collapse;
    width: 100%;
}

th,
td {
    border: 1px solid #cccccc;
    padding: 8px;
    text-align: left;
}

th {
    font-weight: bold;
}

.footer {
    margin-top: 20px;
    font-size: 12px;
}

</style>

</head>

<body>

<h2>Entra ID User Lifecycle Automation</h2>

<p>
The following lifecycle action(s) were completed successfully:
</p>

<table>

<tr>
    <th>Event ID</th>
    <th>Timestamp</th>
    <th>Action</th>
    <th>Display Name</th>
    <th>User Principal Name</th>
    <th>Leave Date</th>
    <th>Previous Status</th>
    <th>New Status</th>
    <th>Result</th>
</tr>

$EmailRows

</table>

<p class="footer">
This notification was generated automatically by the
Entra ID User Lifecycle Automation project.
</p>

</body>

</html>
"@

# ============================================================
# EMAIL SUBJECT
# ============================================================

$EmailSubject =
    "Entra ID Lifecycle Automation - $($NotificationEntries.Count) Action(s)"

# ============================================================
# WHATIF / DRY RUN
# ============================================================

if ($WhatIfPreference) {

    Write-Host ""
    Write-Host "=============================================" `
        -ForegroundColor Yellow

    Write-Host " DRY-RUN MODE" `
        -ForegroundColor Yellow

    Write-Host "=============================================" `
        -ForegroundColor Yellow

    Write-Host ""

    Write-Host "No email will be sent." `
        -ForegroundColor Yellow

    Write-Host ""

    Write-Host "Recipient:" `
        -ForegroundColor Gray

    Write-Host $AdminEmail `
        -ForegroundColor White

    Write-Host ""

    Write-Host "Subject:" `
        -ForegroundColor Gray

    Write-Host $EmailSubject `
        -ForegroundColor White

    Write-Host ""

    Write-Host "Notification preview:" `
        -ForegroundColor Cyan

    Write-Host ""

    foreach ($Entry in $NotificationEntries) {

        Write-Host "EventId : $($Entry.EventId)"
        Write-Host "Action  : $($Entry.Action)"
        Write-Host "User    : $($Entry.UserPrincipalName)"
        Write-Host "Result  : $($Entry.Result)"
        Write-Host ""
    }

    Write-Host "DRY-RUN COMPLETE." `
        -ForegroundColor Green

    Write-Host "No email was sent." `
        -ForegroundColor Green

    exit 0
}

# ============================================================
# CONNECT TO MICROSOFT GRAPH
# ============================================================

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." `
    -ForegroundColor Yellow

Write-Host ""

Write-Host "Required permissions:" `
    -ForegroundColor DarkGray

Write-Host "  User.Read.All" `
    -ForegroundColor DarkGray

Write-Host "  Mail.Send" `
    -ForegroundColor DarkGray

Write-Host ""

try {

    Connect-MgGraph `
        -Scopes $GraphScopes `
        -NoWelcome `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERROR: Microsoft Graph connection failed." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    exit 1
}

# ============================================================
# GET GRAPH CONTEXT
# ============================================================

$Context = Get-MgContext

if (-not $Context) {

    Write-Host ""
    Write-Host "ERROR: Unable to retrieve Graph context." `
        -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "Connected successfully." `
    -ForegroundColor Green

Write-Host ""

Write-Host "Account : $($Context.Account)" `
    -ForegroundColor Gray

Write-Host "Tenant  : $($Context.TenantId)" `
    -ForegroundColor Gray

# ============================================================
# DETERMINE SENDER
# ============================================================

$Sender = $Context.Account

if ([string]::IsNullOrWhiteSpace($Sender)) {

    Write-Host ""
    Write-Host "ERROR: Unable to determine sender account." `
        -ForegroundColor Red

    exit 1
}

# ============================================================
# SEND EMAIL
# ============================================================

Write-Host ""

Write-Host "Sending administrator notification..." `
    -ForegroundColor Yellow

Write-Host ""

Write-Host "From    : $Sender"
Write-Host "To      : $AdminEmail"
Write-Host "Subject : $EmailSubject"

$EmailSent = $false

try {

    $Message = @{

        Subject = $EmailSubject

        Body = @{

            ContentType = "HTML"

            Content = $EmailBody
        }

        ToRecipients = @(
            @{
                EmailAddress = @{
                    Address = $AdminEmail
                }
            }
        )
    }

    if (
        $PSCmdlet.ShouldProcess(
            $AdminEmail,
            "Send Entra ID lifecycle notification"
        )
    ) {

        Send-MgUserMail `
            -UserId $Sender `
            -Message $Message `
            -SaveToSentItems `
            -ErrorAction Stop

        $EmailSent = $true

        Write-Host ""
        Write-Host "SUCCESS: Notification email sent." `
            -ForegroundColor Green
    }
}
catch {

    Write-Host ""
    Write-Host "FAILED: Notification email could not be sent." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    exit 1
}

# ============================================================
# UPDATE NOTIFICATION STATUS
# ============================================================

if ($EmailSent) {

    $NotificationTimestamp = Get-Date `
        -Format "yyyy-MM-dd HH:mm:ss"

    $NotificationEventIds = @(
        $NotificationEntries |
            ForEach-Object {
                $_.EventId
            }
    )

    foreach ($AuditEntry in $AuditEntries) {

        if (
            $NotificationEventIds -contains
            $AuditEntry.EventId
        ) {

            $AuditEntry.NotificationStatus =
                "Sent"

            $AuditEntry.NotificationTimestamp =
                $NotificationTimestamp
        }
    }

    try {

        $AuditEntries |
            Export-Csv `
                -Path $AuditLogFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Force

        Write-Host ""
        Write-Host "Audit events marked as Sent." `
            -ForegroundColor Green
    }
    catch {

        Write-Host ""
        Write-Host `
            "WARNING: Email was sent, but audit notification status could not be saved." `
            -ForegroundColor Yellow

        Write-Host $_.Exception.Message `
            -ForegroundColor Yellow
    }
}

# ============================================================
# CREATE NOTIFICATION REPORT
# ============================================================

$NotificationResult = [PSCustomObject]@{

    Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Recipient       = $AdminEmail
    Sender          = $Sender
    ActionCount     = $NotificationEntries.Count
    Subject         = $EmailSubject
    Result          = "Success"
    EventIds        = (
        $NotificationEntries.EventId -join ";"
    )
}

try {

    $NotificationResult |
        Export-Csv `
            -Path $NotificationReportFile `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force

    Write-Host ""
    Write-Host "Notification result exported:" `
        -ForegroundColor Green

    Write-Host $NotificationReportFile `
        -ForegroundColor Gray
}
catch {

    Write-Host ""
    Write-Host `
        "WARNING: Notification result could not be exported." `
        -ForegroundColor Yellow
}

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host ""

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Notification Summary" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Recipient       : $AdminEmail"
Write-Host "Actions         : $($NotificationEntries.Count)"
Write-Host "Result          : Success"

Write-Host ""

Write-Host "Event IDs notified:" `
    -ForegroundColor Gray

foreach ($Entry in $NotificationEntries) {

    Write-Host "  $($Entry.EventId)" `
        -ForegroundColor Gray
}

Write-Host ""

Write-Host "Script completed successfully." `
    -ForegroundColor Green

Write-Host ""