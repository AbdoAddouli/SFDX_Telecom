/**
 * Bulk-only query boundary for UC-LIF-07. Fixed SOQL count per batch.
 */
public with sharing class PortabilityRepository {
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
                    Contact__c,
                    Status__c,
                    MSISDN__c,
                    Service_Line_Type__c,
                    Engagement__c,
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
            SELECT Id, Subscription__c, Status__c
            FROM Customer_Request__c
            WHERE
                Subscription__c IN :subscriptionIds AND
                Request_Type__c = :PortabilityPolicy.REQUEST_TYPE AND
                Status__c IN :PortabilityPolicy.IN_FLIGHT_STATUSES
        ]) {
            bySubscription.put(request.Subscription__c, request);
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
                    Requested_MSISDN__c,
                    Port_Direction__c,
                    Previous_MSISDN__c,
                    Port_Request_Reference__c,
                    Port_Confirmation_Reference__c,
                    Rejection_Reason__c,
                    Resolution_Summary__c,
                    Calculated_Fee__c
                FROM Customer_Request__c
                WHERE Id IN :requestIds
            ]
        );
    }

    public static Map<String, Id> msisdnOwners(Set<String> msisdns) {
        Map<String, Id> owners = new Map<String, Id>();
        Set<String> values = new Set<String>();
        if (msisdns != null) {
            for (String msisdn : msisdns) {
                if (String.isNotBlank(msisdn)) {
                    values.add(msisdn);
                }
            }
        }
        if (values.isEmpty()) {
            return owners;
        }
        for (Subscription__c subscription : [
            SELECT Id, MSISDN__c
            FROM Subscription__c
            WHERE MSISDN__c IN :values
        ]) {
            owners.put(subscription.MSISDN__c, subscription.Id);
        }
        return owners;
    }
}
