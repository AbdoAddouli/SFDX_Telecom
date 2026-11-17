/**
 * Bulk-only query boundary for plan changes. Callers pass Id sets; this class
 * performs at most one SOQL statement per object per transaction.
 */
public with sharing class PlanChangeRepository {
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
                    Requested_Product__c,
                    Subscription__c,
                    Impacted_Engagement__c,
                    Fee_Breakdown__c,
                    Resolution_Summary__c
                FROM Customer_Request__c
                WHERE Id IN :requestIds
                AND Request_Type__c = :PlanChangePolicy.REQUEST_TYPE
            ]
        );
    }

    public static Map<Id, Subscription__c> subscriptions(Set<Id> subscriptionIds) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return new Map<Id, Subscription__c>();
        }
        return new Map<Id, Subscription__c>(
            [
                SELECT
                    Id,
                    Account__c,
                    Asset__c,
                    Contact__c,
                    Contract__c,
                    Engagement__c,
                    Root_Engagement__c,
                    Status__c,
                    Service_Line_Type__c,
                    Product__c,
                    Monthly_Amount__c,
                    Is_Committed__c,
                    Billing_Start_Date__c,
                    Billing_End_Date__c,
                    Display_Name__c
                FROM Subscription__c
                WHERE Id IN :subscriptionIds
            ]
        );
    }

    public static Map<Id, Engagement__c> engagements(Set<Id> engagementIds) {
        if (engagementIds == null || engagementIds.isEmpty()) {
            return new Map<Id, Engagement__c>();
        }
        return new Map<Id, Engagement__c>(
            [
                SELECT
                    Id,
                    Status__c,
                    Start_Date__c,
                    End_Date__c,
                    Duration_Months__c,
                    Monthly_Amount__c,
                    Root_Engagement__c
                FROM Engagement__c
                WHERE Id IN :engagementIds
            ]
        );
    }

    public static Map<Id, Account> accounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(
            [
                SELECT Id, Segment__c, BillingPostalCode
                FROM Account
                WHERE Id IN :accountIds
            ]
        );
    }

    public static Map<Id, Product2> products(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new Map<Id, Product2>();
        }
        return new Map<Id, Product2>(
            [
                SELECT Id, Name, Family, IsActive, ATS_Product_Code__c
                FROM Product2
                WHERE Id IN :productIds
            ]
        );
    }
}
