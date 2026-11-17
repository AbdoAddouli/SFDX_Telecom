/**
 * Bulk write path for lifecycle intake. Four DML statements cover the whole
 * batch, including reciprocal Case linking and engagement fee stamping.
 */
public with sharing class LifecycleRequestWriter {
    public static void write(List<LifecycleRequestItem> items) {
        List<Case> cases = new List<Case>();
        for (LifecycleRequestItem item : items) {
            if (item.caseRecord != null) {
                cases.add(item.caseRecord);
            }
        }
        if (!cases.isEmpty()) {
            Database.insert(cases, true);
        }

        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        for (LifecycleRequestItem item : items) {
            item.request.Case__c =
                item.caseRecord == null ? null : item.caseRecord.Id;
            requests.add(item.request);
        }
        Database.insert(requests, true);

        List<Case> casesToLink = new List<Case>();
        List<Engagement__c> engagements = new List<Engagement__c>();
        for (LifecycleRequestItem item : items) {
            if (item.caseRecord != null) {
                item.caseRecord.Request_Link__c = item.request.Id;
                casesToLink.add(item.caseRecord);
            }
            if (item.engagement != null) {
                if (item.input.goodwillWaiver == true) {
                    item.engagement.Goodwill_Waiver__c = true;
                    item.engagement.Goodwill_Justification__c =
                        item.input.goodwillJustification;
                }
                engagements.add(item.engagement);
            }
        }
        if (!casesToLink.isEmpty()) {
            Database.update(casesToLink, true);
        }
        if (!engagements.isEmpty()) {
            Database.update(engagements, true);
        }
    }
}
