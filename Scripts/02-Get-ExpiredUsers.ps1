#requires -Version 5.1

<#
.SYNOPSIS
    Detects Microsoft Entra ID users whose employee leave date has passed.

.DESCRIPTION
    This script connects to Microsoft Graph using read-only permissions,
    retrieves Entra ID users with employeeLeaveDateTime configured,
    identifies expired users, and exports the results to a CSV report.

    IMPORTANT:
    This script does NOT disable or modify any user accounts.

.NOTES
    Project: Entra-ID-User-Lifecycle-Automation
    Script: 02-Get-ExpiredUsers.ps1
    PowerShell: Windows PowerShell 5.1+
#>

[CmdletBinding()]
param()

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users"
)

$GraphScopes = @(
    "User.Read.All"
)

# ------------------------------------------------------------
# Project Paths
# ------------------------------------------------------------

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ReportsPath = Join-Path $ProjectRoot "Reports"

if (-not (Test-Path -Path $ReportsPath)) {
    New-Item -ItemType Directory -Path $ReportsPath -Force | Out-Null
}

$ReportFile = Join-Path $ReportsPath (
    "ExpiredUsers_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)

# ------------------------------------------------------------
# Helper Function - Load Required Module
# ------------------------------------------------------------

function Import-RequiredModule {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {

        # Check installed modules first.
        # This method is intentionally used because Windows PowerShell
        # may not always discover Microsoft Graph modules through
        # Get-Module -ListAvailable.

        $InstalledModule = Get-InstalledModule `
            -Name $ModuleName `
            -ErrorAction SilentlyContinue

        if ($InstalledModule) {

            Import-Module `
                -Name $ModuleName `
                -ErrorAction Stop

            Write-Host "Loaded module: $ModuleName" -ForegroundColor Green
            return
        }

        # Check whether the module is already loaded.
        $LoadedModule = Get-Module -Name $ModuleName

        if ($LoadedModule) {

            Write-Host "Module already loaded: $ModuleName" `
                -ForegroundColor Green

            return
        }

        throw "Required module '$ModuleName' is not installed."

    }
    catch {
        Write-Error "Failed to load module '$ModuleName'. $($_.Exception.Message)"
        throw
    }
}

# ------------------------------------------------------------
# Load Microsoft Graph Modules
# ------------------------------------------------------------

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Microsoft Entra ID - Expired User Detection" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

foreach ($Module in $RequiredModules) {

    Import-RequiredModule -ModuleName $Module
}

# ------------------------------------------------------------
# Verify Required Graph Commands
# ------------------------------------------------------------

$RequiredCommands = @(
    "Connect-MgGraph",
    "Get-MgContext",
    "Get-MgUser"
)

foreach ($Command in $RequiredCommands) {

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {

        throw "Required Microsoft Graph command '$Command' is not available."
    }
}

Write-Host ""
Write-Host "Required Microsoft Graph commands verified." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Connect to Microsoft Graph
# ------------------------------------------------------------

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Write-Host "Required permission: User.Read.All" -ForegroundColor DarkGray
Write-Host ""

try {

    Connect-MgGraph `
        -Scopes $GraphScopes `
        -NoWelcome `
        -ErrorAction Stop

}
catch {

    Write-Error "Microsoft Graph connection failed: $($_.Exception.Message)"
    exit 1
}

# ------------------------------------------------------------
# Display Graph Context
# ------------------------------------------------------------

$Context = Get-MgContext

if (-not $Context) {

    Write-Error "Unable to retrieve Microsoft Graph context."
    exit 1
}

Write-Host "Connected successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Account : $($Context.Account)" -ForegroundColor Gray
Write-Host "Tenant  : $($Context.TenantId)" -ForegroundColor Gray
Write-Host "Scopes  : $($Context.Scopes -join ', ')" -ForegroundColor Gray

# ------------------------------------------------------------
# Determine Current Date
# ------------------------------------------------------------

$Today = (Get-Date).Date

Write-Host ""
Write-Host "Today's Date: $($Today.ToString('yyyy-MM-dd'))" `
    -ForegroundColor Cyan

# ------------------------------------------------------------
# Retrieve Entra ID Users
# ------------------------------------------------------------

Write-Host ""
Write-Host "Retrieving users from Microsoft Entra ID..." `
    -ForegroundColor Yellow

try {

    $Users = Get-MgUser `
        -All `
        -Property Id,DisplayName,UserPrincipalName,AccountEnabled,EmployeeLeaveDateTime `
        -ErrorAction Stop

}
catch {

    Write-Error "Failed to retrieve users: $($_.Exception.Message)"
    exit 1
}

$TotalUsers = @($Users).Count

Write-Host "Total users retrieved: $TotalUsers" `
    -ForegroundColor Green

# ------------------------------------------------------------
# Find Users With Expiry Dates
# ------------------------------------------------------------

$UsersWithExpiryDate = @(
    $Users | Where-Object {
        $null -ne $_.EmployeeLeaveDateTime
    }
)

Write-Host ""
Write-Host "Users with expiry date: $(@($UsersWithExpiryDate).Count)" `
    -ForegroundColor Cyan

# ------------------------------------------------------------
# Detect Expired Users
# ------------------------------------------------------------

$ExpiredUsers = @(
    $UsersWithExpiryDate | Where-Object {

        $LeaveDate = $_.EmployeeLeaveDateTime.Date

        $LeaveDate -lt $Today
    }
)

Write-Host "Expired users: $(@($ExpiredUsers).Count)" `
    -ForegroundColor Yellow

# ------------------------------------------------------------
# Build Report
# ------------------------------------------------------------

$Report = @(
    $ExpiredUsers | ForEach-Object {

        $LeaveDate = $_.EmployeeLeaveDateTime.Date

        $DaysExpired = ($Today - $LeaveDate).Days

        $ActionRequired = if ($_.AccountEnabled -eq $true) {
            "Disable Account"
        }
        else {
            "Already Disabled"
        }

        [PSCustomObject]@{
            DisplayName          = $_.DisplayName
            UserPrincipalName    = $_.UserPrincipalName
            AccountEnabled       = $_.AccountEnabled
            EmployeeLeaveDate    = $LeaveDate.ToString("yyyy-MM-dd")
            DaysExpired          = $DaysExpired
            ActionRequired       = $ActionRequired
            UserId               = $_.Id
        }
    }
)

# ------------------------------------------------------------
# Display Results
# ------------------------------------------------------------

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan
Write-Host " Expired User Detection Results" `
    -ForegroundColor Cyan
Write-Host "=============================================" `
    -ForegroundColor Cyan
Write-Host ""

if ($Report.Count -eq 0) {

    Write-Host "No expired users found." -ForegroundColor Green
    Write-Host ""
    Write-Host "No accounts require action." -ForegroundColor Green

}
else {

    Write-Host "Expired users found: $($Report.Count)" `
        -ForegroundColor Red

    Write-Host ""

    $Report |
        Select-Object `
            DisplayName,
            UserPrincipalName,
            AccountEnabled,
            EmployeeLeaveDate,
            DaysExpired,
            ActionRequired |
        Format-Table -AutoSize

    # --------------------------------------------------------
    # Export CSV Report
    # --------------------------------------------------------

    try {

        $Report |
            Export-Csv `
                -Path $ReportFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Force

        Write-Host ""
        Write-Host "Report exported successfully:" `
            -ForegroundColor Green

        Write-Host $ReportFile -ForegroundColor White

    }
    catch {

        Write-Error "Failed to export report: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$ExpiredEnabledUsers = @(
    $Report | Where-Object {
        $_.AccountEnabled -eq $true
    }
)

$AlreadyDisabledUsers = @(
    $Report | Where-Object {
        $_.AccountEnabled -eq $false
    }
)

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host "Total users              : $TotalUsers"
Write-Host "Users with expiry date   : $(@($UsersWithExpiryDate).Count)"
Write-Host "Expired users            : $($Report.Count)"
Write-Host "Expired + Enabled        : $($ExpiredEnabledUsers.Count)"
Write-Host "Expired + Already Disabled: $($AlreadyDisabledUsers.Count)"

Write-Host ""
Write-Host "IMPORTANT: This script is READ-ONLY." `
    -ForegroundColor Yellow

Write-Host "No user accounts were modified." `
    -ForegroundColor Yellow

Write-Host ""
Write-Host "Script completed successfully." `
    -ForegroundColor Green