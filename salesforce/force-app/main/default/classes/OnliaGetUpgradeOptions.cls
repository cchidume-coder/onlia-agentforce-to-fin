/**
 * CLT card action for the Onlia Service Agent (Enhanced Chat v2 / Messaging).
 *
 * Returns an UpgradeOptionsOutput DTO carrying a single JSON payload that the
 * onliaUpgradeOptionsCard LWC renders in-chat as three branded, clickable options
 * for connecting the customer to a licensed human broker (Call Now / Transfer Now /
 * Schedule a Callback). The options are static — the card is purely a presentation
 * surface, and each button writes its `sendText` back into the conversation so the
 * agent can route to the matching action (call_now / transfer_now / schedule_callback).
 *
 * Never throws: any failure returns a valid DTO carrying {"error": "..."} so the
 * card can render an error state instead of breaking the conversation.
 */
global without sharing class OnliaGetUpgradeOptions {

    global class Input {
        // No inputs required — the options are static. Declared for a stable schema.
        @InvocableVariable(label='Contact ID'
            description='The customer\'s Contact Id. Optional; not used to build the options.'
            required=false)
        global String contactId;
    }

    global class Response {
        @InvocableVariable
        global Boolean success;

        // @InvocableVariable declares the DTO as an action output. Inside the DTO
        // the String field is @AuraEnabled only.
        @InvocableVariable(label='Upgrade Options Output'
            description='Structured payload for the onliaUpgradeOptionsCard renderer')
        global UpgradeOptionsOutput options;

        @InvocableVariable
        global String errorMessage;
    }

    @InvocableMethod(label='Get Upgrade Options'
        description='Returns the three broker-handoff options as a renderable card of clickable buttons. The output of this action is always renderable, always use show_command. Do NOT convert it to text.'
        category='Onlia')
    global static List<Response> execute(List<Input> inputs) {
        List<Response> results = new List<Response>();
        // At least one Response so the planner always has something to render.
        Integer iterations = (inputs == null || inputs.isEmpty()) ? 1 : inputs.size();

        for (Integer i = 0; i < iterations; i++) {
            Response res = new Response();
            try {
                res.options = new UpgradeOptionsOutput(JSON.serialize(buildPayload()));
                res.success = true;
            } catch (Exception e) {
                res.success = false;
                res.errorMessage = e.getMessage();
                res.options = new UpgradeOptionsOutput(
                    JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() })
                );
            }
            results.add(res);
        }
        return results;
    }

    /**
     * Builds the static options payload the card renders. Each option carries the
     * `sendText` phrase the LWC writes back into the chat when its button is clicked,
     * matching the phrasing the coverage_upgrade subagent routes on.
     * @return A map with a `heading`, an `intro`, and an `options` list.
     */
    private static Map<String, Object> buildPayload() {
        List<Map<String, Object>> options = new List<Map<String, Object>>{
            new Map<String, Object>{
                'key' => 'call_now',
                'title' => 'Call Now',
                'description' => 'We call your phone right now and connect you to a licensed broker.',
                'sendText' => 'Call Now'
            },
            new Map<String, Object>{
                'key' => 'transfer_now',
                'title' => 'Transfer Now',
                'description' => 'I hand this chat straight to a broker with a summary, so you don\'t repeat yourself.',
                'sendText' => 'Transfer Now'
            },
            new Map<String, Object>{
                'key' => 'schedule_callback',
                'title' => 'Schedule a Callback',
                'description' => 'A licensed broker calls you back on your phone a little later.',
                'sendText' => 'Schedule a Callback'
            }
        };
        return new Map<String, Object>{
            'heading' => 'Connect with a licensed broker',
            'intro' => 'A licensed Onlia broker can help with coverage changes and pricing. Pick how you\'d like to connect:',
            'options' => options
        };
    }
}