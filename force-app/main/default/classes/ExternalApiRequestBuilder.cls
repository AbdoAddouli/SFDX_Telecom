/** Pure request/response mapping. No SOQL, DML or callouts here. */
public with sharing class ExternalApiRequestBuilder {
    public String endpoint(
        ExternalApiService.Request request,
        ExternalApiService.Config config
    ) {
        String base = config.baseUrl == null ? '' : config.baseUrl.trim();
        String suffix = request.path == null ? '' : request.path.trim();
        if (String.isBlank(suffix)) {
            return base;
        }
        while (base.endsWith('/')) {
            base = base.substring(0, base.length() - 1);
        }
        while (suffix.startsWith('/')) {
            suffix = suffix.substring(1);
        }
        return base + '/' + suffix;
    }

    public HttpRequest build(
        ExternalApiService.Request request,
        ExternalApiService.Config config,
        String endpoint
    ) {
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setMethod(request.method.trim().toUpperCase());
        httpRequest.setEndpoint(endpoint);
        httpRequest.setTimeout(config.timeoutMs == null
            ? ExternalApiService.DEFAULT_TIMEOUT_MS
            : config.timeoutMs.intValue());

        if (request.headers != null) {
            for (String key : request.headers.keySet()) {
                httpRequest.setHeader(key, request.headers.get(key));
            }
        }
        if (String.isNotBlank(request.body)
            && httpRequest.getHeader('Content-Type') == null) {
            httpRequest.setHeader('Content-Type', 'application/json');
        }
        httpRequest.setHeader('X-Correlation-Id', request.correlationId);
        if (String.isNotBlank(request.idempotencyKey)) {
            httpRequest.setHeader('Idempotency-Key', request.idempotencyKey);
        }
        if (String.isNotBlank(request.body)) {
            httpRequest.setBody(request.body);
        }
        return httpRequest;
    }

    public Boolean isSuccess(Integer statusCode) {
        return statusCode >= 200 && statusCode < 300;
    }

    public ExternalApiService.Response response(
        ExternalApiService.Request request,
        HttpResponse httpResponse,
        Decimal duration,
        String endpoint
    ) {
        ExternalApiService.Response response = new ExternalApiService.Response();
        response.success = true;
        response.statusCode = httpResponse.getStatusCode();
        response.body = httpResponse.getBody();
        response.correlationId = request.correlationId;
        response.idempotencyKey = request.idempotencyKey;
        response.endpoint = endpoint;
        response.durationMs = duration;
        response.message = 'External API call succeeded.';
        return response;
    }
}
