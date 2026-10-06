# Security Guidance

## Scope

This project performs privileged Microsoft Entra ID operations.

It can:

- change user expiry information
- disable accounts
- remove directly assigned licenses
- send administrative email

Treat the project as administrative automation.

---

## Never commit secrets

Do not commit:

- client secrets
- certificates
- `.pfx` files
- private keys
- access tokens
- refresh tokens
- passwords
- production exports
- production audit logs
- tenant-specific confidential information

The repository `.gitignore` should exclude these items.

---

## Test before production

Use a test tenant or controlled pilot users.

Recommended progression:

```text
Code review
   ↓
WhatIf
   ↓
Test user
   ↓
Small pilot group
   ↓
Production
```

---

## Destructive operations

Two actions modify access:

### Account disable

Disables the user's Entra ID account.

### Direct license removal

Removes licenses assigned directly to the user.

Both are protected by interactive confirmation in normal mode.

`-Force` bypasses these confirmations and should therefore be restricted to approved automation scenarios.

---

## Auditability

Every lifecycle action should have a unique:

```text
EventId
```

The audit event records:

- action
- target user
- result
- execution identity
- computer
- tenant
- notification state

This provides operational traceability.

---

## Notification safety

Notifications should not contain:

- passwords
- access tokens
- secrets
- authentication material

Keep notification content limited to operational lifecycle information.

---

## Least privilege

Use per-script permissions where possible.

Do not use a broad administrator session as a substitute for a documented permission model.

For unattended execution, use a dedicated App Registration and review application permissions regularly.

---

## Group-based licensing

Do not attempt to remove a group-assigned license as though it were a direct assignment.

Use the organization's approved group membership workflow.

---

## Production checklist

Before enabling scheduled execution:

- [ ] Test with `-WhatIf`
- [ ] Test with a dedicated pilot user
- [ ] Confirm the expiry-date source
- [ ] Confirm the disable policy
- [ ] Confirm the licensing policy
- [ ] Confirm notification recipients
- [ ] Review Graph permissions
- [ ] Configure certificate-based authentication
- [ ] Secure the certificate
- [ ] Restrict script execution host
- [ ] Protect audit logs
- [ ] Configure monitoring
- [ ] Define rollback procedures
- [ ] Document ownership and support contacts
