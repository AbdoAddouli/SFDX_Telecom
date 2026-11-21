/**
 * Thin façade for governed outbound callouts.
 *
 * Configuration loading, validation, request building and audit logging live
 * in focused collaborators so this class stays short and easy to extend.
 * One invocation performs exactly one callout and, at most, one log insert.
 * Bulk callers must use Batch/Queueable Apex rather than looping here.
 */
public with sharing class ExternalApiService {
    public static final Integer DEFAULT_TIMEOUT_MS = 10000;

    public class Config {
        public String apiName;
        public String baseUrl;
        public String authType;
        public String namedCredential;
        public Decimal timeoutMs = ExternalApiService.DEFAULT_TIMEOUT_MS;
        public Decimal cacheTtlSeconds = 0;
        public Decimal rateLimitPerMinute;
        public Boolean isActive = true;
    }

    public class Request {
        public String apiName;
        public String method = 'POST';
        public String path;
        public Map<String, String> headers = new Map<String, String>();
        public String body;
        public String correlationId;
        public String idempotencyKey;
        public String operation;
        public String systemName = 'BSS';
        public Id subscriptionId;
        public Id orderId;
        public Integer retryCount;
    }

    public class Response {
        public Boolean success = false;
        public Integer statusCode;
        public String body;
        public String correlationId;
        public String idempotencyKey;
        public String endpoint;
        public Decimal durationMs;
        public String message;
    }

    /** Production entry point: configuration is resolved from metadata. */
    public static Response callout(Request request) {
        return new ExternalApiCall(request).execute();
    }

    /** Test seam: injects configuration without depending on org metadata. */
    @TestVisible
    static Response callout(Request request, Config config, Boolean globalEnabled) {
        return new ExternalApiCall(request, config, globalEnabled).execute();
    }
}
