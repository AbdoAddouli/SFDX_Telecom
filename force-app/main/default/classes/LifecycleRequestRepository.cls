/**
 * Bulk-only query boundary for lifecycle intake. One SOQL statement per object
 * covers the entire batch.
 */
public with sharing class LifecycleRequestRepository {
    public class Data {
        public Map<Id, Subscription__c> subscriptions =
            new Map<Id, Subscription__c>();
        public Map<Id, Account> accounts = new Map<Id, Account>();
        public Map<Id, Engagement__c> engagements =
            new Map<Id, Engagement__c>();
    }

    public static Data load(List<LifecycleRequestService.RequestInput> inputs) {
        Data data = new Data();
        if (inputs == null || inputs.isEmpty()) {
            return data;
        }

        Set<Id> subscriptionIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (LifecycleRequestService.RequestInput input : inputs) {
            if (input == null) {
                continue;
            }
            if (input.subscriptionId != null) {
                subscriptionIds.add(input.subscriptionId);
            }
            if (input.accountId != null) {
                accountIds.add(input.accountId);
            }
        }
        if (!subscriptionIds.isEmpty()) {
            data.subscriptions.putAll(
                [
                    SELECT
                        Id,
                        Account__c,
                        Engagement__c,
                        Service_Line_Type__c
                    FROM Subscription__c
                    WHERE Id IN :subscriptionIds
                ]
            );
            for (Subscription__c subscription : data.subscriptions.values()) {
                if (subscription.Account__c != null) {
                    accountIds.add(subscription.Account__c);
                }
            }
        }
        if (!accountIds.isEmpty()) {
            data.accounts.putAll(
                [SELECT Id, Name, Segment__c FROM Account WHERE Id IN :accountIds]
            );
        }

        Set<Id> engagementIds = new Set<Id>();
        for (Subscription__c subscription : data.subscriptions.values()) {
            if (subscription.Engagement__c != null) {
                engagementIds.add(subscription.Engagement__c);
            }
        }
        if (!engagementIds.isEmpty()) {
            data.engagements.putAll(
                [
                    SELECT
                        Id,
                        Start_Date__c,
                        End_Date__c,
                        Duration_Months__c,
                        Monthly_Amount__c,
                        Status__c
                    FROM Engagement__c
                    WHERE Id IN :engagementIds
                ]
            );
        }
        return data;
    }
}
