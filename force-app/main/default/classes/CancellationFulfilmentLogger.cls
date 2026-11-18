/**
 * Audit logging for cancellation BSS de-provisioning. Logging is best effort
 * and never masks a fulfilment failure.
 */
public with sharing class CancellationFulfilmentLogger {
    public static void success(
        List<CancellationFulfilmentItem> items,
        String correlationId,
        Integer durationMs
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (CancellationFulfilmentItem item : items) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = CancellationFulfilmentPolicy.OPERATION,
                    Status__c = 'Success',
                    Status_Code__c = CancellationFulfilmentPolicy.SUCCESS_CODE,
                    Duration_Ms__c = durationMs,
                    Endpoint__c = CancellationFulfilmentPolicy.ENDPOINT,
                    Subscription__c = item.subscription.Id,
                    Idempotency_Key__c = CancellationFulfilmentPolicy.idempotencyKey(
                        item.subscription,
                        item.request.Cancellation_Effective_Date__c
                    ),
                    Payload_Summary__c = 'Cancellation de-provisioned.',
                    Retry_Count__c = 0
                )
            );
        }
        insertLogs(logs);
    }

    public static void failure(
        List<CancellationFulfilmentItem> items,
        String correlationId,
        String message
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (CancellationFulfilmentItem item : items) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = CancellationFulfilmentPolicy.OPERATION,
                    Status__c = 'Failure',
                    Status_Code__c = CancellationFulfilmentPolicy.FAILURE_CODE,
                    Endpoint__c = CancellationFulfilmentPolicy.ENDPOINT,
                    Subscription__c = item.subscription.Id,
                    Idempotency_Key__c = CancellationFulfilmentPolicy.idempotencyKey(
                        item.subscription,
                        item.request.Cancellation_Effective_Date__c
                    ),
                    Error_Message__c = message.left(255),
                    Payload_Summary__c = 'Cancellation de-provisioning failed.',
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
            // Audit logging must not change the fulfilment outcome.
        }
    }
}
