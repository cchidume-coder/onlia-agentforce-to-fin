<div align="center">

# 🗺️ Migration Map · Onlia Service Agent v10 → Fin Voice

### The original inventory, written at the start of the project

</div>

> [!IMPORTANT]
> **This is the historical starting point**: the first inventory of the Agentforce agent and the *proposed* Fin mapping. Several plans changed during the build (for example the Apex card actions were dropped and the case connectors were split). For what was actually built, see the **[conversion guide](agentforce-to-fin-conversion-guide.md)**.

Source: org `onlia` (admin@your-org.example), `Onlia_Service_Agent` v10 (Active), Agent Script decoded from
`sfdx/force-app/main/default/genAiPlannerBundles/Onlia_Service_Agent_v10/agentScript/*.agent` (stored base64-encoded).

> Fin-side column is a **proposed** mapping using Fin's general building blocks (Guidance, Procedures,
> Data connectors, Content, Handoff). Confirm names/capabilities against the actual Fin Voice workspace before building.

## 1. Agent-level

| Salesforce | Value | Fin equivalent |
|---|---|---|
| Persona / system instructions | "Ollie", warm/concise/professional, AI disclosure, ground every fact in action data, never quote binding rate / guarantee coverage / promise changes (regulated insurance) | Global Guidance / persona + tone settings; compliance rules as top-priority guidance |
| Welcome message | "Thank you for contacting Onlia Insurance. My name is Ollie…" | Fin Voice greeting |
| Error message | "Sorry, something went wrong on my end. Let me try that again." | Fallback/error phrasing |
| Locale | en_US | Language setting |
| Voice modality | voice_id `31eda511aca2`, speed 1.06, stability 0.6, similarity 0.85 | Fin Voice voice selection (voice IDs are ElevenLabs-style and will **not** carry over; pick/clone a voice) |
| Telephony escalation | Flow `SDO_Service_Voice_Escalation`; msg "One moment, I'm transferring… licensed Onlia broker"; `auto_hangup=false` | Handoff to teammate/team + phone transfer target; preserve the message |
| Messaging escalation | Flow `SDO_Service_ASA_Outbound_Route_to_Queue` | Out of scope for voice-only migration |

## 2. Topology (router + 8 subagents)

```
agent_router (start)
 ├─ ServiceCustomerVerification   ← forced first if not verified
 ├─ quote_management        (verified only)
 ├─ policy_and_pink_slip    (verified only)
 ├─ AccountManagement       (verified only)
 ├─ coverage_upgrade        (verified only) → conversation_summary → escalate
 ├─ off_topic
 └─ ambiguous_question
```

| Subagent | Purpose | Fin equivalent |
|---|---|---|
| agent_router | Set ChannelType, derive EffectiveContactId, gate on verification, route by intent | Fin intent routing + verification gate precondition on each Procedure |
| ServiceCustomerVerification | Email/username → emailed OTP → verify; 3 wrong codes → restart; never reveal if account exists; no user switching | Procedure "Verify caller" (voice-adapted, see §5) |
| quote_management | Silent quote lookup, confirm quote on horizon, explain timeline, read summary; offer broker for finalizing | Procedure "Quote status" |
| policy_and_pink_slip | Find active policy, summarize, pink slip by email and/or physical mail (explicit confirm each) | Procedure "Policy & pink slip" |
| AccountManagement | Update contact (email/phone/address), reset password link | Procedure "Update contact" / "Reset password" |
| coverage_upgrade | Change/upgrade/pricing/billing/"talk to a person": offer Call Now / Transfer / Schedule Callback | Handoff Procedure (voice: transfer or callback only) |
| conversation_summary | Find/update/create Case with subject + 3–5 sentence summary, GWP-based priority, then escalate | Pre-handoff summary → write to SF Case via connector; Fin conversation summary/note on handoff |
| off_topic | Redirect, no general-knowledge answers, no prompt leakage | Scope guidance |
| ambiguous_question | Ask for specifics, no actions | Clarification guidance |

## 3. Actions inventory (Salesforce targets to re-expose to Fin)

| Action | Target | Confirm? | Inputs → outputs | Fin approach |
|---|---|---|---|---|
| SendEmailVerificationCode | flow `SvcCopilotTmpl__SendVerificationCode` | no | customerToVerify → authenticationKey, customerId, customerType, verificationCode(hidden) | Data connector → SF REST/Apex endpoint |
| VerifyCustomer | flow `SvcCopilotTmpl__VerifyCode` | no | authKey, customerCode, customerId, customerType → isVerified, customerId | Data connector |
| find_quote | flow `Onlia_Find_Quote` | no | contactId → isSuccess, quoteId | Data connector |
| Get_Quote_Summary | apex `OnliaGetQuoteSummaryAction` | no | contactId, messagingSessionId, quoteId → quote object (card payload) | Data connector; **return voice-friendly text, not card payload** |
| find_active_policy | flow `Onlia_Find_Active_Policy` | no | contactId → policyId/name/number/type, gwp, mailingAddress | Data connector |
| Get_Policy_Summary | apex `OnliaGetPolicySummaryAction` | no | contactId, messagingSessionId, policyId → policy object | Data connector (text output) |
| send_pink_slip_email | flow `Onlia_Send_Pink_Slip_Email` | **yes** | policyId, contactId, confirmedEmail → isSuccess, confirmationMessage | Data connector + explicit read-back confirm |
| send_pink_slip_mail | flow `Onlia_Send_Pink_Slip_Mail` | **yes** | policyId, contactId, confirmedMailingAddress → isSuccess, orderId, confirmationMessage | Data connector + read-back confirm |
| UpdateVerifiedContact | flow `SvcCopilotTmpl__UpdateVrfyCtct` | **yes** | verifiedContactID, newStreet/City/State/Postal, newEmail, newPhone | Data connector + read-back confirm |
| ResetSecurePassword | flow `SvcCopilotTmpl__ResetScrPassword` | **yes** | verifiedContactID → outcomeMessage | Data connector |
| Get_Upgrade_Options | apex `OnliaGetUpgradeOptions` | no | contactId → options card | **Drop for voice**; replaced by spoken menu |
| call_now | flow `Initiate_Outbound_Call_for_Contact` | **yes** | recordId (contact) → callRequested | Probably replaced by native transfer; for voice caller this is redundant |
| schedule_callback | flow `Onlia_Schedule_Callback` | no | contactId, preferredPhone, requestDescription → isSuccess, contactRequestId, confirmationMessage | Data connector |
| get_case_from_session | flow `Onlia_Get_Case_From_Session` | no | messagingSessionId → caseId | Messaging-session based; **rework for voice (VoiceCall id)** |
| update_or_create_case | flow `Onlia_Update_Or_Create_Case` | no | recordId, contactId, newSubject, newDescription, gwp → caseId, wasUpdated | Data connector, called before handoff |

## 4. State variables

| Variable | Role | Fin note |
|---|---|---|
| ChannelType (Voice/Messaging) | channel branching | Not needed once voice-only |
| VoiceCallId, CallerId (ANI), Contact (VoiceCall.Contact__c) | linked voice context | Fin provides caller phone number; use to look up Contact (also enables skipping/strengthening verification) |
| EndUserId, RoutableId, ContactId, EndUserLanguage | messaging-session links | Drop |
| isCustomerVerified, verifiedEmail, verificationSent, authKey, Resolved_Contact_Type, ResolvedContactId, EffectiveContactId, CustomerName | verification state | Procedure-scoped/conversation attributes |
| quoteId, policyId, policyGwp, quoteCardShown, policyCardShown, pinkSlipEmailed, pinkSlipMailed, addressUpdated | de-dup/idempotency flags | Needed to prevent duplicate sends; implement in procedure steps/attributes |
| caseId, newSubject, newDescription, conversationUpdated | handoff case state | Same |

## 5. Gaps and voice-specific risks

1. **Hard-coded test IDs in defaults**: `EffectiveContactId = 003000000000001AAA` and `policyId = a4q000000000001AAA` are baked in as variable defaults. Remove before any real migration; they bypass lookup.
2. **Card/CLT rendering is messaging-only** (`quote`, `policy`, `upgrade options` outputs use custom Lightning types). Fin Voice needs text/speech outputs. Either add voice-safe text fields to the Apex actions or format in the connector layer.
3. **Verification by emailed OTP over a phone call**: caller must read a code from email. Works, but plan for speech-to-text accuracy on codes/emails (spell-back, "is that right?"). Consider ANI match as a first factor.
4. **Escalation and callback depend on Salesforce Omni-Channel flows** (`SDO_Service_Voice_Escalation`). Fin handoff needs a phone transfer target; confirm whether live-broker routing stays in Salesforce (SIP/PSTN transfer) or moves to Intercom teammates.
5. **Case creation keyed on MessagingSession**: `get_case_from_session` won't work for voice-originated calls; use VoiceCall id or create-only.
6. **Source not yet retrieved**: only bot + planner bundle are in `sfdx/`. Flows (`Onlia_*`, `SvcCopilotTmpl__*`) and Apex (`Onlia*Action`) must be retrieved to design the API surface Fin will call.
7. **Security of connection**: Fin data connectors need an authenticated path into Salesforce (Connected App / External Client App with OAuth, least-privilege integration user, or middleware). Needs decision and the credentials set up by you.
8. **Compliance guardrails** (no binding quotes, no coverage promises, broker handoff for billing/changes) must be reproduced as top-priority Fin guidance and tested.

## 6. Proposed build order

1. Retrieve flows/Apex source from `onlia` org; document each one's real inputs/outputs.
2. Decide the Salesforce API surface for Fin (REST via External Client App vs. Apex REST wrappers).
3. Build Fin: persona/guidance → verification procedure → policy/pink slip → quote → account → handoff/callback.
4. Voice tuning (voice, pacing, read-back confirmations).
5. Test against recorded scenarios; compare with `agentforce-test` results for v10.

## 7. Retrieved source (added after org retrieval)

Retrieved into `sfdx/force-app/main/default/` from org `onlia`: 14 flows, 4 Apex classes
(`OnliaGetQuoteSummaryAction`, `OnliaGetPolicySummaryAction`, `OnliaGetUpgradeOptions`, `OnliaSendPinkSlipEmail`).

| Agent action | Real implementation | Status |
|---|---|---|
| find_quote / find_active_policy | Flows `Onlia_Find_Quote` (Quote), `Onlia_Find_Active_Policy` (Insurance_Policy__c) | retrieved |
| Get_Quote / Policy_Summary, Get_Upgrade_Options | Apex classes of the same names | retrieved |
| send_pink_slip_email | Flow → Apex `OnliaSendPinkSlipEmail` | retrieved |
| send_pink_slip_mail | Flow creates an `Order` for the policy | retrieved |
| schedule_callback | Flow creates `ContactRequest` | retrieved |
| call_now | Flow `Initiate_Outbound_Call_for_Contact` | retrieved |
| get_case / update_or_create_case | Flows (MessagingSession, Case) | retrieved |
| Voice escalation | Flow `SDO_Service_Voice_Escalation` (Group, VoiceCall) | retrieved |
| SendEmailVerificationCode / VerifyCustomer | Agent references `SvcCopilotTmpl__*` (not found by that name). Likely backing flows: `Send_Verification_Code_to_Customer`, `Validate_Customer_Verification_Code`, `validate_verification_code`, `Get_Verified_Customer_Information` | retrieved, **mapping unconfirmed** |
| ResetSecurePassword | Probably `SDO_Service_Password_Reset` | retrieved, **mapping unconfirmed** |
| UpdateVerifiedContact | `SvcCopilotTmpl__UpdateVrfyCtct` not found; candidates `Onlia_Update_Contact_Address`, `SDO_Service_Update_Customer_Information` | **not retrieved** |

Open: confirm the `SvcCopilotTmpl__*` -> flow mapping (check the GenAiFunction / planner bundle metadata).
