@IsTest
private class ExternalApiServiceTest {
    private static final String SECRET = 'SUB-SECRET-1';

    private class EchoMock implements HttpCalloutMock {
        public Integer callCount = 0;
        public HttpRequest lastRequest;

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            lastRequest = request;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setBody('{"result":"ok"}');
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        private final Integer statusCode;
        public Integer callCount = 0;

        ErrorMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setStatus('Service Unavailable');
            response.setBody('{"error":"unavailable"}');
            return response;
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            throw new CalloutException('Simulated transport failure');
        }
    }

    private static ExternalApiService.Config activeConfig() {
        ExternalApiService.Config config = new ExternalApiService.Config();
        config.apiName = 'Bss_Provisioning';
        config.baseUrl = 'https://example.test/';
        config.authType = 'None';
        config.isActive = true;
        config.timeoutMs = 7000;
        return config;
    }

    private static ExternalApiService.Request request(String correlationId) {
        ExternalApiService.Request request = new ExternalApiService.Request();
        request.apiName = 'Bss_Provisioning';
        request.method = 'POST';
        request.path = '/v1/provision';
        request.body = '{"subscription":"' + SECRET + '"}';
        request.operation = 'provisionSubscription';
        request.systemName = 'BSS';
        request.idempotencyKey = SECRET;
        request.correlationId = correlationId;
        return request;
    }

    private static String correlation(String tag) {
        String raw = tag + '-' + String.valueOf(DateTime.now().getTime())
            + '-' + IntegrationCorrelation.next();
        return raw.left(36);
    }

    private static List<Integration_Log__c> logsFor(String correlationId) {
        Test.getEventBus().deliver();
        return [
            SELECT Id, Correlation_Id__c, Direction__c, System__c, Operation__c,
                Status__c, Status_Code__c, Endpoint__c, Idempotency_Key__c,
                Payload_Summary__c, Error_Message__c, Duration_Ms__c
            FROM Integration_Log__c
            WHERE Correlation_Id__c = :correlationId
        ];
    }

    @IsTest
    static void successfulCalloutReturnsResponseAndLogsSuccess() {
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);
        ExternalApiService.Request request = request(null);

        ExternalApiService.Response response =
            ExternalApiService.callout(request, activeConfig(), true);

        System.assertEquals(true, response.success);
        System.assertEquals(200, response.statusCode);
        System.assertEquals('{"result":"ok"}', response.body);
        System.assertEquals('https://example.test/v1/provision', response.endpoint);
        System.assertEquals(36, response.correlationId.length());
        System.assertEquals(1, mock.callCount);
        System.assertEquals('POST', mock.lastRequest.getMethod());
        System.assertEquals(response.correlationId,
            mock.lastRequest.getHeader('X-Correlation-Id'));
        System.assertEquals(SECRET,
            mock.lastRequest.getHeader('Idempotency-Key'));
        System.assertEquals('application/json',
            mock.lastRequest.getHeader('Content-Type'));
        System.assertEquals(request.body, mock.lastRequest.getBody());

        List<Integration_Log__c> logs = logsFor(response.correlationId);
        System.assertEquals(1, logs.size());
        System.assertEquals('Outbound', logs[0].Direction__c);
        System.assertEquals('BSS', logs[0].System__c);
        System.assertEquals('provisionSubscription', logs[0].Operation__c);
        System.assertEquals('Success', logs[0].Status__c);
        System.assertEquals('200', logs[0].Status_Code__c);
        System.assertEquals('https://example.test/v1/provision', logs[0].Endpoint__c);
        System.assertEquals(SECRET, logs[0].Idempotency_Key__c);
        System.assert(logs[0].Payload_Summary__c.contains('POST provisionSubscription'));
        System.assert(!logs[0].Payload_Summary__c.contains(SECRET),
            'Raw payload must never be written to the audit log.');
        System.assert(logs[0].Duration_Ms__c >= 0);
    }

    @IsTest
    static void httpFailureThrowsAndLogsFailure() {
        String correlationId = correlation('HTTP');
        ErrorMock mock = new ErrorMock(503);
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            ExternalApiService.callout(request(correlationId), activeConfig(), true);
            System.assert(false, 'A non-2xx response must throw.');
        } catch (ExternalApiException e) {
            System.assert(e.getMessage().contains('503'), e.getMessage());
        }

        System.assertEquals(1, mock.callCount);
        List<Integration_Log__c> logs = logsFor(correlationId);
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assertEquals('503', logs[0].Status_Code__c);
        System.assert(logs[0].Error_Message__c.contains('503'));
    }

    @IsTest
    static void transportExceptionThrowsAndLogsFailure() {
        String correlationId = correlation('TRANS');
        ThrowingMock mock = new ThrowingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            ExternalApiService.callout(request(correlationId), activeConfig(), true);
            System.assert(false, 'A transport exception must propagate.');
        } catch (ExternalApiException e) {
            System.assert(e.getMessage().contains('transport failure'), e.getMessage());
        }

        System.assertEquals(1, mock.callCount);
        List<Integration_Log__c> logs = logsFor(correlationId);
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('transport failure'));
        System.assertEquals(null, logs[0].Status_Code__c);
    }

    @IsTest
    static void inactiveApiIsRejectedWithoutCallout() {
        String correlationId = correlation('INACT');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);
        ExternalApiService.Config config = activeConfig();
        config.isActive = false;

        try {
            ExternalApiService.callout(request(correlationId), config, true);
            System.assert(false, 'An inactive API must not be called.');
        } catch (ExternalApiException e) {
            System.assert(e.getMessage().contains('inactive'), e.getMessage());
        }

        System.assertEquals(0, mock.callCount);
        List<Integration_Log__c> logs = logsFor(correlationId);
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('inactive'));
    }

    @IsTest
    static void globalKillSwitchBlocksCallout() {
        String correlationId = correlation('KILL');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            ExternalApiService.callout(request(correlationId), activeConfig(), false);
            System.assert(false, 'The global kill switch must block the callout.');
        } catch (ExternalApiException e) {
            System.assert(e.getMessage().contains('disabled'), e.getMessage());
        }

        System.assertEquals(0, mock.callCount);
        List<Integration_Log__c> logs = logsFor(correlationId);
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('disabled'));
    }

    @IsTest
    static void namedCredentialAuthRequiresCredential() {
        String correlationId = correlation('NCRED');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);
        ExternalApiService.Config config = activeConfig();
        config.authType = 'NamedCredential';
        config.namedCredential = null;

        try {
            ExternalApiService.callout(request(correlationId), config, true);
            System.assert(false, 'NamedCredential auth needs a credential name.');
        } catch (ExternalApiException e) {
            System.assert(e.getMessage().contains('Named Credential'), e.getMessage());
        }

        System.assertEquals(0, mock.callCount);
        System.assertEquals(1, logsFor(correlationId).size());
    }

    @IsTest
    static void missingMetadataConfigurationIsLoggedAndRejected() {
        String correlationId = correlation('META');
        ExternalApiService.Request request = request(correlationId);
        request.apiName = 'Does_Not_Exist__c';

        try {
            ExternalApiService.callout(request);
            System.assert(false, 'Missing configuration must be rejected.');
        } catch (ExternalApiException e) {
            System.assert(e.getMessage().contains('configuration not found'),
                e.getMessage());
        }

        List<Integration_Log__c> logs = logsFor(correlationId);
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('configuration not found'));
    }
}
