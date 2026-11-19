/**
 * Best-effort audit logging for suspension BSS state changes.
 */
public with sharing class SuspensionLogger {
    public static void success(
        List<SuspensionContext> items,
        String correlationId,
        Integer durationMs
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (SuspensionContext item : items) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = SuspensionPolicy.operation(item.action),
                    Status__c = 'Success',
                    Status_Code__c = SuspensionPolicy.SUCCESS_CODE,
                    Duration_Ms__c = durationMs,
                    Endpoint__c = SuspensionPolicy.endpoint(item.action),
                    Subscription__c = item.subscription.Id,
                    Idempotency_Key__c = SuspensionPolicy.idempotencyKey(
                        item.subscription,
                        item.action,
                        item.request.Id
                    ),
                    Payload_Summary__c = item.action + ' applied.',
                    Retry_Count__c = 0
                )
            );
        }
        insertLogs(logs);
    }

    public static void failure(
        List<SuspensionContext> items,
        String correlationId,
        String message
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (SuspensionContext item : items) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = SuspensionPolicy.operation(item.action),
                    Status__c = 'Failure',
                    Status_Code__c = SuspensionPolicy.FAILURE_CODE,
                    Endpoint__c = SuspensionPolicy.endpoint(item.action),
                    Subscription__c = item.subscription.Id,
                    Idempotency_Key__c = SuspensionPolicy.idempotencyKey(
                        item.subscription,
                        item.action,
                        item.request.Id
                    ),
                    Error_Message__c = message.left(255),
                    Payload_Summary__c = item.action + ' failed.',
                    Retry_Count__c = 0
                )
            );
        }
        insertLogs(logs);
    }

    private static void insertLogs(List<Integration_Log__c> logs) {
        if (logs.isEmpty()) {
            return;
        }
        try {
            Database.insert(logs, false);
        } catch (Exception ignored) {
            // Audit logging must not change the suspension outcome.
        }
    }
}
