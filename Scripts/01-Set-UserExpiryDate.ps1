<#
.SYNOPSIS
    Sets the Microsoft Entra ID employee leave/expiry date for a user.

.DESCRIPTION
    This script:
    1. Checks the required Microsoft Graph modules.
    2. Imports the required Graph modules.
    3. Connects to Microsoft Graph.
    4. Finds a user by User Principal Name (UPN).
    5. Displays the current employeeLeaveDateTime.
    6. Accepts a new expiry/leave date in YYYY-MM-DD format.
    7. Displays a change summary.
    8. Requests confirmation before making the change.
    9. Updates employeeLeaveDateTime.
    10. Verifies the updated value.

.NOTES
    Project : Entra ID User Lifecycle Automation
    Script  : 01-Set-UserExpiryDate.ps1
    Version : 1.0.1

.REQUIREMENTS
    PowerShell 5.1 or PowerShell 7
    Microsoft.Graph.Authentication
    Microsoft.Graph.Users

    Microsoft Graph Permission:
    User.ReadWrite.All
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# ============================================================
# Configuration
# ============================================================

$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users"
)

$GraphScopes = @(
    "User.ReadWrite.All"
)

# ============================================================
# Function: Test Required Module
# ============================================================

function Test-RequiredModule {

    param (
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    # Check if module is already loaded
    $LoadedModule = Get-Module -Name $ModuleName

    if ($LoadedModule) {
        return $true
    }

    # Check PowerShellGet
    $InstalledModule = Get-InstalledModule `
        -Name $ModuleName `
        -ErrorAction SilentlyContinue

    if ($InstalledModule) {
        return $true
    }

    Write-Host ""
    Write-Host "Required module '$ModuleName' was not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install it using:" -ForegroundColor Yellow
    Write-Host "Install-Module $ModuleName -Scope CurrentUser" -ForegroundColor Cyan
    Write-Host ""

    return $false
}

# ============================================================
# Function: Import Required Module
# ============================================================

function Import-RequiredModule {

    param (
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    try {

        Import-Module $ModuleName -ErrorAction Stop

        Write-Host "Loaded module: $ModuleName" -ForegroundColor Green

        return $true
    }
    catch {

        Write-Host ""
        Write-Host "Failed to import module: $ModuleName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""

        return $false
    }
}

# ============================================================
# Banner
# ============================================================

Clear-Host

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Microsoft Entra ID User Lifecycle Automation" -ForegroundColor Cyan
Write-Host " Set User Expiry Date" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Check Required Modules
# ============================================================

foreach ($Module in $RequiredModules) {

    Write-Host "Checking module: $Module" -ForegroundColor Gray

    if (-not (Test-RequiredModule -ModuleName $Module)) {

        Write-Host ""
        Write-Host "Required module is missing." -ForegroundColor Red

        exit 1
    }
}

Write-Host ""
Write-Host "All required modules are installed." -ForegroundColor Green

# ============================================================
# Import Required Modules
# ============================================================

foreach ($Module in $RequiredModules) {

    if (-not (Import-RequiredModule -ModuleName $Module)) {

        Write-Host ""
        Write-Host "Module import failed. Script cannot continue." -ForegroundColor Red

        exit 1
    }
}

# ============================================================
# Verify Required Microsoft Graph Commands
# ============================================================

$RequiredCommands = @(
    "Connect-MgGraph",
    "Get-MgContext",
    "Get-MgUser",
    "Update-MgUser"
)

Write-Host ""
Write-Host "Verifying Microsoft Graph commands..." -ForegroundColor Gray

foreach ($Command in $RequiredCommands) {

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {

        Write-Host ""
        Write-Host "Required command not available: $Command" -ForegroundColor Red

        exit 1
    }
}

Write-Host "Microsoft Graph commands are available." -ForegroundColor Green

# ============================================================
# Connect to Microsoft Graph
# ============================================================

Write-Host ""
Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Gray

try {

    $GraphContext = Get-MgContext

    if (-not $GraphContext) {

        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

        Connect-MgGraph `
            -Scopes $GraphScopes `
            -NoWelcome `
            -ErrorAction Stop

        $GraphContext = Get-MgContext
    }

    if (-not $GraphContext) {

        throw "Microsoft Graph authentication failed."
    }

    Write-Host ""
    Write-Host "Connected to Microsoft Graph successfully." -ForegroundColor Green

    Write-Host "Account : $($GraphContext.Account)" -ForegroundColor Gray
    Write-Host "Tenant  : $($GraphContext.TenantId)" -ForegroundColor Gray

}
catch {

    Write-Host ""
    Write-Host "Microsoft Graph connection failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}

# ============================================================
# User Selection
# ============================================================

Write-Host ""
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host " User Selection" -ForegroundColor Cyan
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

do {

    $UserPrincipalName = Read-Host "Enter User Principal Name (UPN)"

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {

        Write-Host ""
        Write-Host "UPN cannot be empty." -ForegroundColor Red
    }

}
until (-not [string]::IsNullOrWhiteSpace($UserPrincipalName))

# Remove accidental spaces
$UserPrincipalName = $UserPrincipalName.Trim()

# ============================================================
# Get User
# ============================================================

Write-Host ""
Write-Host "Searching for user..." -ForegroundColor Cyan

try {

    $User = Get-MgUser `
        -UserId $UserPrincipalName `
        -Property Id,DisplayName,UserPrincipalName,AccountEnabled,EmployeeLeaveDateTime `
        -ErrorAction Stop

}
catch {

    Write-Host ""
    Write-Host "User could not be found." -ForegroundColor Red
    Write-Host "UPN: $UserPrincipalName" -ForegroundColor Yellow
    Write-Host ""

    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}

# ============================================================
# Display Current User Information
# ============================================================

Write-Host ""
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host " Current User Information" -ForegroundColor Cyan
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

Write-Host "Display Name       : $($User.DisplayName)"
Write-Host "User Principal Name: $($User.UserPrincipalName)"
Write-Host "Account Enabled    : $($User.AccountEnabled)"

if ($User.EmployeeLeaveDateTime) {

    Write-Host "Current Expiry Date: $($User.EmployeeLeaveDateTime)"

}
else {

    Write-Host "Current Expiry Date: Not Set" -ForegroundColor Yellow
}

# ============================================================
# Get New Expiry Date
# ============================================================

Write-Host ""
Write-Host "---------------------------------------------" -ForegroundColor DarkGray
Write-Host " New Expiry Date" -ForegroundColor Cyan
Write-Host "---------------------------------------------" -ForegroundColor DarkGray

do {

    $ExpiryDateInput = Read-Host "Enter expiry/leave date (YYYY-MM-DD)"

    $ExpiryDate = $null

    try {

        # PowerShell 5.1 compatible date parsing
        $ExpiryDate = [datetime]::ParseExact(
            $ExpiryDateInput.Trim(),
            "yyyy-MM-dd",
            [System.Globalization.CultureInfo]::InvariantCulture
        )

        $ValidDate = $true

    }
    catch {

        $ValidDate = $false

        Write-Host ""
        Write-Host "Invalid date format." -ForegroundColor Red
        Write-Host "Please use YYYY-MM-DD." -ForegroundColor Yellow
        Write-Host "Example: 2026-12-31" -ForegroundColor Yellow
    }

}
until ($ValidDate)

# ============================================================
# Set Date to Midnight UTC
# ============================================================

$ExpiryDateUtc = [datetime]::SpecifyKind(
    $ExpiryDate,
    [System.DateTimeKind]::Utc
)

# ============================================================
# Change Summary
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
Write-Host " Change Summary" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Yellow

Write-Host ""
Write-Host "User:"
Write-Host "  $($User.UserPrincipalName)"

Write-Host ""
Write-Host "Current Expiry Date:"
if ($User.EmployeeLeaveDateTime) {
    Write-Host "  $($User.EmployeeLeaveDateTime)"
}
else {
    Write-Host "  Not Set"
}

Write-Host ""
Write-Host "New Expiry Date:"
Write-Host "  $($ExpiryDateUtc.ToString("yyyy-MM-dd"))"

Write-Host ""
Write-Host "Account Enabled:"
Write-Host "  $($User.AccountEnabled)"

# ============================================================
# Confirmation
# ============================================================

Write-Host ""

$Confirmation = Read-Host "Apply this change? (Y/N)"

if ($Confirmation -notin @("Y", "y")) {

    Write-Host ""
    Write-Host "Operation cancelled. No changes were made." -ForegroundColor Yellow

    exit 0
}

# ============================================================
# Update Employee Leave Date
# ============================================================

Write-Host ""
Write-Host "Updating Microsoft Entra ID..." -ForegroundColor Cyan

try {

    if ($PSCmdlet.ShouldProcess(
        $User.UserPrincipalName,
        "Set employeeLeaveDateTime to $($ExpiryDateUtc.ToString("yyyy-MM-dd"))"
    )) {

        Update-MgUser `
            -UserId $User.Id `
            -EmployeeLeaveDateTime $ExpiryDateUtc `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "Expiry date updated successfully." -ForegroundColor Green
    }

}
catch {

    Write-Host ""
    Write-Host "Failed to update the expiry date." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}

# ============================================================
# Verification
# ============================================================

Write-Host ""
Write-Host "Verifying the change..." -ForegroundColor Cyan

try {

    $UpdatedUser = Get-MgUser `
        -UserId $User.Id `
        -Property Id,DisplayName,UserPrincipalName,EmployeeLeaveDateTime `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host " Verification Result" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "User:"
    Write-Host "  $($UpdatedUser.UserPrincipalName)"

    Write-Host ""
    Write-Host "Expiry Date:"
    Write-Host "  $($UpdatedUser.EmployeeLeaveDateTime)"

    if ($UpdatedUser.EmployeeLeaveDateTime) {

        Write-Host ""
        Write-Host "SUCCESS: Expiry date has been verified." -ForegroundColor Green

    }
    else {

        Write-Host ""
        Write-Host "WARNING: Update completed but expiry date is empty." -ForegroundColor Yellow
    }

}
catch {

    Write-Host ""
    Write-Host "WARNING: Update may have succeeded, but verification failed." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# ============================================================
# End
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host " Script completed successfully." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""