/**
 * Best-effort audit logging for portability BSS calls and donor outcomes.
 * Logging never changes the UC-LIF-07 result.
 */
public with sharing class PortabilityLogger {
    public static void success(
        List<PortabilityContext> contexts,
        String operation,
        Integer durationMs
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (PortabilityContext context : contexts) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = context.correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = operation,
                    Status__c = 'Success',
                    Status_Code__c = PortabilityPolicy.SUCCESS_CODE,
                    Duration_Ms__c = durationMs,
                    Endpoint__c = PortabilityPolicy.endpoint(operation),
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
        List<PortabilityContext> contexts,
        String operation,
        String message,
        String statusCode
    ) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (PortabilityContext context : contexts) {
            logs.add(
                new Integration_Log__c(
                    Correlation_Id__c = context.correlationId,
                    Direction__c = 'Outbound',
                    System__c = 'BSS',
                    Operation__c = operation,
                    Status__c = 'Failure',
                    Status_Code__c = statusCode,
                    Endpoint__c = PortabilityPolicy.endpoint(operation),
                    Subscription__c = context.subscription.Id,
                    Idempotency_Key__c = idempotencyKey(context),
                    Error_Message__c = String.isBlank(message)
                        ? 'Portability operation failed.'
                        : message.left(255),
                    Payload_Summary__c = payloadSummary(context),
                    Retry_Count__c = 0
                )
            );
        }
        insertLogs(logs);
    }

    private static String idempotencyKey(PortabilityContext context) {
        return String.isBlank(context.subscription.Name)
            ? 'PORT-' + context.subscription.Id
            : context.subscription.Name;
    }

    private static String payloadSummary(PortabilityContext context) {
        String summary = context.direction + ' port';
        if (String.isNotBlank(context.requestReference)) {
            summary += ' request=' + context.requestReference;
        }
        if (String.isNotBlank(context.confirmationReference)) {
            summary += ' confirmation=' + context.confirmationReference;
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
            // Audit logging must not change the portability outcome.
        }
    }
}
