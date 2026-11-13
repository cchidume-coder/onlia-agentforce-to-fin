/**
 * CLT card action for the Onlia Service Agent (Enhanced Chat v2 / Messaging).
 *
 * Returns a PolicySummaryOutput DTO carrying a single JSON payload that the
 * onliaPolicySummaryCard LWC renders in-chat. Resolves the policy from an
 * explicit policyId when the planner supplies one, otherwise from the
 * conversation's contact via a three-tier fallback ladder (reads only).
 *
 * Sharing: `without sharing` — the EinsteinServiceAgent bot user has no sharing
 * access to Insurance_Policy__c, so `with sharing` would return silent empties.
 * Never throws: every failure path returns a valid DTO carrying {"error": "..."}
 * so the card can render an error state.
 */
global without sharing class OnliaGetPolicySummaryAction {

    global class Input {
        @InvocableVariable(label='Policy ID'
            description='The Insurance_Policy__c record Id to display. If blank, the contact\'s most recent Active policy is used.'
            required=false)
        global String policyId;

        @InvocableVariable(label='Contact ID'
            description='The Salesforce Contact ID of the customer whose active policy to display'
            required=false)
        global String contactId;

        @InvocableVariable(label='Messaging Session ID'
            description='The Messaging Session ID — used to resolve the Contact when Policy ID and Contact ID are not available'
            required=false)
        global String messagingSessionId;
    }

    global class Response {
        @InvocableVariable
        global Boolean success;

        // @InvocableVariable declares the DTO as an action output. Inside the DTO
        // the String field is @AuraEnabled only.
        @InvocableVariable(label='Policy Summary Output'
            description='Structured payload for the onliaPolicySummaryCard renderer')
        global PolicySummaryOutput policy;

        // Flat passthrough so the planner can chain the pink-slip / escalation
        // actions without re-parsing the (filtered) card JSON.
        @InvocableVariable
        global String resolvedPolicyId;

        @InvocableVariable
        global String errorMessage;
    }

    @InvocableMethod(label='Get Policy Summary'
        description='Returns the customer\'s active commercial insurance policy as a renderable summary card. The output of this action is always renderable, always use show_command.'
        category='Onlia')
    global static List<Response> execute(List<Input> inputs) {
        List<Response> results = new List<Response>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        for (Input inp : inputs) {
            Response res = new Response();
            try {
                Insurance_Policy__c policy = resolvePolicy(inp);

                Map<String, Object> payload = new Map<String, Object>();
                if (policy == null) {
                    payload.put('error', 'No active policy was found for this conversation.');
                } else {
                    payload.put('policyName', policy.Name);
                    payload.put('policyNumber', nullToDash(policy.Policy_Number__c));
                    payload.put('policyType', nullToDash(policy.Policy_Type__c));
                    payload.put('status', nullToDash(policy.Status__c));
                    payload.put('gwp', formatCurrency(policy.GWP__c));
                    payload.put('premium', formatCurrency(policy.Premium__c));
                    payload.put('commission', formatCurrency(policy.Commission__c));
                    payload.put('mailingAddress', nullToDash(policy.Policy_Mailing_Address__c));
                    res.resolvedPolicyId = policy.Id;
                }

                res.policy = new PolicySummaryOutput(JSON.serialize(payload));
                res.success = !payload.containsKey('error');

            } catch (Exception e) {
                res.success = false;
                res.errorMessage = e.getMessage();
                res.policy = new PolicySummaryOutput(
                    JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() })
                );
            }
            results.add(res);
        }
        return results;
    }

    /**
     * Resolves the policy to display: explicit policyId first, then the contact's
     * most recent Active policy, resolving the contact through a three-tier ladder.
     * @param inp The action input.
     * @return The matched policy, or null when none can be resolved.
     */
    private static Insurance_Policy__c resolvePolicy(Input inp) {
        // Direct: an explicit policy Id (e.g. supplied by a prior Find Active Policy).
        if (String.isNotBlank(inp.policyId)) {
            Id policyId = (Id) inp.policyId;
            List<Insurance_Policy__c> byId = [
                SELECT Id, Name, Policy_Number__c, Policy_Type__c, Status__c,
                       GWP__c, Premium__c, Commission__c, Policy_Mailing_Address__c
                FROM Insurance_Policy__c
                WHERE Id = :policyId
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                return byId[0];
            }
        }

        // Resolve the contact, then its most recent Active policy.
        Id contactId = resolveContactId(inp);
        if (contactId == null) {
            return null;
        }
        List<Insurance_Policy__c> byContact = [
            SELECT Id, Name, Policy_Number__c, Policy_Type__c, Status__c,
                   GWP__c, Premium__c, Commission__c, Policy_Mailing_Address__c
            FROM Insurance_Policy__c
            WHERE Contact__c = :contactId AND Status__c = 'Active'
            ORDER BY Effective_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];
        return byContact.isEmpty() ? null : byContact[0];
    }

    /**
     * Three-tier contact resolution (reads only): explicit contactId, then the
     * messaging session's contact, then the newest Active session with a contact.
     * @param inp The action input.
     * @return The resolved Contact Id, or null.
     */
    private static Id resolveContactId(Input inp) {
        if (String.isNotBlank(inp.contactId)) {
            return (Id) inp.contactId;
        }
        if (String.isNotBlank(inp.messagingSessionId)) {
            List<MessagingSession> sessions = [
                SELECT EndUserContactId FROM MessagingSession
                WHERE Id = :inp.messagingSessionId LIMIT 1
            ];
            if (!sessions.isEmpty() && sessions[0].EndUserContactId != null) {
                return sessions[0].EndUserContactId;
            }
        }
        List<MessagingSession> active = [
            SELECT EndUserContactId FROM MessagingSession
            WHERE Status = 'Active' AND EndUserContactId != NULL
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return active.isEmpty() ? null : active[0].EndUserContactId;
    }

    /**
     * Formats a currency value for display, e.g. 4500 -> "$4,500".
     * @param value The amount.
     * @return The formatted string, or "—" when null.
     */
    private static String formatCurrency(Decimal value) {
        if (value == null) {
            return '—';
        }
        // Group with thousands separators; drop trailing cents when whole.
        Decimal rounded = value.setScale(2);
        String formatted = rounded.format();
        return '$' + formatted;
    }

    /**
     * @param value A string that may be blank.
     * @return The value, or "—" when blank.
     */
    private static String nullToDash(String value) {
        return String.isBlank(value) ? '—' : value;
    }
}