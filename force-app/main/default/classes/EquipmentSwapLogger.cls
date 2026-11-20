/** Best-effort audit logging for device-swap BSS calls. */
public with sharing class EquipmentSwapLogger {
    public static void success(
        List<EquipmentSwapContext> contexts,
        Integer durationMs
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (EquipmentSwapContext context : contexts) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = context.correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = EquipmentSwapPolicy.OPERATION_SWAP,
                    Status__c = 'Success',
                    Status_Code__c = EquipmentSwapPolicy.SUCCESS_CODE,
                    Duration_Ms__c = durationMs,
                    Endpoint__c = EquipmentSwapPolicy.ENDPOINT,
                    Subscription__c = context.subscription.Id,
                    Idempotency_Key__c = idempotencyKey(context),
                    Payload_Summary__c = payloadSummary(context),
                    Retry_Count__c = 0
                )
            );
        }
        insertLogs(logs);
    }

    public static void failure(
        List<EquipmentSwapContext> contexts,
        String message,
        String statusCode
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (EquipmentSwapContext context : contexts) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = context.correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = EquipmentSwapPolicy.OPERATION_SWAP,
                    Status__c = 'Failure',
                    Status_Code__c = statusCode,
                    Endpoint__c = EquipmentSwapPolicy.ENDPOINT,
                    Subscription__c = context.subscription.Id,
                    Idempotency_Key__c = idempotencyKey(context),
                    Error_Message__c = String.isBlank(message)
                        ? 'Device swap failed.'
                        : message.left(255),
                    Payload_Summary__c = payloadSummary(context),
                    Retry_Count__c = 0
                )
            );
        }
        insertLogs(logs);
    }

    private static String idempotencyKey(EquipmentSwapContext context) {
        return EquipmentSwapPolicy.idempotencyKey(context.subscription.Name);
    }

    private static String payloadSummary(EquipmentSwapContext context) {
        String summary = 'Device swap';
        if (context.device != null) {
            summary += ' product=' + context.device.productCode;
        }
        if (String.isNotBlank(context.serialNumber)) {
            summary += ' serial=' + context.serialNumber;
        }
        return summary.left(255);
    }

    private static void insertLogs(List<Integration_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        try {
            Database.insert(logs, false);
        } catch (Exception ignored) {
            // Audit logging must not change the swap outcome.
        }
    }
}
