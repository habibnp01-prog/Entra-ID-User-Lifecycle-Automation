#requires -Version 5.1

<#
.SYNOPSIS
    Detects Microsoft Entra ID users whose employee leave date has expired.

.DESCRIPTION
    Retrieves Microsoft Entra ID users with an EmployeeLeaveDateTime value
    and identifies users whose leave date is before today's date.

    This script is READ-ONLY against Microsoft Entra ID.

    It does NOT:
        - Disable users
        - Remove licenses
        - Modify users
        - Send emails
        - Write audit events

    It DOES:
        - Read users from Microsoft Entra ID
        - Identify expired users
        - Display results
        - Export an expired-user report

.NOTES
    Required Microsoft Graph Permission:
        User.Read.All

    Required Modules:
        Microsoft.Graph.Authentication
        Microsoft.Graph.Users
#>

[CmdletBinding()]
param()

# ============================================================
# Configuration
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot

$ReportsPath = Join-Path $ProjectRoot "Reports"

$GraphScopes = @(
    "User.Read.All"
)

$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users"
)

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

function Test-RequiredModules {

    foreach ($ModuleName in $RequiredModules) {

        $LoadedModule = Get-Module -Name $ModuleName

        if ($LoadedModule) {
            Write-Host "Loaded module: $ModuleName" -ForegroundColor Green
            continue
        }

        $AvailableModule = Get-Module -ListAvailable -Name $ModuleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $AvailableModule) {

            Write-Host ""
            Write-Host "ERROR: Required module '$ModuleName' is not installed." -ForegroundColor Red
            Write-Host ""
            Write-Host "Install it using:" -ForegroundColor Yellow
            Write-Host "Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber" -ForegroundColor White
            Write-Host ""

            throw "Required module '$ModuleName' is missing."
        }

        Import-Module $AvailableModule.Path -ErrorAction Stop

        Write-Host "Loaded module: $ModuleName" -ForegroundColor Green
    }
}

function Test-RequiredGraphCommands {

    $RequiredCommands = @(
        "Connect-MgGraph",
        "Get-MgContext",
        "Get-MgUser"
    )

    foreach ($CommandName in $RequiredCommands) {

        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue

        if (-not $Command) {
            throw "Required Microsoft Graph command '$CommandName' was not found."
        }
    }

    Write-Host ""
    Write-Host "Required Microsoft Graph commands verified." -ForegroundColor Green
}

function Connect-ToGraph {

    Write-Host ""
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Write-Host "Required permission: User.Read.All" -ForegroundColor Gray
    Write-Host ""

    $Context = Get-MgContext -ErrorAction SilentlyContinue

    $NeedsConnection = $true

    if ($Context) {

        $ExistingScopes = @($Context.Scopes)

        if ($ExistingScopes -contains "User.Read.All") {

            Write-Host "Existing Microsoft Graph session found." -ForegroundColor Green
            Write-Host "Using existing session." -ForegroundColor Green

            $NeedsConnection = $false
        }
    }

    if ($NeedsConnection) {

        Connect-MgGraph `
            -Scopes $GraphScopes `
            -NoWelcome `
            -ErrorAction Stop
    }

    $Context = Get-MgContext -ErrorAction Stop

    if (-not $Context) {
        throw "Microsoft Graph connection could not be established."
    }

    Write-Host "Connected successfully." -ForegroundColor Green
    Write-Host ""

    Write-Host "Account : $($Context.Account)" -ForegroundColor White
    Write-Host "Tenant  : $($Context.TenantId)" -ForegroundColor White
    Write-Host "Scopes  : $($Context.Scopes -join ', ')" -ForegroundColor DarkGray
}

# ============================================================
# Start
# ============================================================

Write-Section "Microsoft Entra ID - Expired User Detection"

# ============================================================
# Validate Modules
# ============================================================

Test-RequiredModules

Test-RequiredGraphCommands

# ============================================================
# Connect to Microsoft Graph
# ============================================================

Connect-ToGraph

# ============================================================
# Prepare Reports Directory
# ============================================================

if (-not (Test-Path -Path $ReportsPath)) {

    New-Item `
        -Path $ReportsPath `
        -ItemType Directory `
        -Force `
        -ErrorAction Stop | Out-Null
}

# ============================================================
# Today's Date
# ============================================================

$Today = (Get-Date).Date

Write-Host ""
Write-Host "Today's Date: $($Today.ToString('yyyy-MM-dd'))" -ForegroundColor White

# ============================================================
# Retrieve Users
# ============================================================

Write-Host ""
Write-Host "Retrieving users from Microsoft Entra ID..." -ForegroundColor Yellow

$Users = Get-MgUser `
    -All `
    -Property Id,DisplayName,UserPrincipalName,AccountEnabled,EmployeeLeaveDateTime `
    -ErrorAction Stop

Write-Host "Total users retrieved: $($Users.Count)" -ForegroundColor Green

# ============================================================
# Users With Expiry Date
# ============================================================

$UsersWithExpiry = @(
    $Users | Where-Object {
        $null -ne $_.EmployeeLeaveDateTime
    }
)

Write-Host ""
Write-Host "Users with expiry date: $($UsersWithExpiry.Count)" -ForegroundColor White

# ============================================================
# Find Expired Users
# ============================================================

$ExpiredUsers = @(
    $UsersWithExpiry | Where-Object {

        $LeaveDate = ([datetime]$_.EmployeeLeaveDateTime).Date

        $LeaveDate -lt $Today
    }
)

Write-Host "Expired users: $($ExpiredUsers.Count)" -ForegroundColor Yellow

# ============================================================
# Build Results
# ============================================================

$Results = foreach ($User in $ExpiredUsers) {

    $LeaveDate = ([datetime]$User.EmployeeLeaveDateTime).Date

    $DaysExpired = ($Today - $LeaveDate).Days

    $ActionRequired = if ($User.AccountEnabled -eq $true) {
        "Disable Account"
    }
    else {
        "Already Disabled"
    }

    [PSCustomObject]@{
        DisplayName          = $User.DisplayName
        UserPrincipalName    = $User.UserPrincipalName
        AccountEnabled       = $User.AccountEnabled
        EmployeeLeaveDate    = $LeaveDate.ToString("yyyy-MM-dd")
        DaysExpired          = $DaysExpired
        ActionRequired       = $ActionRequired
        UserId               = $User.Id
    }
}

# ============================================================
# Display Results
# ============================================================

Write-Section "Expired User Detection Results"

Write-Host "Expired users found: $($Results.Count)" -ForegroundColor Yellow
Write-Host ""

if ($Results.Count -gt 0) {

    $Results |
        Select-Object `
            DisplayName,
            UserPrincipalName,
            AccountEnabled,
            EmployeeLeaveDate,
            DaysExpired,
            ActionRequired |
        Format-Table -AutoSize
}
else {

    Write-Host "No expired users found." -ForegroundColor Green
}

# ============================================================
# Export Report
# ============================================================
#
# IMPORTANT:
# This script intentionally does NOT use ShouldProcess for
# Export-Csv.
#
# Therefore -WhatIf from the parent orchestrator will NOT
# prevent the detection report from being created.
#
# The CSV is only a local report and does not modify Entra ID.
# ============================================================

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$ReportPath = Join-Path `
    $ReportsPath `
    "ExpiredUsers_$Timestamp.csv"

if ($Results.Count -gt 0) {

    $Results |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force `
            -ErrorAction Stop
}
else {

    # Create an empty report with the expected headers
    $EmptyReport = [PSCustomObject]@{
        DisplayName       = ""
        UserPrincipalName = ""
        AccountEnabled    = ""
        EmployeeLeaveDate = ""
        DaysExpired       = ""
        ActionRequired    = ""
        UserId            = ""
    }

    $EmptyReport |
        Select-Object `
            DisplayName,
            UserPrincipalName,
            AccountEnabled,
            EmployeeLeaveDate,
            DaysExpired,
            ActionRequired,
            UserId |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force `
            -ErrorAction Stop
}

# ============================================================
# Verify Report Exists
# ============================================================

if (-not (Test-Path -Path $ReportPath)) {

    throw "The expired-user report could not be created: $ReportPath"
}

$ReportFile = Get-Item -Path $ReportPath -ErrorAction Stop

Write-Host ""
Write-Host "Report exported successfully:" -ForegroundColor Green
Write-Host $ReportFile.FullName -ForegroundColor White

# ============================================================
# Summary
# ============================================================

$ExpiredEnabled = @(
    $Results | Where-Object {
        $_.AccountEnabled -eq $true
    }
)

$ExpiredDisabled = @(
    $Results | Where-Object {
        $_.AccountEnabled -eq $false
    }
)

Write-Section "Summary"

Write-Host "Total users              : $($Users.Count)" -ForegroundColor White
Write-Host "Users with expiry date   : $($UsersWithExpiry.Count)" -ForegroundColor White
Write-Host "Expired users            : $($Results.Count)" -ForegroundColor Yellow
Write-Host "Expired + Enabled        : $($ExpiredEnabled.Count)" -ForegroundColor Yellow
Write-Host "Expired + Already Disabled: $($ExpiredDisabled.Count)" -ForegroundColor Gray

Write-Host ""
Write-Host "IMPORTANT: This script is READ-ONLY." -ForegroundColor Cyan
Write-Host "No user accounts were modified." -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Return Report Information to Orchestrator
# ============================================================

[PSCustomObject]@{
    Status               = "Success"
    TotalUsers           = $Users.Count
    UsersWithExpiry      = $UsersWithExpiry.Count
    ExpiredUsers         = $Results.Count
    ExpiredEnabled       = $ExpiredEnabled.Count
    ExpiredAlreadyDisabled = $ExpiredDisabled.Count
    ReportPath           = $ReportFile.FullName
}

Write-Host "Script completed successfully." -ForegroundColor Green