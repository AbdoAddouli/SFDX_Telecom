/**
 * @description Nightly hard-delete of abandoned Subscription_Wizard_State__c
 * rows. A state expires seven days after its last activity. If Expires_On__c
 * is blank, Last_Activity_On__c is used as a fallback so old rows are still
 * purged (DATA_MODEL.md §14.2).
 *
 * Implements Schedulable so the job can be activated with System.schedule.
 */
global without sharing class WizardStateCleanupBatch
    implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 2000;

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        DateTime fallbackCutoff = DateTime.now().addDays(-7);
        return Database.getQueryLocator(
            'SELECT Id FROM Subscription_Wizard_State__c ' +
            'WHERE Expires_On__c < :today ' +
            'OR (Expires_On__c = null AND Last_Activity_On__c < :fallbackCutoff)'
        );
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }
        Database.delete(scope, false);
    }

    global void finish(Database.BatchableContext bc) {
        // Nothing to do.
    }

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new WizardStateCleanupBatch(), BATCH_SIZE);
    }
}
