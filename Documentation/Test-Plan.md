# Test Plan

## Purpose

Validate the lifecycle automation before production use.

---

## Test matrix

| Test | Expected result |
|---|---|
| Detection with no expired users | No modification |
| Detection with expired disabled user | Report shows `Already Disabled` |
| Detection with expired enabled user | Report shows `Disable Account` |
| WhatIf | No Entra modifications |
| Disable confirmation = N | No disable |
| Disable confirmation = Y | Account disabled |
| License confirmation = N | License remains |
| License confirmation = Y | Direct license removed |
| Group-assigned license | Direct-removal logic does not treat it as a direct assignment |
| Audit write | Unique EventId created |
| Notification | Successful events emailed |
| Notification rerun | Already-sent events not resent |
| Disable failure | Failure captured in audit |
| License failure | Failure captured in audit |

---

## Recommended test sequence

### Test 1 — Read-only detection

```powershell
.\02-Get-ExpiredUsers.ps1
```

Verify the CSV report.

### Test 2 — End-to-end WhatIf

```powershell
.\Run-EntraUserLifecycle.ps1 `
    -AdminEmail "admin@example.com" `
    -WhatIf
```

Verify:

```text
Users modified       : 0
Licenses removed     : 0
Audit events written : 0
Email sent           : No
```

### Test 3 — Cancel disable

Run normal mode and enter:

```text
N
```

Verify the account remains enabled.

### Test 4 — Approve disable

Run normal mode and enter:

```text
Y
```

Verify:

```text
accountEnabled = false
```

and confirm a `Disable` audit event is created.

### Test 5 — Cancel license removal

At:

```text
Remove directly assigned licenses? (Y/N)
```

enter:

```text
N
```

Verify the direct license remains.

### Test 6 — Approve license removal

Enter:

```text
Y
```

Verify the license is removed and the remaining assigned-license count is zero.

### Test 7 — Notification

Verify the administrator receives an email containing the successful lifecycle actions.

### Test 8 — Notification idempotency

Run notification again without creating a new lifecycle event.

Expected result:

```text
No successful unnotified lifecycle actions found.
```

---

## Production acceptance criteria

The project should not be scheduled for unattended execution until:

- [ ] WhatIf passes
- [ ] Disable test passes
- [ ] License removal test passes
- [ ] Audit test passes
- [ ] Notification test passes
- [ ] Notification idempotency test passes
- [ ] Least-privilege permissions are reviewed
- [ ] Application authentication is configured
- [ ] Rollback procedure is documented
