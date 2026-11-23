// SeeAllData is intentional: this smoke test exercises the real metadata path,
// including the organisation's External_Api_Enabled__c feature flag.
@IsTest(SeeAllData=true)
private class E8IntegrationSmokeTest {
    private class Always500 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setStatus('Internal Server Error');
            response.setBody('{"error":"synthetic"}');
            return response;
        }
    }

    @IsTest
    static void failingCalloutReturnsExpectedFailureAndAuditsIt() {
        Test.setMock(HttpCalloutMock.class, new Always500());

        E8IntegrationSmoke.Result result = E8IntegrationSmoke.failingCallout();

        System.assertEquals('EXPECTED_FAILURE', result.outcome);
        System.assertNotEquals(null, result.correlationId);
        System.assert(result.message.contains('500'), result.message);

        Test.getEventBus().deliver();
        List<Integration_Log__c> logs = [
            SELECT Status__c, Status_Code__c, System__c, Error_Message__c
            FROM Integration_Log__c
            WHERE Correlation_Id__c = :result.correlationId
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assertEquals('500', logs[0].Status_Code__c);
        System.assertEquals('Other', logs[0].System__c);
        System.assert(logs[0].Error_Message__c.contains('500'));
    }
}
