/**
 * Daily batch that fulfils cancellations on their effective date.
 * Scheduled daily at 01:00 as 'ATS Cancellation Fulfilment (Daily)'.
 */
global without sharing class CancellationFulfilmentBatch
    implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 200;

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Account__c,
                    Account__r.Name,
                    Case__c,
                    Subscription__c,
                    Cancellation_Effective_Date__c,
                    Calculated_Fee__c,
                    Status__c,
                    Subscription__r.Name,
                    Subscription__r.Status__c,
                    Subscription__r.Account__c,
                    Subscription__r.Asset__c,
                    Subscription__r.Contract__c,
                    Subscription__r.Engagement__c,
                    Subscription__r.Service_Line_Type__c,
                    Subscription__r.Product__r.ATS_Product_Code__c
                FROM Customer_Request__c
                WHERE
                    Request_Type__c = :CancellationPolicy.REQUEST_TYPE
                    AND Status__c = :CancellationPolicy.STATUS_IN_FULFILMENT
                    AND Cancellation_Effective_Date__c <= :Date.today()
            ]
        );
    }

    global void execute(
        Database.BatchableContext bc,
        List<SObject> scope
    ) {
        if (scope.isEmpty()) {
            return;
        }
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        for (SObject record : scope) {
            requests.add((Customer_Request__c) record);
        }
        CancellationFulfilmentService.fulfil(requests);
    }

    global void finish(Database.BatchableContext bc) {
        // Per-request audit rows are written by the service; nothing to do.
    }

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new CancellationFulfilmentBatch(), BATCH_SIZE);
    }
}
