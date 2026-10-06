# Permissions Guide



## Entra ID User Lifecycle Automation



This document describes the Microsoft Graph permissions required by the Entra ID User Lifecycle Automation project.



\---



## 1. Overview



The automation uses Microsoft Graph PowerShell to:



\- Read Microsoft Entra ID users

\- Read user lifecycle information

\- Set the `employeeLeaveDateTime` attribute

\- Disable expired user accounts

\- Send administrator notification emails

\- Record audit information locally



The required permissions depend on which script is being executed.



\---



## 2. Microsoft Graph Permissions



### Script 01 — Set User Expiry Date



\*\*Script:\*\*



```text

Scripts\\01-Set-UserExpiryDate.ps1


