# Entra ID User Lifecycle Automation

PowerShell-based automation for managing Microsoft Entra ID user lifecycle events using Microsoft Graph.

This project detects users whose configured leave/expiry date has passed, validates their account state, disables eligible accounts, records the action, and notifies administrators.

---

## Overview

Managing user accounts after an employee leaves an organization is an important identity and security task.

Manual lifecycle management can result in:

- Delayed account deactivation
- Unnecessary account exposure
- Inconsistent administrative processes
- Limited auditability
- Increased operational workload

This project automates the process using PowerShell and Microsoft Graph.

---

## Features

- Set Microsoft Entra ID user expiry/leave dates
- Detect expired users
- Identify expired accounts that are still enabled
- Disable expired accounts
- Skip accounts that are already disabled
- Generate CSV reports
- Create lifecycle audit events
- Send administrator email notifications
- Support `-WhatIf` / dry-run execution
- Support automation mode with `-Force`
- Modular PowerShell architecture
- Microsoft Graph integration
- Designed for scheduled execution

---

## Architecture

```text
                    Microsoft Entra ID
                           |
                           v
                  employeeLeaveDateTime
                           |
                           v
              PowerShell Lifecycle Engine
                           |
             +-------------+-------------+
             |             |             |
             v             v             v
       Expiry Detection  Validation   Account State
             |             |             |
             +-------------+-------------+
                           |
                           v
                  Disable Expired User
                           |
              +------------+------------+
              |                         |
              v                         v
         Audit Logging            Administrator
                                   Notification