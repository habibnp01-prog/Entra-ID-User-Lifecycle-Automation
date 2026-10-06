# Contributing

Thank you for helping improve the project.

## Before making changes

- Test changes in a non-production environment.
- Avoid committing generated reports or logs.
- Never commit credentials or certificates.
- Document any new Microsoft Graph permissions.
- Clearly identify destructive operations.
- Preserve `-WhatIf` or safe testing behavior where applicable.

## PowerShell standards

Prefer:

- `Set-StrictMode` where compatible with the project
- explicit error handling
- `-ErrorAction Stop` for critical operations
- clear function names
- comments around destructive operations
- structured output/reporting
- least-privilege Graph permissions

## Pull requests

A useful pull request should include:

1. What changed
2. Why it changed
3. Which scripts are affected
4. Required Graph permissions
5. Testing performed
6. Any breaking changes

## Security

Do not report secrets or credentials in issues.

For sensitive security concerns, contact the repository owner privately.
