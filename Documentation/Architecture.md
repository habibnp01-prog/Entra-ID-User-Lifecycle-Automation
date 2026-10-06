# Architecture

## Lifecycle flow

```text
                   HR / Administrator
                          │
                          ▼
              employeeLeaveDateTime
                          │
                          ▼
              01 Set User Expiry Date
                          │
                          ▼
                  02 Detect Expired
                          │
                          ▼
                Expired + Enabled?
                     │          │
                    No         Yes
                     │          │
                     │          ▼
                     │       Confirm
                     │          │
                     │          ▼
                     │       03 Disable
                     │          │
                     │          ▼
                     │       05 Audit
                     │          │
                     │          ▼
                     │       Confirm
                     │          │
                     │          ▼
                     │       04 Remove
                     │       Direct Licenses
                     │          │
                     │          ▼
                     │       05 Audit
                     │          │
                     └──────────┤
                                ▼
                       06 Notification
                                │
                                ▼
                       Administrator Email
```

---

## Script responsibilities

| Component | Responsibility |
|---|---|
| `01-Set-UserExpiryDate.ps1` | Set user expiry/leave date |
| `02-Get-ExpiredUsers.ps1` | Read-only detection |
| `03-Disable-ExpiredUsers.ps1` | Disable expired enabled accounts |
| `04-Remove-UserLicenses.ps1` | Remove direct licenses |
| `05-Write-AuditLog.ps1` | Local audit persistence |
| `06-Send-AdminNotification.ps1` | Administrator notification |
| `Run-EntraUserLifecycle.ps1` | Workflow orchestration |

---

## Data flow

```text
Microsoft Entra ID
       │
       ├── User data
       │
       ▼
02 Detection
       │
       ▼
Reports/ExpiredUsers_*.csv
       │
       ▼
03 Disable
       │
       ▼
Reports/DisableExpiredUsers_*.csv
       │
       ▼
05 Audit
       │
       ▼
Logs/EntraUserLifecycle_Audit.csv
       │
       ▼
04 License Removal
       │
       ▼
05 Audit
       │
       ▼
06 Notification
       │
       ├── Microsoft Graph Mail
       │
       ▼
Reports/Notification_*.csv
```

---

## Design principles

### Separation of detection and modification

Detection is read-only.

Modification is performed only by dedicated lifecycle scripts.

### Confirmation before destructive actions

Normal mode asks before:

- disabling accounts
- removing direct licenses

### Report-driven orchestration

The orchestrator uses generated CSV reports as explicit outputs from the child lifecycle scripts.

This makes the workflow easier to inspect and troubleshoot.

### Audit before notification

Lifecycle events are written to the audit log before the notification stage selects them.

### Event-based notification

Every lifecycle event receives a unique `EventId`.

Notification status is tracked per event so the same event is not repeatedly notified after a successful send.

---

## Future architecture

For unattended production execution:

```text
Scheduled Task
      │
      ▼
Run-EntraUserLifecycle.ps1 -Force
      │
      ▼
Certificate-based Graph authentication
      │
      ▼
Microsoft Graph
      │
      ├── Users
      ├── Licenses
      └── Mail
```

Future enhancements can add:

- centralized configuration
- structured JSON logging
- Pester tests
- GitHub Actions
- SIEM integration
- group-license lifecycle handling
- service-account/application identity
