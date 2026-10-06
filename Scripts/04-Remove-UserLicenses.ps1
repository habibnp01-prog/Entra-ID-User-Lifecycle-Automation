#requires -Version 5.1

<#
.SYNOPSIS
    Removes directly assigned Microsoft 365 / Entra ID licenses from a user.

.DESCRIPTION
    This script:
      - Checks required Microsoft Graph modules
      - Offers to install missing modules automatically
      - Checks required Graph commands
      - Offers to install missing command modules automatically
      - Connects to Microsoft Graph
      - Displays assigned licenses
      - Supports -WhatIf
      - Requests Y/N confirmation before removal
      - Supports -Force for automation
      - Removes directly assigned licenses
      - Verifies license removal
      - Creates a CSV report

.NOTES
    Required Graph permissions:
      User.Read.All
      LicenseAssignment.ReadWrite.All

    Important:
      This script removes directly assigned licenses.
      Group-based licenses should be managed through group membership.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# ============================================================
# Configuration
# ============================================================

$ErrorActionPreference = "Stop"

$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Users",
    "Microsoft.Graph.Users.Actions",
    "Microsoft.Graph.Identity.DirectoryManagement"
)

$RequiredScopes = @(
    "User.Read.All",
    "LicenseAssignment.ReadWrite.All"
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot

$ReportsPath = Join-Path $ProjectRoot "Reports"

if (-not (Test-Path $ReportsPath)) {
    New-Item -Path $ReportsPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$ReportPath = Join-Path `
    $ReportsPath `
    "RemoveUserLicenses_$Timestamp.csv"

# ============================================================
# Helper - Section Header
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

# ============================================================
# Check / Install Required Modules
# ============================================================

function Test-RequiredModules {

    Write-Section "Checking Required Modules"

    foreach ($ModuleName in $RequiredModules) {

        Write-Host "Checking module: $ModuleName"

        # ----------------------------------------------------
        # Check if already loaded
        # ----------------------------------------------------

        $LoadedModule = Get-Module -Name $ModuleName

        if ($LoadedModule) {

            Write-Host `
                "Module already loaded: $ModuleName $($LoadedModule.Version)" `
                -ForegroundColor Green

            continue
        }

        # ----------------------------------------------------
        # Try normal import
        # ----------------------------------------------------

        try {

            Import-Module `
                $ModuleName `
                -Force `
                -ErrorAction Stop

            $LoadedModule = Get-Module -Name $ModuleName

            if ($LoadedModule) {

                Write-Host `
                    "Loaded module: $ModuleName $($LoadedModule.Version)" `
                    -ForegroundColor Green

                continue
            }
        }
        catch {
            # Continue to module discovery.
        }

        # ----------------------------------------------------
        # Search installed module paths
        # ----------------------------------------------------

        $AvailableModule = Get-Module `
            -ListAvailable `
            -Name $ModuleName `
            -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($AvailableModule) {

            try {

                Import-Module `
                    $AvailableModule.Path `
                    -Force `
                    -ErrorAction Stop

                $LoadedModule = Get-Module -Name $ModuleName

                if ($LoadedModule) {

                    Write-Host `
                        "Loaded module: $ModuleName $($LoadedModule.Version)" `
                        -ForegroundColor Green

                    continue
                }
            }
            catch {
                # Continue to installation.
            }
        }

        # ----------------------------------------------------
        # Module missing
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "MISSING MODULE: $ModuleName" `
            -ForegroundColor Yellow

        $InstallCommand = `
            "Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber"

        Write-Host ""
        Write-Host "Required installation command:" `
            -ForegroundColor Cyan

        Write-Host $InstallCommand

        Write-Host ""

        $InstallAnswer = Read-Host `
            "Install this module now? (Y/N)"

        if ($InstallAnswer -notmatch "^(Y|YES)$") {

            throw @"

Required module '$ModuleName' is not installed.

The script cannot continue.

Install it manually using:

$InstallCommand

"@
        }

        # ----------------------------------------------------
        # Install missing module
        # ----------------------------------------------------

        try {

            Write-Host ""
            Write-Host "Installing $ModuleName..." `
                -ForegroundColor Cyan

            Install-Module `
                $ModuleName `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop

            Write-Host `
                "Module installed successfully." `
                -ForegroundColor Green

            Import-Module `
                $ModuleName `
                -Force `
                -ErrorAction Stop

            $LoadedModule = Get-Module -Name $ModuleName

            if (-not $LoadedModule) {

                throw `
                    "Module installed but could not be loaded."
            }

            Write-Host `
                "Module loaded successfully: $($LoadedModule.Version)" `
                -ForegroundColor Green
        }
        catch {

            throw @"

Failed to install or load module:

$ModuleName

Install manually using:

$InstallCommand

Error:
$($_.Exception.Message)

"@
        }
    }

    Write-Host ""
    Write-Host "All required modules are available." `
        -ForegroundColor Green
}

# ============================================================
# Check / Install Required Graph Commands
# ============================================================

function Test-GraphCommands {

    Write-Section "Verifying Microsoft Graph Commands"

    $RequiredCommands = @(
        @{
            Name   = "Connect-MgGraph"
            Module = "Microsoft.Graph.Authentication"
        },
        @{
            Name   = "Get-MgContext"
            Module = "Microsoft.Graph.Authentication"
        },
        @{
            Name   = "Get-MgUser"
            Module = "Microsoft.Graph.Users"
        },
        @{
            Name   = "Get-MgSubscribedSku"
            Module = "Microsoft.Graph.Identity.DirectoryManagement"
        },
        @{
            Name   = "Set-MgUserLicense"
            Module = "Microsoft.Graph.Users.Actions"
        }
    )

    foreach ($CommandInfo in $RequiredCommands) {

        $CommandName = $CommandInfo.Name
        $ModuleName = $CommandInfo.Module

        $Command = Get-Command `
            $CommandName `
            -ErrorAction SilentlyContinue

        # ----------------------------------------------------
        # Command exists
        # ----------------------------------------------------

        if ($Command) {

            Write-Host `
                "OK: $CommandName" `
                -ForegroundColor Green

            continue
        }

        # ----------------------------------------------------
        # Command missing
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "MISSING COMMAND: $CommandName" `
            -ForegroundColor Yellow

        Write-Host `
            "Required module: $ModuleName" `
            -ForegroundColor Yellow

        $InstallCommand = `
            "Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber"

        Write-Host ""
        Write-Host "Required installation command:" `
            -ForegroundColor Cyan

        Write-Host $InstallCommand

        Write-Host ""

        $InstallAnswer = Read-Host `
            "Install the required module now? (Y/N)"

        if ($InstallAnswer -notmatch "^(Y|YES)$") {

            throw @"

Required command '$CommandName' is unavailable.

Required module:

$ModuleName

Install manually using:

$InstallCommand

"@
        }

        # ----------------------------------------------------
        # Install command module
        # ----------------------------------------------------

        try {

            Write-Host ""
            Write-Host "Installing required module..." `
                -ForegroundColor Cyan

            Install-Module `
                $ModuleName `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop

            Import-Module `
                $ModuleName `
                -Force `
                -ErrorAction Stop

            $Command = Get-Command `
                $CommandName `
                -ErrorAction SilentlyContinue

            if (-not $Command) {

                throw @"

Module installed, but command '$CommandName'
is still unavailable.

"@
            }

            Write-Host ""
            Write-Host `
                "OK: $CommandName is now available." `
                -ForegroundColor Green
        }
        catch {

            throw @"

Failed to install the module required for:

$CommandName

Module:
$ModuleName

Installation command:

$InstallCommand

Error:
$($_.Exception.Message)

"@
        }
    }

    Write-Host ""
    Write-Host `
        "All required Microsoft Graph commands are available." `
        -ForegroundColor Green
}

# ============================================================
# Connect to Microsoft Graph
# ============================================================

function Connect-ToGraph {

    Write-Section "Checking Microsoft Graph Connection"

    $Context = Get-MgContext -ErrorAction SilentlyContinue

    $NeedsConnection = $true

    if ($Context) {

        $ExistingScopes = @($Context.Scopes)

        $MissingScopes = @(
            $RequiredScopes | Where-Object {
                $_ -notin $ExistingScopes
            }
        )

        if ($MissingScopes.Count -eq 0) {

            $NeedsConnection = $false
        }
        else {

            Write-Host ""
            Write-Host `
                "Existing Graph session is missing required permissions:" `
                -ForegroundColor Yellow

            foreach ($Scope in $MissingScopes) {

                Write-Host `
                    "  $Scope" `
                    -ForegroundColor Yellow
            }
        }
    }

    if ($NeedsConnection) {

        Write-Host "Connecting to Microsoft Graph..."
        Write-Host ""

        Write-Host "Required permissions:"

        foreach ($Scope in $RequiredScopes) {

            Write-Host "  $Scope"
        }

        Write-Host ""

        Connect-MgGraph `
            -Scopes $RequiredScopes `
            -NoWelcome `
            -ErrorAction Stop |
            Out-Null

        Write-Host ""
        Write-Host `
            "Connected to Microsoft Graph successfully." `
            -ForegroundColor Green
    }
    else {

        Write-Host `
            "Existing Microsoft Graph connection has the required permissions." `
            -ForegroundColor Green
    }

    $Context = Get-MgContext -ErrorAction Stop

    Write-Host ""
    Write-Host "Account : $($Context.Account)"
    Write-Host "Tenant  : $($Context.TenantId)"
}

# ============================================================
# Get License Catalog
# ============================================================

function Get-LicenseCatalog {

    Write-Host ""
    Write-Host "Retrieving tenant license catalog..."

    try {

        $SubscribedSkus = Get-MgSubscribedSku `
            -All `
            -ErrorAction Stop

        $LicenseCatalog = @{}

        foreach ($Sku in $SubscribedSkus) {

            $SkuId = $Sku.SkuId.ToString()

            $LicenseCatalog[$SkuId] = $Sku
        }

        Write-Host `
            "License catalog retrieved successfully." `
            -ForegroundColor Green

        return $LicenseCatalog
    }
    catch {

        throw @"

Unable to retrieve the tenant license catalog.

Required permission:
LicenseAssignment.ReadWrite.All

Error:
$($_.Exception.Message)

"@
    }
}

# ============================================================
# Get License Display Name
# ============================================================

function Get-LicenseDisplayName {

    param(
        [Parameter(Mandatory = $true)]
        $License,

        [Parameter(Mandatory = $true)]
        [hashtable]$LicenseCatalog
    )

    $SkuId = $License.SkuId.ToString()

    if ($LicenseCatalog.ContainsKey($SkuId)) {

        $CatalogSku = $LicenseCatalog[$SkuId]

        if (-not [string]::IsNullOrWhiteSpace(
            $CatalogSku.SkuPartNumber
        )) {

            return $CatalogSku.SkuPartNumber
        }
    }

    return $SkuId
}

# ============================================================
# Header
# ============================================================

Write-Section `
    "Microsoft Entra ID User Lifecycle Automation - Remove Licenses"

Write-Host "Project Root :"
Write-Host $ProjectRoot
Write-Host ""

if ($WhatIfPreference) {

    Write-Host `
        "Execution Mode : WHATIF" `
        -ForegroundColor Yellow
}
elseif ($Force) {

    Write-Host `
        "Execution Mode : AUTOMATION" `
        -ForegroundColor Yellow
}
else {

    Write-Host `
        "Execution Mode : INTERACTIVE" `
        -ForegroundColor Green
}

# ============================================================
# STEP 1 - Modules
# ============================================================

Test-RequiredModules

# ============================================================
# STEP 2 - Graph Commands
# ============================================================

Test-GraphCommands

# ============================================================
# STEP 3 - Graph Connection
# ============================================================

Connect-ToGraph

# ============================================================
# STEP 4 - User Selection
# ============================================================

Write-Section "User Selection"

if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {

    $UserPrincipalName = Read-Host `
        "Enter User Principal Name (UPN)"
}

if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {

    throw "User Principal Name cannot be empty."
}

Write-Host ""
Write-Host "Searching for user..."

# ============================================================
# STEP 5 - Retrieve User
# ============================================================

try {

    $User = Get-MgUser `
        -UserId $UserPrincipalName `
        -Property Id,DisplayName,UserPrincipalName,AccountEnabled,AssignedLicenses `
        -ErrorAction Stop
}
catch {

    throw @"

Unable to find user:

$UserPrincipalName

Error:
$($_.Exception.Message)

"@
}

# ============================================================
# STEP 6 - Display User
# ============================================================

Write-Section "Current User Information"

Write-Host "Display Name       : $($User.DisplayName)"
Write-Host "User Principal Name: $($User.UserPrincipalName)"
Write-Host "Account Enabled    : $($User.AccountEnabled)"

# ============================================================
# STEP 7 - License Catalog
# ============================================================

$LicenseCatalog = Get-LicenseCatalog

# ============================================================
# STEP 8 - Assigned Licenses
# ============================================================

$AssignedLicenses = @($User.AssignedLicenses)

Write-Host ""

if ($AssignedLicenses.Count -eq 0) {

    Write-Host `
        "No licenses are assigned to this user." `
        -ForegroundColor Yellow

    $NoLicenseResult = [PSCustomObject]@{
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DisplayName       = $User.DisplayName
        UserPrincipalName = $User.UserPrincipalName
        SkuId             = ""
        LicenseName       = ""
        PreviousStatus    = "No License"
        Action            = "Remove License"
        Result            = "Skipped"
        Details           = "User has no assigned licenses."
    }

    $NoLicenseResult |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force

    Write-Host ""
    Write-Host "Report exported:"
    Write-Host $ReportPath

    exit 0
}

# ============================================================
# STEP 9 - Build License List
# ============================================================

$LicenseRows = @()

foreach ($License in $AssignedLicenses) {

    $LicenseName = Get-LicenseDisplayName `
        -License $License `
        -LicenseCatalog $LicenseCatalog

    $SkuId = $License.SkuId.ToString()

    $LicenseRows += [PSCustomObject]@{
        LicenseName = $LicenseName
        SkuId       = $SkuId
    }
}

# ============================================================
# STEP 10 - Display Licenses
# ============================================================

Write-Section "Assigned Licenses"

$LicenseRows |
    Format-Table `
        LicenseName,
        SkuId `
        -AutoSize

Write-Host ""
Write-Host `
    "Total assigned licenses: $($LicenseRows.Count)"

# ============================================================
# Licensing Warning
# ============================================================

Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host ""
Write-Host `
    "This script removes licenses assigned directly to the user."
Write-Host ""
Write-Host `
    "If a license is assigned through a group, remove the user"
Write-Host `
    "from the appropriate licensing group instead."
Write-Host ""

# ============================================================
# STEP 11 - WhatIf
# ============================================================

if ($WhatIfPreference) {

    Write-Section "WhatIf Preview"

    foreach ($LicenseRow in $LicenseRows) {

        Write-Host `
            "[WhatIf] Would remove license:" `
            -ForegroundColor Yellow

        Write-Host "  License : $($LicenseRow.LicenseName)"
        Write-Host "  SKU ID  : $($LicenseRow.SkuId)"
        Write-Host ""
    }

    Write-Host `
        "WHATIF completed." `
        -ForegroundColor Green

    Write-Host `
        "No licenses were removed." `
        -ForegroundColor Green

    $WhatIfResults = @()

    foreach ($LicenseRow in $LicenseRows) {

        $WhatIfResults += [PSCustomObject]@{
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            DisplayName       = $User.DisplayName
            UserPrincipalName = $User.UserPrincipalName
            SkuId             = $LicenseRow.SkuId
            LicenseName       = $LicenseRow.LicenseName
            PreviousStatus    = "Assigned"
            Action            = "Remove License"
            Result            = "WhatIf - No Change"
            Details           = "License removal preview only."
        }
    }

    $WhatIfResults |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force

    Write-Host ""
    Write-Host "WhatIf report exported:"
    Write-Host $ReportPath

    exit 0
}

# ============================================================
# STEP 12 - Confirmation
# ============================================================

$Confirmed = $false

if ($Force) {

    Write-Host ""
    Write-Host `
        "AUTOMATION MODE ENABLED" `
        -ForegroundColor Yellow

    Write-Host `
        "Interactive confirmation will be skipped."

    Write-Host ""

    $Confirmed = $true
}
else {

    Write-Section "License Removal Confirmation"

    Write-Host "User:"
    Write-Host "  $($User.UserPrincipalName)"
    Write-Host ""

    Write-Host "Licenses that will be removed:"

    foreach ($LicenseRow in $LicenseRows) {

        Write-Host `
            "  - $($LicenseRow.LicenseName)"
    }

    Write-Host ""

    $Confirmation = Read-Host `
        "Remove ALL listed licenses from this user? (Y/N)"

    if ($Confirmation -match "^(Y|YES)$") {

        $Confirmed = $true
    }
    else {

        $Confirmed = $false
    }
}

# ============================================================
# STEP 13 - Cancellation
# ============================================================

if (-not $Confirmed) {

    Write-Host ""
    Write-Host `
        "License removal cancelled." `
        -ForegroundColor Yellow

    $CancelledResults = @()

    foreach ($LicenseRow in $LicenseRows) {

        $CancelledResults += [PSCustomObject]@{
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            DisplayName       = $User.DisplayName
            UserPrincipalName = $User.UserPrincipalName
            SkuId             = $LicenseRow.SkuId
            LicenseName       = $LicenseRow.LicenseName
            PreviousStatus    = "Assigned"
            Action            = "Remove License"
            Result            = "Skipped"
            Details           = "Administrator declined license removal."
        }
    }

    $CancelledResults |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force

    Write-Host ""
    Write-Host "Report exported:"
    Write-Host $ReportPath

    exit 0
}

# ============================================================
# STEP 14 - Remove Licenses
# ============================================================

Write-Section "Removing Assigned Licenses"

$RemovalResults = @()

foreach ($LicenseRow in $LicenseRows) {

    Write-Host ""
    Write-Host `
        "Processing: $($LicenseRow.LicenseName)"

    try {

        $Target = `
            "$($User.UserPrincipalName) - $($LicenseRow.LicenseName)"

        if ($PSCmdlet.ShouldProcess(
            $Target,
            "Remove license"
        )) {

            Set-MgUserLicense `
                -UserId $User.Id `
                -AddLicenses @() `
                -RemoveLicenses @($LicenseRow.SkuId) `
                -ErrorAction Stop |
                Out-Null

            Write-Host `
                "SUCCESS: License removed." `
                -ForegroundColor Green

            $RemovalResults += [PSCustomObject]@{
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                DisplayName       = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
                SkuId             = $LicenseRow.SkuId
                LicenseName       = $LicenseRow.LicenseName
                PreviousStatus    = "Assigned"
                Action            = "Remove License"
                Result            = "Success"
                Details           = "License removal API call succeeded."
            }
        }
    }
    catch {

        Write-Host `
            "ERROR: License removal failed." `
            -ForegroundColor Red

        Write-Host `
            $_.Exception.Message `
            -ForegroundColor Red

        $RemovalResults += [PSCustomObject]@{
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            DisplayName       = $User.DisplayName
            UserPrincipalName = $User.UserPrincipalName
            SkuId             = $LicenseRow.SkuId
            LicenseName       = $LicenseRow.LicenseName
            PreviousStatus    = "Assigned"
            Action            = "Remove License"
            Result            = "Failed"
            Details           = $_.Exception.Message
        }
    }
}

# ============================================================
# STEP 15 - Verify Removal
# ============================================================

Write-Section "Verifying License Removal"

try {

    $UpdatedUser = Get-MgUser `
        -UserId $User.Id `
        -Property Id,DisplayName,UserPrincipalName,AssignedLicenses `
        -ErrorAction Stop

    $RemainingLicenses = @($UpdatedUser.AssignedLicenses)

    Write-Host `
        "Remaining assigned licenses: $($RemainingLicenses.Count)"

    if ($RemainingLicenses.Count -eq 0) {

        Write-Host ""
        Write-Host `
            "SUCCESS: No assigned licenses remain." `
            -ForegroundColor Green

        foreach ($Result in $RemovalResults) {

            if ($Result.Result -eq "Success") {

                $Result.Details = `
                    "License removed and verified successfully."
            }
        }
    }
    else {

        Write-Host ""
        Write-Host `
            "WARNING: Some licenses remain assigned." `
            -ForegroundColor Yellow

        foreach ($RemainingLicense in $RemainingLicenses) {

            $RemainingName = Get-LicenseDisplayName `
                -License $RemainingLicense `
                -LicenseCatalog $LicenseCatalog

            Write-Host `
                "  Remaining: $RemainingName" `
                -ForegroundColor Yellow
        }
    }
}
catch {

    Write-Host ""
    Write-Host `
        "WARNING: License removal completed, but verification failed." `
        -ForegroundColor Yellow

    Write-Host `
        $_.Exception.Message `
        -ForegroundColor Yellow
}

# ============================================================
# STEP 16 - Export Report
# ============================================================

if ($RemovalResults.Count -gt 0) {

    $RemovalResults |
        Export-Csv `
            -Path $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force
}

# ============================================================
# STEP 17 - Final Summary
# ============================================================

Write-Section "Final Summary"

$SuccessCount = @(
    $RemovalResults |
        Where-Object {
            $_.Result -eq "Success"
        }
).Count

$FailedCount = @(
    $RemovalResults |
        Where-Object {
            $_.Result -eq "Failed"
        }
).Count

Write-Host `
    "User                    : $($User.UserPrincipalName)"

Write-Host `
    "Licenses found          : $($LicenseRows.Count)"

Write-Host `
    "Successfully removed    : $SuccessCount"

Write-Host `
    "Failed                  : $FailedCount"

Write-Host ""
Write-Host "Report exported:"
Write-Host $ReportPath
Write-Host ""

if (
    $FailedCount -eq 0 -and
    $SuccessCount -eq $LicenseRows.Count
) {

    Write-Host `
        "Script completed successfully." `
        -ForegroundColor Green
}
elseif ($SuccessCount -gt 0) {

    Write-Host `
        "Script completed with warnings." `
        -ForegroundColor Yellow
}
else {

    Write-Host `
        "Script completed with errors." `
        -ForegroundColor Red
}

Write-Host ""