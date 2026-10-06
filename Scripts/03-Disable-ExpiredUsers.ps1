#requires -Version 5.1

<#
.SYNOPSIS
    Disables Microsoft Entra ID users whose employee leave date has passed.

.DESCRIPTION
    This script connects to Microsoft Graph, detects users whose
    employeeLeaveDateTime has passed, validates their current account
    status, and disables only accounts that are both:

        1. Expired
        2. Currently enabled

    The script supports:

        - Manual confirmation mode
        - Automated mode using -Force
        - WhatIf / Dry-Run mode

    Manual mode requires the administrator to type DISABLE.

    Automated mode skips the interactive confirmation and is intended
    for use by Run-EntraUserLifecycle.ps1 and scheduled tasks.

.PARAMETER Force
    Skips the interactive DISABLE confirmation.

    Intended for trusted automation such as:
        Run-EntraUserLifecycle.ps1

.PARAMETER WhatIf
    Performs a dry run. No accounts are modified.

.EXAMPLE
    .\03-Disable-ExpiredUsers.ps1

    Detects expired users and asks for confirmation before disabling.

.EXAMPLE
    .\03-Disable-ExpiredUsers.ps1 -WhatIf

    Detects expired users but does not modify any accounts.

.EXAMPLE
    .\03-Disable-ExpiredUsers.ps1 -Force

    Runs unattended and disables eligible expired accounts without
    interactive confirmation.

.EXAMPLE
    .\03-Disable-ExpiredUsers.ps1 -Force -WhatIf

    Simulates the automated workflow without modifying accounts.

.NOTES
    Project: Entra-ID-User-Lifecycle-Automation
    Script: 03-Disable-ExpiredUsers.ps1
    PowerShell: Windows PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess)]
param(

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# ============================================================
# CONFIGURATION
# ============================================================

$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users"
)

$GraphScopes = @(
    "User.Read.All",
    "User.ReadWrite.All"
)

# ============================================================
# PROJECT PATHS
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$ReportsPath = Join-Path `
    $ProjectRoot `
    "Reports"

if (-not (Test-Path -Path $ReportsPath)) {

    New-Item `
        -ItemType Directory `
        -Path $ReportsPath `
        -Force |
        Out-Null
}

$ReportFile = Join-Path `
    $ReportsPath `
    (
        "DisableExpiredUsers_{0}.csv" -f (
            Get-Date -Format "yyyyMMdd_HHmmss"
        )
    )

# ============================================================
# HELPER FUNCTION
# ============================================================

function Import-RequiredModule {

    param (

        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {

        $InstalledModule = Get-InstalledModule `
            -Name $ModuleName `
            -ErrorAction SilentlyContinue

        if ($InstalledModule) {

            Import-Module `
                -Name $ModuleName `
                -ErrorAction Stop

            Write-Host "Loaded module: $ModuleName" `
                -ForegroundColor Green

            return
        }

        $LoadedModule = Get-Module `
            -Name $ModuleName

        if ($LoadedModule) {

            Write-Host "Module already loaded: $ModuleName" `
                -ForegroundColor Green

            return
        }

        throw `
            "Required module '$ModuleName' is not installed."
    }
    catch {

        Write-Error `
            "Failed to load module '$ModuleName'. $($_.Exception.Message)"

        throw
    }
}

# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Microsoft Entra ID - Disable Expired Users" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

# ============================================================
# MODE
# ============================================================

if ($WhatIfPreference) {

    Write-Host "DRY-RUN MODE ENABLED" `
        -ForegroundColor Yellow

    Write-Host "No user accounts will be modified." `
        -ForegroundColor Yellow

    Write-Host ""
}

if ($Force -and -not $WhatIfPreference) {

    Write-Host "AUTOMATION MODE ENABLED" `
        -ForegroundColor Yellow

    Write-Host "Interactive confirmation will be skipped." `
        -ForegroundColor Yellow

    Write-Host ""
}

# ============================================================
# LOAD MICROSOFT GRAPH MODULES
# ============================================================

Write-Host "Loading Microsoft Graph modules..." `
    -ForegroundColor Yellow

foreach ($Module in $RequiredModules) {

    Import-RequiredModule `
        -ModuleName $Module
}

# ============================================================
# VERIFY REQUIRED COMMANDS
# ============================================================

$RequiredCommands = @(
    "Connect-MgGraph",
    "Get-MgContext",
    "Get-MgUser",
    "Update-MgUser"
)

foreach ($Command in $RequiredCommands) {

    if (-not (
        Get-Command `
            $Command `
            -ErrorAction SilentlyContinue
    )) {

        throw `
            "Required Microsoft Graph command '$Command' is not available."
    }
}

Write-Host ""
Write-Host "Required Microsoft Graph commands verified." `
    -ForegroundColor Green

# ============================================================
# CONNECT TO MICROSOFT GRAPH
# ============================================================

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." `
    -ForegroundColor Yellow

Write-Host "Required permissions:" `
    -ForegroundColor DarkGray

Write-Host "  User.Read.All" `
    -ForegroundColor DarkGray

Write-Host "  User.ReadWrite.All" `
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

    return
}

# ============================================================
# GRAPH CONTEXT
# ============================================================

$Context = Get-MgContext

if (-not $Context) {

    Write-Host ""
    Write-Host "ERROR: Unable to retrieve Microsoft Graph context." `
        -ForegroundColor Red

    return
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
# CURRENT DATE
# ============================================================

$Today = (Get-Date).Date

Write-Host ""
Write-Host "Today's Date: $($Today.ToString('yyyy-MM-dd'))" `
    -ForegroundColor Cyan

# ============================================================
# RETRIEVE USERS
# ============================================================

Write-Host ""
Write-Host "Retrieving users from Microsoft Entra ID..." `
    -ForegroundColor Yellow

try {

    $Users = Get-MgUser `
        -All `
        -Property `
            Id,
            DisplayName,
            UserPrincipalName,
            AccountEnabled,
            EmployeeLeaveDateTime `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERROR: Failed to retrieve users." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    return
}

$TotalUsers = @($Users).Count

Write-Host ""
Write-Host "Total users retrieved: $TotalUsers" `
    -ForegroundColor Green

# ============================================================
# FIND EXPIRED USERS
# ============================================================

$ExpiredUsers = @(
    $Users |
        Where-Object {

            $null -ne $_.EmployeeLeaveDateTime -and
            $_.EmployeeLeaveDateTime.Date -lt $Today
        }
)

Write-Host ""
Write-Host "Expired users found: $($ExpiredUsers.Count)" `
    -ForegroundColor Yellow

# ============================================================
# SEPARATE ENABLED / DISABLED
# ============================================================

$ExpiredEnabledUsers = @(
    $ExpiredUsers |
        Where-Object {
            $_.AccountEnabled -eq $true
        }
)

$ExpiredDisabledUsers = @(
    $ExpiredUsers |
        Where-Object {
            $_.AccountEnabled -eq $false
        }
)

Write-Host ""
Write-Host "Expired + Enabled         : $($ExpiredEnabledUsers.Count)"
Write-Host "Expired + Already Disabled: $($ExpiredDisabledUsers.Count)"

# ============================================================
# NO EXPIRED USERS
# ============================================================

if ($ExpiredUsers.Count -eq 0) {

    Write-Host ""
    Write-Host "No expired users found." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "No accounts require action." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Script completed successfully." `
        -ForegroundColor Green

    return
}

# ============================================================
# DISPLAY EXPIRED ENABLED USERS
# ============================================================

if ($ExpiredEnabledUsers.Count -gt 0) {

    Write-Host ""
    Write-Host "=============================================" `
        -ForegroundColor Red

    Write-Host " Accounts Eligible for Disable" `
        -ForegroundColor Red

    Write-Host "=============================================" `
        -ForegroundColor Red

    Write-Host ""

    $ExpiredEnabledUsers |
        Select-Object `
            DisplayName,
            UserPrincipalName,
            AccountEnabled,
            @{
                Name = "EmployeeLeaveDate"
                Expression = {
                    $_.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")
                }
            } |
        Format-Table -AutoSize
}

# ============================================================
# PREPARE RESULTS
# ============================================================

$Results = @()

# ============================================================
# WHATIF / DRY RUN
# ============================================================

if ($WhatIfPreference) {

    Write-Host ""
    Write-Host "DRY-RUN RESULTS" `
        -ForegroundColor Yellow

    Write-Host ""

    foreach ($User in $ExpiredEnabledUsers) {

        $Results += [PSCustomObject]@{

            Timestamp         =
                Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            DisplayName       =
                $User.DisplayName

            UserPrincipalName =
                $User.UserPrincipalName

            EmployeeLeaveDate =
                $User.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")

            PreviousStatus    =
                "Enabled"

            Action            =
                "Disable"

            Result            =
                "WhatIf - No Change"

            UserId            =
                $User.Id
        }

        Write-Host `
            "[WHATIF] Would disable: $($User.UserPrincipalName)" `
            -ForegroundColor Yellow
    }
}
else {

    # ========================================================
    # SAFETY CONFIRMATION
    # ========================================================

    if (-not $Force) {

        Write-Host ""
        Write-Host "WARNING: ACCOUNT MODIFICATION" `
            -ForegroundColor Red

        Write-Host ""
        Write-Host `
            "The following enabled Entra ID accounts are expired."

        Write-Host `
            "They will be disabled if you continue."

        Write-Host ""

        $Confirmation = Read-Host `
            "Type DISABLE to continue"

        if ($Confirmation -cne "DISABLE") {

            Write-Host ""
            Write-Host "Operation cancelled." `
                -ForegroundColor Yellow

            Write-Host `
                "No user accounts were modified." `
                -ForegroundColor Green

            return
        }
    }

    # ========================================================
    # DISABLE USERS
    # ========================================================

    Write-Host ""
    Write-Host "Starting account disable operation..." `
        -ForegroundColor Yellow

    foreach ($User in $ExpiredEnabledUsers) {

        Write-Host ""
        Write-Host `
            "Processing: $($User.UserPrincipalName)" `
            -ForegroundColor Cyan

        # ----------------------------------------------------
        # RE-READ USER BEFORE MODIFICATION
        # ----------------------------------------------------

        try {

            $CurrentUser = Get-MgUser `
                -UserId $User.Id `
                -Property `
                    Id,
                    DisplayName,
                    UserPrincipalName,
                    AccountEnabled,
                    EmployeeLeaveDateTime `
                -ErrorAction Stop
        }
        catch {

            Write-Host `
                "FAILED: Unable to re-read user." `
                -ForegroundColor Red

            $Results += [PSCustomObject]@{

                Timestamp =
                    Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                DisplayName =
                    $User.DisplayName

                UserPrincipalName =
                    $User.UserPrincipalName

                EmployeeLeaveDate =
                    $User.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")

                PreviousStatus =
                    "Unknown"

                Action =
                    "Disable"

                Result =
                    "Failed - User Read Error"

                UserId =
                    $User.Id
            }

            continue
        }

        # ----------------------------------------------------
        # SAFETY CHECK - ACCOUNT STATUS
        # ----------------------------------------------------

        if ($CurrentUser.AccountEnabled -ne $true) {

            Write-Host `
                "SKIPPED: Account is already disabled." `
                -ForegroundColor Yellow

            $Results += [PSCustomObject]@{

                Timestamp =
                    Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                DisplayName =
                    $CurrentUser.DisplayName

                UserPrincipalName =
                    $CurrentUser.UserPrincipalName

                EmployeeLeaveDate =
                    if ($null -ne $CurrentUser.EmployeeLeaveDateTime) {
                        $CurrentUser.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")
                    }
                    else {
                        "Not Set"
                    }

                PreviousStatus =
                    "Disabled"

                Action =
                    "None"

                Result =
                    "Skipped - Already Disabled"

                UserId =
                    $CurrentUser.Id
            }

            continue
        }

        # ----------------------------------------------------
        # SAFETY CHECK - EXPIRY DATE
        # ----------------------------------------------------

        if (
            $null -eq $CurrentUser.EmployeeLeaveDateTime -or
            $CurrentUser.EmployeeLeaveDateTime.Date -ge $Today
        ) {

            Write-Host `
                "SKIPPED: User is no longer expired." `
                -ForegroundColor Yellow

            $Results += [PSCustomObject]@{

                Timestamp =
                    Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                DisplayName =
                    $CurrentUser.DisplayName

                UserPrincipalName =
                    $CurrentUser.UserPrincipalName

                EmployeeLeaveDate =
                    if ($null -ne $CurrentUser.EmployeeLeaveDateTime) {
                        $CurrentUser.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")
                    }
                    else {
                        "Not Set"
                    }

                PreviousStatus =
                    "Enabled"

                Action =
                    "None"

                Result =
                    "Skipped - No Longer Expired"

                UserId =
                    $CurrentUser.Id
            }

            continue
        }

        # ----------------------------------------------------
        # DISABLE ACCOUNT
        # ----------------------------------------------------

        try {

            if (
                $PSCmdlet.ShouldProcess(
                    $CurrentUser.UserPrincipalName,
                    "Disable Microsoft Entra ID account"
                )
            ) {

                Update-MgUser `
                    -UserId $CurrentUser.Id `
                    -AccountEnabled:$false `
                    -ErrorAction Stop

                Write-Host `
                    "SUCCESS: Account disabled." `
                    -ForegroundColor Green

                $Results += [PSCustomObject]@{

                    Timestamp =
                        Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                    DisplayName =
                        $CurrentUser.DisplayName

                    UserPrincipalName =
                        $CurrentUser.UserPrincipalName

                    EmployeeLeaveDate =
                        $CurrentUser.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")

                    PreviousStatus =
                        "Enabled"

                    Action =
                        "Disable"

                    Result =
                        "Success"

                    UserId =
                        $CurrentUser.Id
                }
            }
        }
        catch {

            Write-Host `
                "FAILED: $($_.Exception.Message)" `
                -ForegroundColor Red

            $Results += [PSCustomObject]@{

                Timestamp =
                    Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                DisplayName =
                    $CurrentUser.DisplayName

                UserPrincipalName =
                    $CurrentUser.UserPrincipalName

                EmployeeLeaveDate =
                    $CurrentUser.EmployeeLeaveDateTime.Date.ToString("yyyy-MM-dd")

                PreviousStatus =
                    "Enabled"

                Action =
                    "Disable"

                Result =
                    "Failed - $($_.Exception.Message)"

                UserId =
                    $CurrentUser.Id
            }
        }
    }
}

# ============================================================
# EXPORT RESULTS
# ============================================================

if ($Results.Count -gt 0) {

    try {

        $Results |
            Export-Csv `
                -Path $ReportFile `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Force

        Write-Host ""
        Write-Host `
            "Results exported successfully:" `
            -ForegroundColor Green

        Write-Host `
            $ReportFile `
            -ForegroundColor White
    }
    catch {

        Write-Host ""
        Write-Host `
            "WARNING: Could not export results." `
            -ForegroundColor Yellow

        Write-Host `
            $_.Exception.Message `
            -ForegroundColor Yellow
    }
}

# ============================================================
# FINAL VERIFICATION
# ============================================================

$SuccessfulDisables = @(
    $Results |
        Where-Object {
            $_.Result -eq "Success"
        }
)

$FailedDisables = @(
    $Results |
        Where-Object {
            $_.Result -like "Failed*"
        }
)

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Host ""
Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host " Final Summary" `
    -ForegroundColor Cyan

Write-Host "=============================================" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host `
    "Total users               : $TotalUsers"

Write-Host `
    "Expired users             : $($ExpiredUsers.Count)"

Write-Host `
    "Expired + Enabled         : $($ExpiredEnabledUsers.Count)"

Write-Host `
    "Expired + Already Disabled: $($ExpiredDisabledUsers.Count)"

if ($WhatIfPreference) {

    Write-Host `
        "Would be disabled         : $($ExpiredEnabledUsers.Count)" `
        -ForegroundColor Yellow

    Write-Host ""

    Write-Host `
        "DRY-RUN COMPLETE." `
        -ForegroundColor Yellow

    Write-Host `
        "No user accounts were modified." `
        -ForegroundColor Green
}
else {

    Write-Host `
        "Successfully disabled     : $($SuccessfulDisables.Count)" `
        -ForegroundColor Green

    Write-Host `
        "Failed                    : $($FailedDisables.Count)" `
        -ForegroundColor Red
}

Write-Host ""

Write-Host `
    "Script completed." `
    -ForegroundColor Green