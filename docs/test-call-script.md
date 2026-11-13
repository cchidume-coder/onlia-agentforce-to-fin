<div align="center">

# 📞 Test-Call Script · Olivia

### What to say, what you should hear, and what to check in Salesforce

</div>

> [!NOTE]
> **Test contact:** Lauren Bailey (Contact `003000000000001AAA`), email `test.caller@example.com` (placeholder; use the contact's real inbox). Keep that inbox open, because the verification code and the pink slip arrive there.

> [!WARNING]
> The demo org can send only **15 single emails a day**. Once that's used up, codes and pink slips stop arriving even though Fin says they were sent.

## 🧭 Where to run it

| Option | How |
|---|---|
| **Real call via Salesforce** | Call the Salesforce number; `Route_Call_to_Fin` creates the Case and transfers to Fin |
| **Real call direct to Fin** | Call the Fin Voice number (no Case is created by the routing flow) |
| **Fin test panel** | Fin › Train › Procedures › open a procedure › **Test** (connectors must be **live**) |

---

## 1️⃣ Verify, then policy details

| # | You say | You should hear / see | Behind the scenes |
|:-:|---|---|---|
| 1 | "Hi, I'd like the details of my active policy." | Fin asks for your email (no answer yet) | Verify gate |
| 2 | Your email → "yes" to the read-back | "If that email is on file, you'll get a code shortly." | `SvcCopilotTmpl__SendVerificationCode` |
| 3 | Read the 6-digit code | Thanks you for verifying | `SvcCopilotTmpl__VerifyCode` |
| 4 | — | **Commercial Auto, CA-2024-90417** | `Onlia_Find_Active_Policy` |
| 5 | "What's the mailing address on it?" | **1 Market St, San Francisco, CA 94105** | from the same lookup |
| 6 | "What's the commission or GWP?" | Fin refuses | never exposed by the connector |

## 2️⃣ Same call, more requests (no second code)

| You say | You should hear / see |
|---|---|
| "What's the status of my quote?" | **00000021 · Presented · expires 24 Feb 2027**, with no new verification |
| "Can you email me my pink slip?" | Natural read-back of your email → waits for **yes** → sends; the PDF arrives |

## 3️⃣ General question (no verification)

| You say | You should hear / see |
|---|---|
| "Can I bundle my car and home insurance?" | Up to **20% car / 30% home**, from the knowledge article, with no email or code request |
| "What liability limits can I choose on car insurance?" | **$200,000** minimum; **$500K / $1M / $2M** options (Ontario information) |

## 4️⃣ Broker handoff (case updated first)

| You say | You should hear / see |
|---|---|
| After the pink slip: "I'd like to upgrade. Can I speak with a broker?" | "You'll be passed over to a licensed broker now." |
| "Can you waive my late fee?" | "That's not something I'm able to handle…", then the handoff |

> [!TIP]
> When the call reaches the broker in Salesforce, the Voice Call should show the **Case** and **Lauren Bailey**, and the Case should already have Fin's subject (for example *"Policy upgrade request – caller verified"*) and summary.

## 🔎 Check Salesforce afterwards

```bash
sf data query -o onlia -q "SELECT CaseNumber, Subject, Description, LastModifiedDate FROM Case WHERE ContactId='003000000000001AAA' ORDER BY LastModifiedDate DESC LIMIT 3"
```

```bash
sf data query -o onlia -q "SELECT Name, Case__c, Contact__c, RelatedRecordId FROM VoiceCall ORDER BY CreatedDate DESC LIMIT 1"
```
