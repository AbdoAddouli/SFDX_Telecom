/**
 * Bulk-only query boundary for suspension requests. Fixed SOQL count per batch.
 */
public with sharing class SuspensionRepository {
    public static Map<Id, Subscription__c> subscriptions(
        Set<Id> subscriptionIds
    ) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return new Map<Id, Subscription__c>();
        }
        return new Map<Id, Subscription__c>(
            [
                SELECT
                    Id,
                    Name,
                    Account__c,
                    Status__c,
                    External_Status__c,
                    Service_Line_Type__c,
                    Product__r.ATS_Product_Code__c
                FROM Subscription__c
                WHERE Id IN :subscriptionIds
            ]
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
            AND Request_Type__c IN :SuspensionPolicy.REQUEST_TYPES
            AND Status__c IN :SuspensionPolicy.IN_FLIGHT_STATUSES
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
                    Account__c,
                    Case__c,
                    Status__c,
                    Subscription__c,
                    Request_Type__c,
                    Customer_Comment__c,
                    Calculated_Fee__c,
                    Resolution_Summary__c
                FROM Customer_Request__c
                WHERE Id IN :requestIds
            ]
        );
    }
}
