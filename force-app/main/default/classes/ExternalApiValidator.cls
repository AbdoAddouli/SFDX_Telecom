/** Fail-fast checks shared by metadata and injected configurations. */
public with sharing class ExternalApiValidator {
    private static final Set<String> HTTP_METHODS = new Set<String>{
        'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'
    };

    /** Assigns a correlation ID before any failure can be logged. */
    public void prepare(ExternalApiService.Request request) {
        if (request == null) {
            throw new ExternalApiException('External API request is required.');
        }
        if (String.isBlank(request.correlationId)) {
            request.correlationId = IntegrationCorrelation.next();
        }
    }

    public void validate(
        ExternalApiService.Request request,
        ExternalApiService.Config config,
        Boolean globalEnabled
    ) {
        validateRequest(request);
        validateConfig(config, globalEnabled);
    }

    private void validateRequest(ExternalApiService.Request request) {
        if (String.isBlank(request.apiName)) {
            throw new ExternalApiException('External API name is required.');
        }
        String method = request.method == null ? '' : request.method.trim().toUpperCase();
        if (!HTTP_METHODS.contains(method)) {
            throw new ExternalApiException(
                'Unsupported HTTP method: ' + String.valueOf(request.method));
        }
    }

    private void validateConfig(
        ExternalApiService.Config config,
        Boolean globalEnabled
    ) {
        if (config == null) {
            throw new ExternalApiException('External API configuration is missing.');
        }
        if (globalEnabled == false) {
            throw new ExternalApiException(
                'External callouts are disabled by ATS_Feature_Flags__c.');
        }
        if (config.isActive == false) {
            throw new ExternalApiException(
                'External API ' + config.apiName + ' is inactive.');
        }
        if (String.isBlank(config.baseUrl)) {
            throw new ExternalApiException(
                'External API ' + config.apiName + ' has no base URL.');
        }
        if (String.isBlank(config.authType)) {
            throw new ExternalApiException(
                'External API ' + config.apiName + ' has no auth type.');
        }
        if (config.authType == 'NamedCredential'
            && String.isBlank(config.namedCredential)) {
            throw new ExternalApiException('External API ' + config.apiName
                + ' requires a Named Credential.');
        }
    }
}
