#requires -Version 5.1

<#
.SYNOPSIS
    Sends administrator notifications for Entra ID lifecycle actions.

.DESCRIPTION
    Reads successful, unnotified lifecycle events from the local audit log
    and sends an administrator email using Microsoft Graph.

    The email includes:

        Event ID
        Timestamp
        Action
        Display Name
        User Principal Name
        Leave Date
        Previous Status
        New Status
        Result
        Performed By
        Computer

.PARAMETER AdminEmail
    Email address that receives the notification.

.PARAMETER WhatIf
    Previews the notification without sending email.

.PARAMETER IncludeAllSuccessfulActions
    Includes all successful lifecycle actions, including:

        Disable
        RemoveLicense
        Set Expiry
        Detect Expired
        Skip
        Other
#>

[CmdletBinding(SupportsShouldProcess)]
param(

    [Parameter(Mandatory = $true)]
    [string]$AdminEmail,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAllSuccessfulActions
)

# ============================================================
# Configuration
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

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$LogsPath = Join-Path `
    $ProjectRoot `
    "Logs"

$ReportsPath = Join-Path `
    $ProjectRoot `
    "Reports"

$AuditLogPath = Join-Path `
    $LogsPath `
    "EntraUserLifecycle_Audit.csv"

$NotificationReportPath = Join-Path `
    $ReportsPath `
    ("Notification_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# ============================================================
# Header
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Entra ID User Lifecycle - Notification" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Notification recipient:"
Write-Host $AdminEmail `
    -ForegroundColor White

# ============================================================
# Validate Email
# ============================================================

if (
    $AdminEmail -notmatch `
    '^[^@\s]+@[^@\s]+\.[^@\s]+$'
) {

    Write-Host ""
    Write-Host "ERROR: Invalid administrator email address." `
        -ForegroundColor Red

    return
}

# ============================================================
# WhatIf
# ============================================================

if ($WhatIfPreference) {

    Write-Host ""
    Write-Host "Execution Mode : WHATIF" `
        -ForegroundColor Yellow

    Write-Host "No email will be sent." `
        -ForegroundColor Yellow
}
else {

    Write-Host ""
    Write-Host "Execution Mode : LIVE" `
        -ForegroundColor Green
}

# ============================================================
# Validate Required Modules
# ============================================================

Write-Host ""
Write-Host "Loading Microsoft Graph modules..." `
    -ForegroundColor Cyan

foreach ($ModuleName in $RequiredModules) {

    try {

        Import-Module `
            $ModuleName `
            -ErrorAction Stop

        $Module = Get-Module `
            $ModuleName

        Write-Host "Module loaded: $ModuleName $($Module.Version)" `
            -ForegroundColor Green
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Required module unavailable:" `
            -ForegroundColor Red

        Write-Host $ModuleName `
            -ForegroundColor Red

        Write-Host ""
        Write-Host "Install with:" `
            -ForegroundColor Yellow

        Write-Host "Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber" `
            -ForegroundColor Gray

        return
    }
}

# ============================================================
# Validate Commands
# ============================================================

Write-Host ""
Write-Host "Verifying Microsoft Graph commands..." `
    -ForegroundColor Cyan

$RequiredCommands = @(
    "Connect-MgGraph",
    "Get-MgContext",
    "Send-MgUserMail"
)

foreach ($CommandName in $RequiredCommands) {

    if (Get-Command `
        -Name $CommandName `
        -ErrorAction SilentlyContinue) {

        Write-Host "$CommandName : OK" `
            -ForegroundColor Green
    }
    else {

        Write-Host ""
        Write-Host "ERROR: Command unavailable: $CommandName" `
            -ForegroundColor Red

        return
    }
}

# ============================================================
# Audit Log Validation
# ============================================================

if (-not (Test-Path -Path $AuditLogPath -PathType Leaf)) {

    Write-Host ""
    Write-Host "Audit log not found:" `
        -ForegroundColor Yellow

    Write-Host $AuditLogPath `
        -ForegroundColor Gray

    return
}

Write-Host ""
Write-Host "Audit log found:"
Write-Host $AuditLogPath `
    -ForegroundColor Gray

# ============================================================
# Read Audit Log
# ============================================================

try {

    $AuditData = @(
        Import-Csv `
            -Path $AuditLogPath `
            -ErrorAction Stop
    )
}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to read audit log." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

Write-Host ""
Write-Host "Audit entries found: $($AuditData.Count)" `
    -ForegroundColor Cyan

if ($AuditData.Count -eq 0) {

    Write-Host ""
    Write-Host "No audit events available for notification." `
        -ForegroundColor Yellow

    return
}

# ============================================================
# Select Successful Unnotified Events
# ============================================================

$SuccessfulEvents = @(
    $AuditData |
        Where-Object {

            $_.Result -eq "Success" -and
            $_.EventId -and
            $_.NotificationStatus -ne "Sent"
        }
)

# Default behavior:
# Only lifecycle actions that normally represent completed work.

if (-not $IncludeAllSuccessfulActions) {

    $SuccessfulEvents = @(
        $SuccessfulEvents |
            Where-Object {
                $_.Action -eq "Disable"
            }
    )
}

Write-Host ""
Write-Host "Unnotified successful actions: $($SuccessfulEvents.Count)" `
    -ForegroundColor Cyan

if ($SuccessfulEvents.Count -eq 0) {

    Write-Host ""
    Write-Host "No successful unnotified lifecycle actions found." `
        -ForegroundColor Green

    return
}

Write-Host ""
Write-Host "Actions selected for notification: $($SuccessfulEvents.Count)" `
    -ForegroundColor Green

# ============================================================
# Display Selected Events
# ============================================================

Write-Host ""

$SuccessfulEvents |
    Format-Table `
        EventId,
        Timestamp,
        Action,
        DisplayName,
        UserPrincipalName,
        Result,
        PerformedBy,
        ComputerName `
        -AutoSize

# ============================================================
# Connect Microsoft Graph
# ============================================================

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." `
    -ForegroundColor Cyan

Write-Host ""
Write-Host "Required permissions:"
Write-Host "  User.Read.All"
Write-Host "  Mail.Send"

try {

    $GraphContext = Get-MgContext `
        -ErrorAction SilentlyContinue

    $NeedsConnection = $true

    if ($null -ne $GraphContext) {

        $ExistingScopes = @(
            $GraphContext.Scopes
        )

        if (
            $ExistingScopes -contains "Mail.Send" -and
            $ExistingScopes -contains "User.Read.All"
        ) {

            $NeedsConnection = $false
        }
    }

    if ($NeedsConnection) {

        Connect-MgGraph `
            -Scopes $GraphScopes `
            -NoWelcome `
            -ErrorAction Stop | Out-Null
    }

    $GraphContext = Get-MgContext `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "Connected successfully." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Account : $($GraphContext.Account)"
    Write-Host "Tenant  : $($GraphContext.TenantId)"
}
catch {

    Write-Host ""
    Write-Host "ERROR: Microsoft Graph connection failed." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

# ============================================================
# Build Email HTML
# ============================================================

$RowsHtml = ""

foreach ($Event in $SuccessfulEvents) {

    $PerformedBy = if (
        [string]::IsNullOrWhiteSpace($Event.PerformedBy)
    ) {
        "Not Available"
    }
    else {
        $Event.PerformedBy
    }

    $Computer = if (
        [string]::IsNullOrWhiteSpace($Event.ComputerName)
    ) {
        "Not Available"
    }
    else {
        $Event.ComputerName
    }

    $RowsHtml += @"
<tr>
<td>$($Event.EventId)</td>
<td>$($Event.Timestamp)</td>
<td>$($Event.Action)</td>
<td>$($Event.DisplayName)</td>
<td>$($Event.UserPrincipalName)</td>
<td>$($Event.EmployeeLeaveDate)</td>
<td>$($Event.PreviousAccountStatus)</td>
<td>$($Event.NewAccountStatus)</td>
<td>$($Event.Result)</td>
<td>$PerformedBy</td>
<td>$Computer</td>
</tr>
"@
}

$ActionCount = $SuccessfulEvents.Count

$Subject = "Entra ID Lifecycle Automation - $ActionCount Action(s)"

$HtmlBody = @"
<html>
<head>
<style>
body {
    font-family: Arial, Helvetica, sans-serif;
    font-size: 14px;
    color: #222222;
}

h2 {
    color: #1f4e79;
}

table {
    border-collapse: collapse;
    width: 100%;
}

th {
    background-color: #f2f2f2;
    border: 1px solid #cccccc;
    padding: 8px;
    text-align: left;
}

td {
    border: 1px solid #cccccc;
    padding: 8px;
    white-space: nowrap;
}

.footer {
    margin-top: 20px;
    color: #666666;
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
<th>Performed By</th>
<th>Computer</th>
</tr>

$RowsHtml

</table>

<p class="footer">
This notification was generated automatically by the
Entra ID User Lifecycle Automation project.
</p>

</body>
</html>
"@

# ============================================================
# WhatIf Preview
# ============================================================

if ($WhatIfPreference) {

    Write-Host ""
    Write-Host "WHATIF: Email would be sent to:" `
        -ForegroundColor Yellow

    Write-Host $AdminEmail `
        -ForegroundColor White

    Write-Host ""
    Write-Host "Subject:"
    Write-Host $Subject `
        -ForegroundColor White

    Write-Host ""
    Write-Host "Performed By values:"

    $SuccessfulEvents |
        Select-Object -ExpandProperty PerformedBy -Unique |
        ForEach-Object {
            Write-Host "  $_" `
                -ForegroundColor Gray
        }

    Write-Host ""
    Write-Host "WHATIF complete. No email was sent." `
        -ForegroundColor Green

    return
}

# ============================================================
# Send Email
# ============================================================

Write-Host ""
Write-Host "Sending administrator notification..." `
    -ForegroundColor Cyan

Write-Host ""
Write-Host "From    : $($GraphContext.Account)"
Write-Host "To      : $AdminEmail"
Write-Host "Subject : $Subject"

$Message = @{
    Subject = $Subject

    Body = @{
        ContentType = "HTML"
        Content     = $HtmlBody
    }

    ToRecipients = @(
        @{
            EmailAddress = @{
                Address = $AdminEmail
            }
        }
    )
}

try {

    Send-MgUserMail `
        -UserId $GraphContext.Account `
        -Message $Message `
        -SaveToSentItems `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "SUCCESS: Notification email sent." `
        -ForegroundColor Green
}
catch {

    Write-Host ""
    Write-Host "ERROR: Failed to send notification email." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

# ============================================================
# Mark Events as Sent
# ============================================================

try {

    $UpdatedAuditData = @(
        Import-Csv `
            -Path $AuditLogPath `
            -ErrorAction Stop
    )

    $NotifiedEventIds = @(
        $SuccessfulEvents |
            Select-Object -ExpandProperty EventId
    )

    foreach ($AuditEvent in $UpdatedAuditData) {

        if (
            $NotifiedEventIds -contains $AuditEvent.EventId
        ) {

            $AuditEvent.NotificationStatus = "Sent"

            $AuditEvent.NotificationTimestamp =
                Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }

    $UpdatedAuditData |
        Export-Csv `
            -Path $AuditLogPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -ErrorAction Stop

    Write-Host ""
    Write-Host "Audit events marked as Sent." `
        -ForegroundColor Green
}
catch {

    Write-Host ""
    Write-Host "WARNING: Email was sent, but audit status could not be updated." `
        -ForegroundColor Yellow

    Write-Host $_.Exception.Message `
        -ForegroundColor Yellow
}

# ============================================================
# Notification Report
# ============================================================

try {

    $SuccessfulEvents |
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
            PerformedBy,
            ComputerName |
        Export-Csv `
            -Path $NotificationReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -ErrorAction Stop

    Write-Host ""
    Write-Host "Notification result exported:"
    Write-Host $NotificationReportPath `
        -ForegroundColor Gray
}
catch {

    Write-Host ""
    Write-Host "WARNING: Unable to export notification report." `
        -ForegroundColor Yellow
}

# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Notification Summary" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host "Recipient : $AdminEmail"
Write-Host "Actions   : $ActionCount"
Write-Host "Result    : Success" `
    -ForegroundColor Green

Write-Host ""
Write-Host "Event IDs notified:"

foreach ($Event in $SuccessfulEvents) {

    Write-Host "  $($Event.EventId)"
}

Write-Host ""
Write-Host "Script completed successfully." `
    -ForegroundColor Green
