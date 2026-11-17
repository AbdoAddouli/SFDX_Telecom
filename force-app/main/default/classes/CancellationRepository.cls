/**
 * Bulk-only query boundary for cancellation records. All callers pass Id sets
 * so this class performs a fixed number of SOQL queries per transaction.
 */
public with sharing class CancellationRepository {
    public static Map<Id, Subscription__c> subscriptions(Set<Id> subscriptionIds) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return new Map<Id, Subscription__c>();
        }
        return new Map<Id, Subscription__c>(
            [SELECT Id, Status__c FROM Subscription__c WHERE Id IN :subscriptionIds]
        );
    }

    public static Map<Id, Customer_Request__c> inFlightBySubscription(
        Set<Id> subscriptionIds
    ) {
        Map<Id, Customer_Request__c> bySubscription =
            new Map<Id, Customer_Request__c>();
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return bySubscription;
        }
        for (Customer_Request__c request : [
            SELECT Id, Subscription__c
            FROM Customer_Request__c
            WHERE Subscription__c IN :subscriptionIds
            AND Request_Type__c = :CancellationPolicy.REQUEST_TYPE
            AND Status__c IN :CancellationPolicy.IN_FLIGHT_STATUSES
        ]) {
            if (!bySubscription.containsKey(request.Subscription__c)) {
                bySubscription.put(request.Subscription__c, request);
            }
        }
        return bySubscription;
    }

    public static Map<Id, Customer_Request__c> requests(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Customer_Request__c>();
        }
        return new Map<Id, Customer_Request__c>(
            [
                SELECT
                    Id,
                    Case__c,
                    Status__c,
                    Subscription__c,
                    Cancellation_Effective_Date__c,
                    Calculated_Fee__c,
                    Due_Date__c,
                    Resolution_Summary__c
                FROM Customer_Request__c
                WHERE Id IN :requestIds
            ]
        );
    }
}
