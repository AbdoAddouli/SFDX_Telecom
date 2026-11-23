/** Scheduled entry point for the cached product image refresh. */
public with sharing class ProductImageSyncScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        Database.executeBatch(new ProductImageSyncBatch(), 200);
    }
}
