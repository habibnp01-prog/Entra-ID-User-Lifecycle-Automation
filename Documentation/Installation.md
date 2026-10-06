# Installation Guide

## Prerequisites

### Windows

- Windows 10/11 or Windows Server
- Windows PowerShell 5.1 or PowerShell 7+
- Internet connectivity to Microsoft Graph
- Microsoft Entra ID test tenant for initial validation

### Recommended

Run initial tests from a dedicated administrative workstation or test server.

Do not begin with production users.

---

## 1. Clone the repository

```powershell
git clone https://github.com/habibnp01-prog/Entra-ID-User-Lifecycle-Automation.git
cd Entra-ID-User-Lifecycle-Automation
```

---

## 2. Install Microsoft Graph PowerShell modules

Install the complete module set:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
```

Verify:

```powershell
Get-InstalledModule Microsoft.Graph.Authentication
Get-InstalledModule Microsoft.Graph.Users
Get-InstalledModule Microsoft.Graph.Users.Actions
Get-InstalledModule Microsoft.Graph.Identity.DirectoryManagement
```

---

## 3. Prepare project directories

The project expects:

```text
Config/
Logs/
Reports/
Scripts/
```

Keep these placeholders in Git:

```text
Logs/.gitkeep
Reports/.gitkeep
```

Do not commit generated reports or audit logs.

---

## 4. Set an expiry date

Run:

```powershell
cd Scripts
.\01-Set-UserExpiryDate.ps1
```

The script asks for:

- User Principal Name
- expiry/leave date

The date format is:

```text
YYYY-MM-DD
```

The script requests confirmation before changing the user.

---

## 5. Test detection

Run:

```powershell
.\02-Get-ExpiredUsers.ps1
```

This stage is read-only.

Expected output includes:

```text
Total users
Users with expiry date
Expired users
Expired + Enabled
Expired + Already Disabled
```

A report is generated under:

```text
Reports/ExpiredUsers_*.csv
```

---

## 6. Test the complete workflow safely

Run:

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com" `
    -WhatIf
```

Verify that:

- expired users are detected
- the CSV report is generated
- accounts are not modified
- licenses are not removed
- audit events are not written
- no email is sent

---

## 7. Run normal mode

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com"
```

The workflow asks separately:

```text
Disable expired user accounts? (Y/N)
```

and, after successful disables:

```text
Remove directly assigned licenses? (Y/N)
```

Only enter `Y` when the displayed accounts and intended action are correct.

---

## 8. Force mode

For controlled automation:

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com" `
    -Force
```

`-Force` bypasses the two interactive confirmation prompts.

Use this only after testing and approval.

---

## 9. Verify reports

After a successful execution:

```powershell
Get-ChildItem ..\Reports |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 Name, LastWriteTime
```

Expected report types:

```text
ExpiredUsers_*.csv
DisableExpiredUsers_*.csv
RemoveUserLicenses_*.csv
Notification_*.csv
```

---

## 10. Verify audit log

```powershell
.\05-Write-AuditLog.ps1 -ShowLog
```

The audit log is:

```text
Logs/EntraUserLifecycle_Audit.csv
```

---

## 11. Test notification

The orchestrator automatically invokes the notification stage after lifecycle actions.

You can also test the notification script directly:

```powershell
.\06-Send-AdminNotification.ps1 `
    -AdminEmail "admin@example.com" `
    -WhatIf
```

---

## Production automation

Before deploying as a Scheduled Task:

1. Replace interactive delegated authentication with application authentication.
2. Use a dedicated Entra application/service identity.
3. Use certificate-based authentication.
4. Review application permissions.
5. Store the certificate securely.
6. Test the workflow against a controlled pilot group.
7. Enable monitoring and alerting.
8. Define rollback and exception procedures.

Do not store credentials or certificates in the repository.
