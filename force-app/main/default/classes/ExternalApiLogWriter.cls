/** Translates callout outcomes into best-effort Integration_Log__c rows. */
public with sharing class ExternalApiLogWriter {
    public void success(
        ExternalApiService.Request request,
        String endpoint,
        Decimal duration,
        Integer statusCode
    ) {
        write(request, endpoint, 'Success', null, null, duration,
            String.valueOf(statusCode));
    }

    public void failure(
        ExternalApiService.Request request,
        String endpoint,
        String message,
        String stackTrace,
        Decimal duration,
        String statusCode
    ) {
        write(request, endpoint, 'Failure', message, stackTrace, duration,
            statusCode);
    }

    private void write(
        ExternalApiService.Request request,
        String endpoint,
        String status,
        String errorMessage,
        String stackTrace,
        Decimal duration,
        String statusCode
    ) {
        IntegrationLogService.LogInput input = new IntegrationLogService.LogInput();
        input.correlationId = request == null ? null : request.correlationId;
        input.idempotencyKey = request == null ? null : request.idempotencyKey;
        input.systemName = request == null ? 'BSS' : request.systemName;
        input.operation = request == null || String.isBlank(request.operation)
            ? 'ExternalApiCall'
            : request.operation;
        input.endpoint = endpoint;
        input.status = status;
        input.statusCode = statusCode;
        input.durationMs = duration;
        input.errorMessage = errorMessage;
        input.errorStack = stackTrace;
        input.subscriptionId = request == null ? null : request.subscriptionId;
        input.orderId = request == null ? null : request.orderId;
        input.retryCount = request == null ? null : request.retryCount;
        input.payloadSummary = summary(request);
        IntegrationLogService.publish(input);
    }

    /** Never persist raw bodies: they can contain customer data. */
    private String summary(ExternalApiService.Request request) {
        if (request == null) {
            return 'ExternalApiCall';
        }
        String operation = String.isBlank(request.operation)
            ? 'ExternalApiCall'
            : request.operation;
        Integer size = String.isBlank(request.body) ? 0 : request.body.length();
        return request.method + ' ' + operation + ' bytes=' + size;
    }
}
