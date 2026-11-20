/**
 * Daily batch that creates renewal outreach tasks at T-60, T-30 and T-7.
 * Scheduled daily at 03:00 as 'ATS Renewal Outreach (Daily)'.
 */
global without sharing class RenewalOutreachBatch
    implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 200;

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    OwnerId,
                    Status__c,
                    Renewal_Contacted__c,
                    Subscription__r.Next_Renewal_Date__c,
                    Subscription__r.Status__c,
                    Subscription__r.Contact__c,
                    Subscription__r.Contact__r.Do_Not_Call__c
                FROM Engagement__c
                WHERE Status__c = :RenewalPolicy.ENGAGEMENT_ACTIVE
                AND Subscription__r.Status__c = :RenewalPolicy.SUBSCRIPTION_ACTIVE
                AND Subscription__r.Next_Renewal_Date__c >= :Date.today()
                AND Subscription__r.Next_Renewal_Date__c <= :Date.today().addDays(60)
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
        List<Engagement__c> engagements = new List<Engagement__c>();
        for (SObject record : scope) {
            engagements.add((Engagement__c) record);
        }
        RenewalOutreachService.apply(engagements);
    }

    global void finish(Database.BatchableContext bc) {
        // Stage-specific tasks and engagement guards are written by the service.
    }

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new RenewalOutreachBatch(), BATCH_SIZE);
    }
}
