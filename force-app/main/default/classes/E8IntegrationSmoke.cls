/**
 * Synthetic runtime smoke harness for E8. Sends a non-PII payload to a
 * deliberately failing endpoint configured in custom metadata. Used to prove
 * that a callout failure commits no business writes while the audit event
 * survives. Not referenced by production flows.
 */
public with sharing class E8IntegrationSmoke {
    public class Result {
        public String correlationId;
        public String outcome;
        public String message;
        public Integer statusCode;
    }

    public static Result failingCallout() {
        ExternalApiService.Request request = new ExternalApiService.Request();
        request.apiName = 'E8_Failure_Test';
        request.method = 'POST';
        request.path = 'status/500';
        request.body = '{"scenario":"E8_RUNTIME_ROLLBACK_PROOF","containsPii":false}';
        request.operation = 'E8_Failure_Proof';
        request.systemName = 'Other';
        request.idempotencyKey = 'e8-failure-' + String.valueOf(DateTime.now().getTime());

        try {
            ExternalApiService.callout(request);
            Result result = new Result();
            result.correlationId = request.correlationId;
            result.outcome = 'UNEXPECTED_SUCCESS';
            result.message = 'The deliberately failing endpoint returned 2xx.';
            return result;
        } catch (ExternalApiException e) {
            Result result = new Result();
            result.correlationId = request.correlationId;
            result.outcome = 'EXPECTED_FAILURE';
            result.message = e.getMessage();
            result.statusCode = 500;
            return result;
        }
    }
}
