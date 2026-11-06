/**
 * @description Weekly hard-delete of Integration_Log__c rows older than
 * 13 months. The object is the highest-volume custom object; soft deletion
 * would let the table grow without bound (DATA_MODEL.md §14.1).
 *
 * Implements Schedulable so the job can be activated with System.schedule.
 */
global without sharing class IntegrationLogCleanupBatch
    implements Database.Batchable<SObject>, Schedulable {

    private static final Integer BATCH_SIZE = 2000;

    global Database.QueryLocator start(Database.BatchableContext bc) {
        DateTime cutoff = DateTime.now().addMonths(-13);
        return Database.getQueryLocator(
            'SELECT Id FROM Integration_Log__c WHERE CreatedDate < :cutoff'
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
        Database.executeBatch(new IntegrationLogCleanupBatch(), BATCH_SIZE);
    }
}
