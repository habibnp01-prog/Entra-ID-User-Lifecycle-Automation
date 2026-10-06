# Microsoft Graph Permissions

## Permission model

The project uses different Graph permissions depending on the operation.

| Script | Permissions | Why |
|---|---|---|
| `01-Set-UserExpiryDate.ps1` | `User.ReadWrite.All` | Read and update `employeeLeaveDateTime` |
| `02-Get-ExpiredUsers.ps1` | `User.Read.All` | Read users and expiry information |
| `03-Disable-ExpiredUsers.ps1` | `User.Read.All`, `User.ReadWrite.All` | Read users and disable accounts |
| `04-Remove-UserLicenses.ps1` | `User.Read.All`, `LicenseAssignment.ReadWrite.All` | Read assignments and remove direct licenses |
| `05-Write-AuditLog.ps1` | None | Writes to local CSV only |
| `06-Send-AdminNotification.ps1` | `User.Read.All`, `Mail.Send` | Read context and send notification email |
| `Run-EntraUserLifecycle.ps1` | Inherits requirements of called scripts | Orchestrates the workflow |

---

## Delegated vs application permissions

The current project uses interactive Microsoft Graph authentication.

This is useful for:

- development
- testing
- administrator-driven execution
- troubleshooting

For unattended production execution, use an application identity with certificate-based authentication.

---

## Least privilege

Do not give a script more permissions than it needs.

For example:

### Detection

```text
User.Read.All
```

is sufficient for the read-only detection stage.

### Disable

The account-disable stage requires write access:

```text
User.ReadWrite.All
```

### License removal

The license-removal stage requires:

```text
User.Read.All
LicenseAssignment.ReadWrite.All
```

### Notification

The notification stage requires:

```text
User.Read.All
Mail.Send
```

---

## Important: delegated testing sessions

A Microsoft Graph PowerShell session can already contain many permissions from previous tests.

For example, an existing session may show permissions unrelated to this project.

Do not copy a broad interactive session's scope list into production documentation as the project's required permission model.

Review the actual permissions requested by each script.

---

## Application permission hardening

Before unattended deployment:

1. Create a dedicated App Registration.
2. Add only the required application permissions.
3. Grant admin consent.
4. Use certificate authentication.
5. Store the certificate securely.
6. Restrict who can manage the application.
7. Monitor sign-ins and Graph activity.
8. Periodically review permissions.

---

## License removal warning

`LicenseAssignment.ReadWrite.All` is powerful.

The project intentionally limits its lifecycle license stage to licenses assigned directly to the user.

For group-based licensing:

```text
User
  ↓
Group membership
  ↓
License assignment
```

change the group membership according to organizational policy rather than trying to remove the license directly.

---

## Security principle

Treat the following as privileged operations:

- changing `employeeLeaveDateTime`
- disabling accounts
- removing licenses
- sending administrative notifications

Use a test tenant or pilot users before production rollout.
