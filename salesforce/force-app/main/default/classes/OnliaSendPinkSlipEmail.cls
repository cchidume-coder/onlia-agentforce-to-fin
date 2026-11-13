/**
 * Agentforce/Flow helper: emails the customer's pink-slip (proof of insurance) document.
 * A pure Flow cannot attach a ContentVersion binary to an email, so the Onlia_Send_Pink_Slip_Email
 * flow calls this small invocable to build and send the message with the policy's PDF attached.
 * The physical-mail path is a native flow (Onlia_Send_Pink_Slip_Mail) with no Apex.
 */
public with sharing class OnliaSendPinkSlipEmail {
    /**
     * @param requests One request per policy/contact pair to email.
     * @return One response per request with a confirmation message.
     */
    @InvocableMethod(label='Send Pink Slip Email' description='Emails the policy document (pink slip) to the confirmed email address.' category='Onlia')
    public static List<Response> sendPinkSlipEmail(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> policyIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isNotBlank(req.policyId)) {
                policyIds.add((Id) req.policyId);
            }
            if (String.isNotBlank(req.contactId)) {
                contactIds.add((Id) req.contactId);
            }
        }

        Map<Id, Insurance_Policy__c> policyById = new Map<Id, Insurance_Policy__c>(
            [
                SELECT Id, Name, Policy_Number__c
                FROM Insurance_Policy__c
                WHERE Id IN :policyIds
                WITH USER_MODE
            ]
        );
        Map<Id, Contact> contactById = new Map<Id, Contact>(
            [SELECT Id, Name, Email FROM Contact WHERE Id IN :contactIds WITH USER_MODE]
        );
        Map<Id, ContentVersion> versionByPolicy = getLatestVersionByPolicy(policyIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Response> emailResponses = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();
            try {
                Insurance_Policy__c policy = String.isBlank(req.policyId)
                    ? null
                    : policyById.get((Id) req.policyId);
                if (policy == null) {
                    res.isSuccess = false;
                    res.errorMessage = 'Policy not found.';
                    responses.add(res);
                    continue;
                }

                Contact contact = String.isBlank(req.contactId)
                    ? null
                    : contactById.get((Id) req.contactId);

                String emailTo = String.isNotBlank(req.confirmedEmail)
                    ? req.confirmedEmail
                    : (contact != null ? contact.Email : null);
                if (String.isBlank(emailTo)) {
                    res.isSuccess = false;
                    res.errorMessage = 'No email address was confirmed or on file. Ask the customer for the email to send to.';
                    responses.add(res);
                    continue;
                }

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ emailTo });
                email.setSubject('Your Onlia proof of insurance (Policy ' + policy.Policy_Number__c + ')');
                email.setPlainTextBody(
                    'Hi ' + (contact != null ? contact.Name : 'there') + ',\n\n' +
                    'Attached is the proof of insurance (pink slip) for policy ' +
                    policy.Policy_Number__c + '.' +
                    '\n\nThank you,\nOnlia'
                );
                email.setSaveAsActivity(false);
                ContentVersion version = versionByPolicy.get(policy.Id);
                if (version != null) {
                    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                    attachment.setFileName(version.Title + '.pdf');
                    attachment.setBody(version.VersionData);
                    email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
                }
                emails.add(email);
                emailResponses.add(res);

                res.isSuccess = true;
                res.confirmationMessage = 'Done — I emailed your pink slip to ' + emailTo + '.';
            } catch (Exception e) {
                res.isSuccess = false;
                res.errorMessage = e.getMessage();
                res.errorType = e.getTypeName();
            }
            responses.add(res);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
        return responses;
    }

    private static Map<Id, ContentVersion> getLatestVersionByPolicy(Set<Id> policyIds) {
        Map<Id, ContentVersion> versionByPolicy = new Map<Id, ContentVersion>();
        if (policyIds == null || policyIds.isEmpty()) {
            return versionByPolicy;
        }
        Map<Id, Id> docIdByPolicy = new Map<Id, Id>();
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :policyIds
        ]) {
            if (!docIdByPolicy.containsKey(link.LinkedEntityId)) {
                docIdByPolicy.put(link.LinkedEntityId, link.ContentDocumentId);
                docIds.add(link.ContentDocumentId);
            }
        }
        for (ContentVersion version : [
            SELECT Id, Title, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
        ]) {
            for (Id policyId : docIdByPolicy.keySet()) {
                if (docIdByPolicy.get(policyId) == version.ContentDocumentId) {
                    versionByPolicy.put(policyId, version);
                }
            }
        }
        return versionByPolicy;
    }

    public class Request {
        @InvocableVariable(label='Policy Id' description='Id of the insurance policy.' required=true)
        public String policyId;
        @InvocableVariable(label='Contact Id' description='Id of the contact to email.' required=true)
        public String contactId;
        @InvocableVariable(label='Confirmed Email' description='The email address the customer confirmed. Defaults to the email on the contact when blank.' required=false)
        public String confirmedEmail;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean isSuccess = false;
        @InvocableVariable(label='Confirmation Message')
        public String confirmationMessage;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        @InvocableVariable(label='Error Type')
        public String errorType;
    }
}