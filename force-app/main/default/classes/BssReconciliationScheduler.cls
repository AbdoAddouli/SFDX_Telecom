/** Schedulable entry point for the nightly BSS reconciliation batch. */
public with sharing class BssReconciliationScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        Database.executeBatch(new BssReconciliationBatch(), 200);
    }
}
