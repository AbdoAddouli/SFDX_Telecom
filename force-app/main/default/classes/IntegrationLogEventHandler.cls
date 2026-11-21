/**
 * Bulk event subscriber that materialises rollback-safe audit events as
 * Integration_Log__c rows. Inserts are best-effort so a bad log can never
 * fail the event delivery.
 */
public without sharing class IntegrationLogEventHandler {
    public static void handle(List<Integration_Log_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<Integration_Log__c> records = new List<Integration_Log__c>();
        for (Integration_Log_Event__e event : events) {
            records.add(IntegrationLogService.fromEvent(event));
        }
        Database.insert(records, false);
    }
}
