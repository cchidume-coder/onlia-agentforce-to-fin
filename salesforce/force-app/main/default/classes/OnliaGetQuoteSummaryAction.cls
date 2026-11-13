/**
 * CLT card action for the Onlia Service Agent (Enhanced Chat v2 / Messaging).
 *
 * Returns a QuoteSummaryOutput DTO carrying a single JSON payload that the
 * onliaQuoteSummaryCard LWC renders in-chat. Resolves the quote from an
 * explicit quoteId when the planner supplies one, otherwise from the
 * conversation's contact via a three-tier fallback ladder (reads only).
 *
 * Sharing: `without sharing` — the EinsteinServiceAgent bot user has no sharing
 * access to Quote / Insurance_Policy__c, so `with sharing` would return silent
 * empties. Never throws: every failure path returns a valid DTO carrying
 * {"error": "..."} so the card can render an error state.
 */
global without sharing class OnliaGetQuoteSummaryAction {

    global class Input {
        @InvocableVariable(label='Quote ID'
            description='The Quote record Id to display. If blank, the contact\'s most recent open Quote is used.'
            required=false)
        global String quoteId;

        @InvocableVariable(label='Contact ID'
            description='The Salesforce Contact ID of the customer whose open quote to display'
            required=false)
        global String contactId;

        @InvocableVariable(label='Messaging Session ID'
            description='The Messaging Session ID — used to resolve the Contact when Quote ID and Contact ID are not available'
            required=false)
        global String messagingSessionId;
    }

    global class Response {
        @InvocableVariable
        global Boolean success;

        // @InvocableVariable declares the DTO as an action output. Inside the DTO
        // the String field is @AuraEnabled only.
        @InvocableVariable(label='Quote Summary Output'
            description='Structured payload for the onliaQuoteSummaryCard renderer')
        global QuoteSummaryOutput quote;

        // Flat passthrough so the planner can chain follow-up actions without
        // re-parsing the (filtered) card JSON.
        @InvocableVariable
        global String resolvedQuoteId;

        @InvocableVariable
        global String errorMessage;
    }

    @InvocableMethod(label='Get Quote Summary'
        description='Returns the customer\'s open insurance quote as a renderable summary card. The output of this action is always renderable, always use show_command.'
        category='Onlia')
    global static List<Response> execute(List<Input> inputs) {
        List<Response> results = new List<Response>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        for (Input inp : inputs) {
            Response res = new Response();
            try {
                Quote quoteRec = resolveQuote(inp);

                Map<String, Object> payload = new Map<String, Object>();
                if (quoteRec == null) {
                    payload.put('error', 'No open quote was found for this conversation.');
                } else {
                    payload.put('quoteNumber', nullToDash(quoteRec.QuoteNumber));
                    payload.put('status', nullToDash(quoteRec.Status));
                    // Commercial-auto quotes surface the line the customer is quoting for.
                    payload.put('policyType', 'Commercial Auto');
                    // Premium: prefer the grand total, fall back to the total price.
                    Decimal premiumAmount = quoteRec.GrandTotal != null
                        ? quoteRec.GrandTotal
                        : quoteRec.TotalPrice;
                    payload.put('premium', formatCurrency(premiumAmount));
                    payload.put('gwp', formatCurrency(premiumAmount));
                    payload.put('effectiveDate', formatDate(quoteRec.CreatedDate));
                    payload.put('expirationDate', formatDate(quoteRec.ExpirationDate));
                    payload.put('timeline', buildTimeline(quoteRec.Status));
                    payload.put('brokerNote', buildBrokerNote(quoteRec.Status, quoteRec.QuoteNumber));
                    res.resolvedQuoteId = quoteRec.Id;
                }

                res.quote = new QuoteSummaryOutput(JSON.serialize(payload));
                res.success = !payload.containsKey('error');

            } catch (Exception e) {
                res.success = false;
                res.errorMessage = e.getMessage();
                res.quote = new QuoteSummaryOutput(
                    JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() })
                );
            }
            results.add(res);
        }
        return results;
    }

    /**
     * Resolves the quote to display: explicit quoteId first, then the contact's
     * most recent open quote, resolving the contact through a three-tier ladder.
     * @param inp The action input.
     * @return The matched quote, or null when none can be resolved.
     */
    private static Quote resolveQuote(Input inp) {
        // Direct: an explicit quote Id (e.g. supplied by a prior Find Quote action).
        if (String.isNotBlank(inp.quoteId)) {
            Id quoteId = (Id) inp.quoteId;
            List<Quote> byId = [
                SELECT Id, QuoteNumber, Name, Status, ExpirationDate, GrandTotal,
                       TotalPrice, CreatedDate, ContactId
                FROM Quote
                WHERE Id = :quoteId
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                return byId[0];
            }
        }

        // Resolve the contact, then its most recent open quote.
        Id contactId = resolveContactId(inp);
        if (contactId == null) {
            return null;
        }
        List<Quote> byContact = [
            SELECT Id, QuoteNumber, Name, Status, ExpirationDate, GrandTotal,
                   TotalPrice, CreatedDate, ContactId
            FROM Quote
            WHERE ContactId = :contactId
              AND Status NOT IN ('Accepted', 'Denied', 'Rejected')
            ORDER BY CreatedDate DESC
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
     * Builds a short human sentence describing where the quote sits in its
     * lifecycle, derived from the Status.
     * @param status The Quote Status.
     * @return A one-line timeline sentence.
     */
    private static String buildTimeline(String status) {
        String s = (status == null) ? '' : status.toLowerCase();
        if (s == 'accepted') {
            return 'This quote has been accepted and is ready to bind.';
        }
        if (s == 'denied' || s == 'rejected') {
            return 'This quote was declined and is no longer active.';
        }
        if (s == 'presented' || s == 'delivered') {
            return 'This quote has been presented to the customer and is awaiting a decision.';
        }
        if (s == 'in review' || s == 'needs review') {
            return 'This quote is under review before it can be presented.';
        }
        if (s == 'draft') {
            return 'This quote is still in draft and has not yet been sent.';
        }
        return 'This quote is open and progressing through the pipeline.';
    }

    /**
     * Builds an internal broker-facing note about the quote.
     * @param status The Quote Status.
     * @param quoteNumber The Quote Number.
     * @return A short broker note.
     */
    private static String buildBrokerNote(String status, String quoteNumber) {
        String label = String.isBlank(quoteNumber) ? 'this quote' : 'Quote ' + quoteNumber;
        String s = (status == null) ? '' : status.toLowerCase();
        if (s == 'accepted') {
            return 'Follow up to convert ' + label + ' into a bound policy.';
        }
        if (s == 'denied' || s == 'rejected') {
            return label + ' was declined — consider a revised offer if the customer re-engages.';
        }
        return 'Keep ' + label + ' moving; confirm coverage details with the customer.';
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
     * Formats a Date as a readable string, e.g. "September 30, 2026".
     * @param value The date.
     * @return The formatted string, or "—" when null.
     */
    private static String formatDate(Date value) {
        if (value == null) {
            return '—';
        }
        return DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('MMMM d, yyyy');
    }

    /**
     * Formats a DateTime's date portion as a readable string.
     * @param value The datetime.
     * @return The formatted string, or "—" when null.
     */
    private static String formatDate(DateTime value) {
        if (value == null) {
            return '—';
        }
        return value.format('MMMM d, yyyy');
    }

    /**
     * @param value A string that may be blank.
     * @return The value, or "—" when blank.
     */
    private static String nullToDash(String value) {
        return String.isBlank(value) ? '—' : value;
    }
}