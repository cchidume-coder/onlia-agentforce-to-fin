<div align="center">

# 🔌 Fin Data Connectors · Onlia

### The 11 connectors Olivia uses to reach Salesforce

![Count](https://img.shields.io/badge/Connectors-11-1F8DED)
![Auth](https://img.shields.io/badge/Auth-OAuth%20client%20credentials-6E40C9)
![API](https://img.shields.io/badge/Salesforce%20API-68.0-0B5CAB)

</div>

> [!NOTE]
> Connectors can't be exported with the CLI token used for this project, so this page documents them by hand. It matches the live configuration.

## ⚙️ Shared settings

| Setting | Value |
|---|---|
| **Base URL** | `{instance}` = `https://your-org.my.salesforce.com` (demo org) |
| **Flow connectors** | `POST {instance}/services/data/v68.0/actions/custom/flow/<FLOW>` |
| **Auth** | Fin Authentication token "Salesforce - Production" (OAuth client credentials, `Authorization: Bearer`) |
| **Header** | `Content-Type: application/json` |
| **Body** | `{"inputs":[{ ... }]}`, with inputs written as bare `{{name}}` placeholders |
| **Response** | One-item array; values in `[0].outputValues`. Failure = `[0].isSuccess` false or `[0].errors` not empty |
| **Code block** | Returns `isSuccess`, `errors` and an **allow-list** of `outputValues` fields only |
| **Usage** | Procedures only (not chosen by Fin on its own) |

## 🔐 Identity

| Connector | Flow | Inputs | Exposed to Fin | Never exposed |
|---|---|---|---|---|
| **Onlia Send Verification Code** | `SvcCopilotTmpl__SendVerificationCode` | `customerToVerify` (email) | `authenticationKey`, `customerId`, `customerType`, `verificationMessage` | 🚫 `verificationCode` |
| **Onlia Verify Code** | `SvcCopilotTmpl__VerifyCode` | `customerCode`, `customerId`, `customerType`, `authenticationKey` | `isVerified`, `customerId`, `customerType` | |

## 📄 Policy & quote

| Connector | Flow | Inputs | Exposed to Fin | Never exposed |
|---|---|---|---|---|
| **Onlia Find Active Policy** | `Onlia_Find_Active_Policy` | `contactId` | `policyId`, `policyName`, `policyNumber`, `policyType`, `mailingAddress` | 🚫 `gwp` |
| **Onlia Find Quote** | `Onlia_Find_Quote` | `contactId` | `quoteId`, `quoteNumber`, `status`, `expirationDate` | |

## ✉️ Fulfilment & account  *(write actions)*

| Connector | Flow | Inputs | Exposed to Fin |
|---|---|---|---|
| **Onlia Send Pink Slip Email** | `Onlia_Send_Pink_Slip_Email` | `policyId`, `contactId`, `confirmedEmail` | `confirmationMessage`, `errorMessage` |
| **Onlia Send Pink Slip Mail** | `Onlia_Send_Pink_Slip_Mail` | `policyId`, `contactId`, `confirmedMailingAddress` | `orderId`, `confirmationMessage`, `errorMessage` |
| **Onlia Update Contact** | `SvcCopilotTmpl__UpdateVrfyCtct` | `verifiedContactID` + only the changed fields: `newStreetAddress`, `newCity`, `newState`, `newPostalCode`, `newEmailAddress`, `newPhoneNumber` | success only |
| **Onlia Schedule Callback** | `Onlia_Schedule_Callback` | `contactId`, `preferredPhone`, `requestDescription` | `contactRequestId`, `confirmationMessage` |

## 🗂️ Case

| Connector | Request | Inputs | Exposed to Fin |
|---|---|---|---|
| **Onlia Find Latest Case** | `GET {instance}/services/data/v68.0/query?q=SELECT+Id,CaseNumber,Subject,Status+FROM+Case+WHERE+ContactId='{{contactId}}'+AND+IsClosed=false+ORDER+BY+CreatedDate+DESC+LIMIT+1` | `contactId` | `found`, `caseId`, `caseNumber`, `subject`, `status` |
| **Onlia Update Case** *(write)* | `POST …/flow/Onlia_Update_Or_Create_Case` with `recordId` = `{{caseId}}` | `caseId`, `contactId`, `newSubject`, `newDescription` (all required) | `caseId`, `wasUpdated` |
| **Onlia Update Or Create Case** *(write)* | `POST …/flow/Onlia_Update_Or_Create_Case` **without** `recordId` | `contactId`, `newSubject`, `newDescription` | `caseId`, `wasUpdated` |

> [!WARNING]
> **Why two case connectors share one flow:** the flow takes its update path when `recordId` isn't *null*, and Fin sends a blank input as `""`. A single connector with an optional `recordId` would send `""` and break case creation. So **Update Case** always has an ID, and **Update Or Create Case** never sends one.

## ✅ Rules

1. **Send Verification Code** and **Verify Code** run *before* the caller is verified; everything else runs only after a successful Verify Code.
2. `contactId` always comes from the `customerId` of a successful **Verify Code**. Fin never asks the caller for it.
3. Write connectors need a read-back and an explicit **yes** in the procedure first.
4. Turn off Fin's customer-verification requirement on these connectors for voice; the email code is the identity check.
5. Each connector needs a passing **live test** before it can be published. Write connectors create real records, so test with a sandbox contact.
6. **Update Contact:** blank fields may overwrite existing values, so send only what the caller is changing.
