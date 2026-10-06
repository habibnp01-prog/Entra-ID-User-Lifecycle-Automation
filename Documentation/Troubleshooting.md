# Troubleshooting Guide

## 1. Microsoft Graph module not found

### Symptom

```text
Required module 'Microsoft.Graph.Users' was not found.
```

### Fix

```powershell
Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force
```

For the complete project:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force
```

Then verify:

```powershell
Get-InstalledModule Microsoft.Graph*
```

---

## 2. Graph permission error

### Symptom

A script connects successfully but fails when reading or modifying users.

### Check the current session

```powershell
Get-MgContext | Format-List Account,TenantId,Scopes
```

Compare the session with the permissions documented in:

```text
Documentation/Permissions.md
```

If the required delegated scope is missing, reconnect with the required permission.

---

## 3. Existing Graph session has excessive scopes

A PowerShell session can retain scopes from earlier testing.

Check:

```powershell
Get-MgContext
```

Do not assume the displayed broad scope list represents the project's intended least-privilege model.

Reconnect deliberately when testing permission boundaries.

---

## 4. No expired users found

The detection logic considers a user expired when:

```text
employeeLeaveDateTime < today's date
```

A leave date equal to today is not treated as expired by this project.

Check a user:

```powershell
Get-MgUser `
    -UserId "user@example.com" `
    -Property DisplayName,UserPrincipalName,AccountEnabled,EmployeeLeaveDateTime |
    Select-Object DisplayName,UserPrincipalName,AccountEnabled,EmployeeLeaveDateTime
```

---

## 5. Detection report cannot be found

The orchestrator expects:

```text
Reports/ExpiredUsers_*.csv
```

Run detection directly:

```powershell
.\02-Get-ExpiredUsers.ps1
```

Then verify:

```powershell
Get-ChildItem ..\Reports\ExpiredUsers_*.csv |
    Sort-Object LastWriteTime -Descending
```

---

## 6. Disable report cannot be found

The orchestrator expects:

```text
Reports/DisableExpiredUsers_*.csv
```

Run:

```powershell
.\03-Disable-ExpiredUsers.ps1
```

The script should create a timestamped report after processing.

---

## 7. User is already disabled

This is expected behavior.

The detection stage distinguishes:

```text
Expired + Enabled
```

from:

```text
Expired + Already Disabled
```

Only expired and enabled users are eligible for the disable operation.

---

## 8. License cannot be removed

First verify the user's assigned licenses.

The license script displays the assigned licenses before attempting removal.

If the license is inherited through group membership, direct license removal is not the correct action.

Check the user's licensing groups and organizational licensing policy.

---

## 9. Audit log append error

### Symptom

An error indicates that the CSV schema does not match an older audit file.

The audit script contains migration handling for the legacy `ExecutedBy` field.

If needed, inspect:

```text
Logs/EntraUserLifecycle_Audit.csv
```

Do not manually delete the audit history unless the organization has approved that action.

---

## 10. Notification says no unnotified actions

The notification script selects successful audit events whose:

```text
NotificationStatus
```

is not already:

```text
Sent
```

Check the audit log:

```powershell
.\05-Write-AuditLog.ps1 -ShowLog
```

If all successful events are already marked `Sent`, no new email is expected.

---

## 11. Notification email fails

Check:

```powershell
Get-MgContext | Format-List Account,TenantId,Scopes
```

The notification stage requires:

```text
User.Read.All
Mail.Send
```

Also verify that the sending account can send mail through Microsoft Graph.

---

## 12. Test safely

Start with:

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com" `
    -WhatIf
```

Do not start with `-Force`.

---

## 13. PowerShell command parsing problems

When writing multiline PowerShell commands with backticks:

```powershell
$Result = Some-Command `
    -Parameter1 "Value" `
    -Parameter2 "Value"
```

do not place a blank line immediately after a backtick.

A blank line terminates the continuation and can cause errors such as:

```text
The term '-Parameter1' is not recognized
```

Prefer splatting for complex commands where practical.

---

## 14. Production authentication

If a Scheduled Task cannot authenticate interactively, this is expected with the current delegated authentication model.

The production roadmap is:

```text
App Registration
      ↓
Certificate
      ↓
Microsoft Graph application authentication
      ↓
Scheduled Task
      ↓
Run-EntraUserLifecycle.ps1 -Force
```

Do not solve this by storing a username/password in the script.
