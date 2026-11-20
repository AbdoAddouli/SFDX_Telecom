/**
 * Bulk-only query boundary for renewal decisions. Fixed SOQL count per batch.
 */
public with sharing class RenewalRepository {
    public static Map<Id, Subscription__c> subscriptions(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Subscription__c>();
        }
        return new Map<Id, Subscription__c>(
            [
                SELECT
                    Id,
                    Name,
                    Account__c,
                    Contact__c,
                    Asset__c,
                    Contract__c,
                    Engagement__c,
                    Root_Engagement__c,
                    Service_Line_Type__c,
                    Product__c,
                    Status__c,
                    Monthly_Amount__c,
                    Billing_Start_Date__c,
                    Billing_End_Date__c,
                    Is_Committed__c
                FROM Subscription__c
                WHERE Id IN :ids
            ]
        );
    }

    public static Map<Id, Engagement__c> engagements(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Engagement__c>();
        }
        return new Map<Id, Engagement__c>(
            [
                SELECT
                    Id,
                    Account__c,
                    Subscription__c,
                    Contract__c,
                    Asset__c,
                    Root_Engagement__c,
                    Status__c,
                    Start_Date__c,
                    End_Date__c,
                    Duration_Months__c,
                    Monthly_Amount__c,
                    Renewal_Contacted__c
                FROM Engagement__c
                WHERE Id IN :ids
            ]
        );
    }

    public static Map<Id, Account> accounts(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(
            [
                SELECT Id, Name, Segment__c, BillingPostalCode
                FROM Account
                WHERE Id IN :ids
            ]
        );
    }

    public static Map<Id, Product2> products(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Product2>();
        }
        return new Map<Id, Product2>(
            [
                SELECT Id, Name, Family, IsActive, ATS_Product_Code__c
                FROM Product2
                WHERE Id IN :ids
            ]
        );
    }

    public static Map<Id, Contract> contracts(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new Map<Id, Contract>();
        }
        return new Map<Id, Contract>(
            [SELECT Id, Auto_Renew__c FROM Contract WHERE Id IN :ids]
        );
    }

    public static Map<Id, Customer_Request__c> requests(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
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
                    Requested_Product__c,
                    Fee_Breakdown__c,
                    Resolution_Summary__c
                FROM Customer_Request__c
                WHERE Id IN :ids
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
            AND Request_Type__c = :RenewalPolicy.REQUEST_TYPE
            AND Status__c IN :RenewalPolicy.IN_FLIGHT_STATUSES
        ]) {
            if (!bySubscription.containsKey(request.Subscription__c)) {
                bySubscription.put(request.Subscription__c, request);
            }
        }
        return bySubscription;
    }
}
