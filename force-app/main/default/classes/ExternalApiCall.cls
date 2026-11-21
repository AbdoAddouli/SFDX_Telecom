/**
 * Executes one governed callout. Kept separate from the façade so each step is
 * small, testable and reusable. No DML happens before Http.send().
 */
public with sharing class ExternalApiCall {
    private final ExternalApiService.Request request;
    private final Boolean fromMetadata;
    private final ExternalApiValidator validator = new ExternalApiValidator();
    private final ExternalApiRequestBuilder builder = new ExternalApiRequestBuilder();
    private final ExternalApiLogWriter logger = new ExternalApiLogWriter();

    private ExternalApiService.Config config;
    private Boolean globalEnabled;

    public ExternalApiCall(ExternalApiService.Request request) {
        this(request, null, null, true);
    }

    public ExternalApiCall(
        ExternalApiService.Request request,
        ExternalApiService.Config config,
        Boolean globalEnabled
    ) {
        this(request, config, globalEnabled, false);
    }

    private ExternalApiCall(
        ExternalApiService.Request request,
        ExternalApiService.Config config,
        Boolean globalEnabled,
        Boolean fromMetadata
    ) {
        this.request = request;
        this.config = config;
        this.globalEnabled = globalEnabled;
        this.fromMetadata = fromMetadata;
    }

    public ExternalApiService.Response execute() {
        prepare();

        String endpoint = builder.endpoint(request, config);
        HttpRequest httpRequest = buildRequest(endpoint);

        Long startedAt = System.currentTimeMillis();
        HttpResponse httpResponse = send(httpRequest, startedAt, endpoint);
        Decimal duration = System.currentTimeMillis() - startedAt;
        Integer statusCode = httpResponse.getStatusCode();

        if (!builder.isSuccess(statusCode)) {
            String message = 'External API ' + request.apiName
                + ' returned HTTP ' + statusCode + '.';
            logger.failure(request, endpoint, message, null, duration,
                String.valueOf(statusCode));
            throw new ExternalApiException(message);
        }

        logger.success(request, endpoint, duration, statusCode);
        return builder.response(request, httpResponse, duration, endpoint);
    }

    private void prepare() {
        try {
            validator.prepare(request);
            if (fromMetadata) {
                ExternalApiConfigLoader loader = new ExternalApiConfigLoader();
                config = loader.load(request.apiName);
                globalEnabled = loader.globalEnabled();
            }
            validator.validate(request, config, globalEnabled);
        } catch (ExternalApiException e) {
            logger.failure(request, null, e.getMessage(), null, null, null);
            throw e;
        }
    }

    private HttpRequest buildRequest(String endpoint) {
        try {
            return builder.build(request, config, endpoint);
        } catch (Exception e) {
            String message = 'External API ' + request.apiName
                + ' request could not be built: ' + e.getMessage();
            logger.failure(request, endpoint, message, null, null, null);
            throw new ExternalApiException(message);
        }
    }

    private HttpResponse send(HttpRequest httpRequest, Long startedAt, String endpoint) {
        try {
            return new Http().send(httpRequest);
        } catch (Exception e) {
            Decimal duration = System.currentTimeMillis() - startedAt;
            String message = 'External API ' + request.apiName
                + ' callout failed: ' + e.getMessage();
            logger.failure(request, endpoint, message, e.getStackTraceString(),
                duration, null);
            throw new ExternalApiException(message);
        }
    }
}
