/**
 * Single normalisation path for integration audit rows.
 *
 * publish() emits a Publish Immediately platform event so an audit row survives
 * a business rollback. The event handler performs the best-effort insert.
 * Field values are normalised and truncated before they reach the event.
 */
public without sharing class IntegrationLogService {
    private static final Set<String> STATUSES = new Set<String>{
        'Success', 'Failure', 'Retried', 'DeadLetter'
    };
    private static final Set<String> SYSTEMS = new Set<String>{
        'BSS', 'OSS', 'ProductImage', 'Weather', 'Other'
    };

    public class LogInput {
        public String correlationId;
        public String idempotencyKey;
        public String systemName;
        public String operation;
        public String endpoint;
        public String status;
        public String statusCode;
        public Decimal durationMs;
        public String payloadSummary;
        public String errorMessage;
        public String errorStack;
        public Id subscriptionId;
        public Id orderId;
        public Integer retryCount;
        public Boolean inbound;
    }

    /** Builds a normalised log row without DML. Exposed for deterministic tests. */
    public static Integration_Log__c build(LogInput input) {
        LogInput source = input == null ? new LogInput() : input;

        String correlation = trim(source.correlationId, 36);
        if (String.isBlank(correlation)) {
            correlation = IntegrationCorrelation.next();
        }

        return new Integration_Log__c(
            Correlation_Id__c = correlation,
            Direction__c = source.inbound == true ? 'Inbound' : 'Outbound',
            System__c = systemValue(source.systemName),
            Operation__c = trim(defaultString(source.operation, 'Unspecified'), 60),
            Status__c = statusValue(source.status),
            Endpoint__c = trim(source.endpoint, 255),
            Idempotency_Key__c = trim(source.idempotencyKey, 64),
            Status_Code__c = trim(source.statusCode, 10),
            Payload_Summary__c = trim(source.payloadSummary, 255),
            Error_Message__c = trim(source.errorMessage, 255),
            Error_Stack__c = trim(source.errorStack, 32768),
            Subscription__c = source.subscriptionId,
            Order__c = source.orderId,
            Retry_Count__c = source.retryCount == null ? 0 : source.retryCount,
            Duration_Ms__c = source.durationMs == null ? 0 : source.durationMs
        );
    }

    /** Publishes a rollback-safe audit event and returns it for assertions. */
    public static Integration_Log_Event__e publish(LogInput input) {
        Integration_Log__c record = build(input);
        Integration_Log_Event__e event = new Integration_Log_Event__e(
            Correlation_Id__c = record.Correlation_Id__c,
            Direction__c = record.Direction__c,
            System__c = record.System__c,
            Operation__c = record.Operation__c,
            Status__c = record.Status__c,
            Status_Code__c = record.Status_Code__c,
            Endpoint__c = record.Endpoint__c,
            Idempotency_Key__c = record.Idempotency_Key__c,
            Payload_Summary__c = record.Payload_Summary__c,
            Error_Message__c = record.Error_Message__c,
            Error_Stack__c = record.Error_Stack__c,
            Duration_Ms__c = record.Duration_Ms__c,
            Retry_Count__c = record.Retry_Count__c,
            Subscription_Id__c = idText(record.Subscription__c),
            Order_Id__c = idText(record.Order__c)
        );
        EventBus.publish(event);
        return event;
    }

    /** Maps an event back to a log row. Used only by the event handler. */
    public static Integration_Log__c fromEvent(Integration_Log_Event__e event) {
        LogInput input = new LogInput();
        input.correlationId = event.Correlation_Id__c;
        input.idempotencyKey = event.Idempotency_Key__c;
        input.systemName = event.System__c;
        input.operation = event.Operation__c;
        input.status = event.Status__c;
        input.statusCode = event.Status_Code__c;
        input.endpoint = event.Endpoint__c;
        input.durationMs = event.Duration_Ms__c;
        input.payloadSummary = event.Payload_Summary__c;
        input.errorMessage = event.Error_Message__c;
        input.errorStack = event.Error_Stack__c;
        input.subscriptionId = toId(event.Subscription_Id__c);
        input.orderId = toId(event.Order_Id__c);
        input.retryCount = event.Retry_Count__c == null
            ? null
            : event.Retry_Count__c.intValue();
        input.inbound = event.Direction__c == 'Inbound';
        return build(input);
    }

    private static String idText(Id value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Id toId(String value) {
        return String.isBlank(value) ? null : (Id) value;
    }

    private static String statusValue(String value) {
        String candidate = value == null ? '' : value.trim();
        return STATUSES.contains(candidate) ? candidate : 'Failure';
    }

    private static String systemValue(String value) {
        String candidate = value == null ? '' : value.trim();
        return SYSTEMS.contains(candidate) ? candidate : 'Other';
    }

    private static String defaultString(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }

    private static String trim(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.length() > maxLength ? value.left(maxLength) : value;
    }
}
