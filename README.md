# Entra ID User Lifecycle Automation

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-PowerShell-5C2D91?logo=microsoft)
![Platform](https://img.shields.io/badge/Platform-Microsoft%20Entra%20ID-0078D4)
![Status](https://img.shields.io/badge/Status-Tested-success)

A PowerShell-based Microsoft Entra ID user lifecycle automation project for administrators who need a controlled, auditable leaver/offboarding workflow.

The project detects users whose `employeeLeaveDateTime` has passed, optionally disables expired accounts, optionally removes **directly assigned** licenses, records lifecycle events in a local audit log, and sends an administrator notification.

> **This is an independent community project and is not an official Microsoft product.**

---

## What problem does it solve?

User offboarding often involves several repetitive administrative tasks:

```text
Employee leave date reached
        │
        ▼
Detect expired Entra ID user
        │
        ▼
Confirm / disable account
        │
        ▼
Confirm / remove direct licenses
        │
        ▼
Write audit event
        │
        ▼
Notify administrator
```

The goal is to make the process:

- repeatable
- controlled
- auditable
- easy to test
- easy to troubleshoot
- suitable for scheduled automation after unattended authentication is implemented

---

## Features

- Detect expired users using `employeeLeaveDateTime`
- Set/update a user's expiry date
- Separate confirmation for account disable
- Separate confirmation for license removal
- `-WhatIf` dry-run support where applicable
- `-Force` automation mode for the destructive lifecycle stages
- Remove directly assigned licenses
- Warn about group-based licensing
- Generate CSV reports
- Maintain a local lifecycle audit log
- Track notification state using `EventId`
- Capture administrator, Windows user, computer, and tenant context
- Send HTML administrator notifications through Microsoft Graph
- Avoid sending the same successful audit event repeatedly after it has been marked `Sent`

---

## Project workflow

### 1. Assign the expiry date

`01-Set-UserExpiryDate.ps1`

Sets the Microsoft Entra `employeeLeaveDateTime` value for a user.

This script is intentionally separate from the daily lifecycle orchestrator. Expiry dates can be supplied manually or by another HR-driven process.

### 2. Detect expired users

`02-Get-ExpiredUsers.ps1`

Read-only detection:

- retrieves users
- checks `employeeLeaveDateTime`
- identifies dates before the current date
- distinguishes enabled and already-disabled accounts
- creates an `ExpiredUsers_*.csv` report

### 3. Disable expired accounts

`03-Disable-ExpiredUsers.ps1`

Disables accounts that are:

1. expired
2. currently enabled

The orchestrator asks for confirmation before executing this stage unless `-Force` is used.

### 4. Remove direct licenses

`04-Remove-UserLicenses.ps1`

Removes licenses assigned directly to the user.

> Group-based licensing is different. If a license is inherited through a group, remove the user from the appropriate licensing group instead of attempting direct license removal.

### 5. Audit the lifecycle

`05-Write-AuditLog.ps1`

Writes a unique `EventId` for each lifecycle action and stores the event in:

```text
Logs/EntraUserLifecycle_Audit.csv
```

The audit record includes execution context such as:

- Graph administrator account
- Windows account
- computer name
- tenant ID
- action
- result
- notification status

### 6. Notify the administrator

`06-Send-AdminNotification.ps1`

Reads successful, unnotified audit events and sends an HTML email through Microsoft Graph.

After a successful notification, the selected events are marked as:

```text
NotificationStatus = Sent
```

### 7. Orchestrate the workflow

`Run-EntraUserLifecycle.ps1`

Coordinates the complete process:

```text
02 Detect
   ↓
Confirmation
   ↓
03 Disable
   ↓
05 Audit
   ↓
Confirmation
   ↓
04 Remove Direct Licenses
   ↓
05 Audit
   ↓
06 Notification
```

---

## Repository structure

```text
Entra-ID-User-Lifecycle-Automation/
│
├── README.md
├── .gitignore
│
├── Scripts/
│   ├── 01-Set-UserExpiryDate.ps1
│   ├── 02-Get-ExpiredUsers.ps1
│   ├── 03-Disable-ExpiredUsers.ps1
│   ├── 04-Remove-UserLicenses.ps1
│   ├── 05-Write-AuditLog.ps1
│   ├── 06-Send-AdminNotification.ps1
│   └── Run-EntraUserLifecycle.ps1
│
├── Config/
│   └── Config.example.json
│
├── Documentation/
│   ├── Installation.md
│   ├── Permissions.md
│   ├── Troubleshooting.md
│   ├── Security.md
│   ├── Architecture.md
│   └── Test-Plan.md
│
├── Logs/
│   └── .gitkeep
│
└── Reports/
    └── .gitkeep
```

Generated reports, logs, certificates, secrets, and environment-specific configuration should not be committed.

---

## Requirements

### Operating system

- Windows
- Windows PowerShell 5.1 or PowerShell 7+

### Microsoft Graph PowerShell SDK

The project uses Microsoft Graph PowerShell modules.

Required modules:

```powershell
Microsoft.Graph.Authentication
Microsoft.Graph.Users
Microsoft.Graph.Users.Actions
Microsoft.Graph.Identity.DirectoryManagement
```

Not every script requires every module.

See [Documentation/Permissions.md](Documentation/Permissions.md) for the per-script requirements.

---

## Quick start

### 1. Clone the repository

```powershell
git clone https://github.com/habibnp01-prog/Entra-ID-User-Lifecycle-Automation.git
cd Entra-ID-User-Lifecycle-Automation
```

### 2. Install Microsoft Graph modules

For the complete project:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
```

### 3. Test detection first

```powershell
cd Scripts
.\02-Get-ExpiredUsers.ps1
```

This is read-only.

### 4. Run the complete workflow in dry-run mode

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com" `
    -WhatIf
```

Dry-run mode should:

- detect expired users
- generate the detection report
- show which users would be disabled
- make no account changes
- remove no licenses
- write no lifecycle audit events
- send no email

### 5. Run normally

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com"
```

Normal mode requests separate confirmation before:

1. disabling expired accounts
2. removing directly assigned licenses

### 6. Automation mode

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com" `
    -Force
```

Use `-Force` only when the execution environment and approval process are appropriate for unattended or controlled automation.

---

## Safety model

The project deliberately separates detection from destructive operations.

### Read-only

`02-Get-ExpiredUsers.ps1`

No Entra ID modifications.

### Destructive

`03-Disable-ExpiredUsers.ps1`

Changes `accountEnabled`.

### Destructive

`04-Remove-UserLicenses.ps1`

Removes directly assigned licenses.

### Local audit

`05-Write-AuditLog.ps1`

Writes only to the project's local audit CSV.

### Notification

`06-Send-AdminNotification.ps1`

Sends an administrator email and updates notification state in the local audit log.

---

## Reports

Generated reports are stored under:

```text
Reports/
```

Examples:

```text
ExpiredUsers_YYYYMMDD_HHMMSS.csv
DisableExpiredUsers_YYYYMMDD_HHMMSS.csv
RemoveUserLicenses_YYYYMMDD_HHMMSS.csv
Notification_YYYYMMDD_HHMMSS.csv
```

Reports are environment-specific and should normally remain untracked.

---

## Audit log

The local audit log is:

```text
Logs/EntraUserLifecycle_Audit.csv
```

Typical fields include:

```text
EventId
Timestamp
Action
DisplayName
UserPrincipalName
EmployeeLeaveDate
PreviousAccountStatus
NewAccountStatus
Result
Details
PerformedBy
WindowsUser
ComputerName
TenantId
NotificationStatus
NotificationTimestamp
```

The `EventId` provides a stable identifier for each lifecycle event.

---

## Authentication

The current implementation uses interactive Microsoft Graph authentication.

For production unattended execution, the recommended next step is to move to an application identity using:

- Microsoft Entra App Registration
- certificate-based authentication
- Microsoft Graph application permissions
- a dedicated service identity
- least-privilege permissions
- secure certificate storage

Do not store client secrets, certificates, refresh tokens, or access tokens in this repository.

---

## Permissions

The intended permissions are kept as small as practical for each script.

| Script | Microsoft Graph permission |
|---|---|
| `01-Set-UserExpiryDate.ps1` | `User.ReadWrite.All` |
| `02-Get-ExpiredUsers.ps1` | `User.Read.All` |
| `03-Disable-ExpiredUsers.ps1` | `User.Read.All`, `User.ReadWrite.All` |
| `04-Remove-UserLicenses.ps1` | `User.Read.All`, `LicenseAssignment.ReadWrite.All` |
| `05-Write-AuditLog.ps1` | None |
| `06-Send-AdminNotification.ps1` | `User.Read.All`, `Mail.Send` |

See [Documentation/Permissions.md](Documentation/Permissions.md).

---

## Important limitation: group-based licensing

The license-removal stage targets **directly assigned** licenses.

If a user receives a license through group-based licensing:

```text
User
  ↓
Licensing Group
  ↓
Microsoft 365 License
```

the correct lifecycle operation is generally to remove the user from the licensing group according to the organization's access policy.

Do not treat a group-assigned license as a direct license.

---

## Testing

The project has been tested through the complete lifecycle in a test environment, including:

- dry-run detection
- expired-user identification
- separate disable confirmation
- successful account disable
- direct license discovery
- separate license confirmation
- successful direct-license removal
- post-removal verification
- audit event creation
- administrator notification
- notification state tracking

A successful end-to-end execution produced two lifecycle audit events:

```text
Disable
RemoveLicense
```

and one administrator notification containing both actions.

---

## Troubleshooting

See:

[Documentation/Troubleshooting.md](Documentation/Troubleshooting.md)

Common issues include:

- Graph module discovery
- insufficient Graph permissions
- stale Graph sessions
- missing reports
- audit schema migration
- group-based licensing
- notification failures
- running destructive scripts without the required confirmation

---

## Roadmap

### Completed

- [x] Expiry date management
- [x] Expired-user detection
- [x] Account disable automation
- [x] Direct license removal
- [x] Separate action confirmations
- [x] Dry-run mode
- [x] Force/automation mode
- [x] CSV reporting
- [x] Local audit trail
- [x] Administrator notification
- [x] Notification state tracking

### Planned

- [ ] Certificate-based Graph application authentication
- [ ] Least-privilege application permission model
- [ ] Scheduled Task deployment guide
- [ ] Config-driven execution
- [ ] Structured JSON logging
- [ ] Better group-based license handling
- [ ] Pester tests
- [ ] CI validation with GitHub Actions
- [ ] Additional lifecycle actions

---

## Microsoft Entra Lifecycle Workflows

Microsoft Entra ID also provides native Lifecycle Workflows for Joiner-Mover-Leaver scenarios.

This repository is a PowerShell/Graph automation project intended for administrators who want a script-driven implementation and learning platform. It does not replace the need to evaluate native Microsoft Entra Lifecycle Workflows for production requirements.

See Microsoft's Lifecycle Workflows documentation when deciding between native governance workflows and custom automation.

---

## Contributing

Issues, improvements, documentation updates, and PowerShell enhancements are welcome.

Before submitting changes:

1. Test in a non-production tenant.
2. Use `-WhatIf` where supported.
3. Never commit secrets or production exports.
4. Document new Graph permissions.
5. Include a clear description of destructive behavior.
6. Prefer least-privilege access.

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Security

See [Documentation/Security.md](Documentation/Security.md).

If you discover a security issue, do not publish credentials, tokens, tenant information, or other sensitive data in an issue.

---

## Author

**Mohammad Habib Khan**

Microsoft Endpoint & Identity Administrator

Focus areas:

- Microsoft Entra ID
- Microsoft Intune
- Microsoft Configuration Manager
- Active Directory
- Microsoft 365
- PowerShell automation
- Hybrid identity

---

## License

No license is currently declared by this documentation pack. Add a license before accepting external contributions if you intend to grant others explicit rights to use, modify, and redistribute the project.
