@IsTest
private class IntegrationLogServiceTest {

    private static String text(String seed, Integer length) {
        String value = '';
        while (value.length() < length) {
            value += seed;
        }
        return value.left(length);
    }

    private static String correlation(String tag) {
        String raw = tag + '-' + String.valueOf(DateTime.now().getTime())
            + '-' + IntegrationCorrelation.next();
        return raw.left(36);
    }

    @IsTest
    static void buildMapsFieldsAndTruncatesToSchemaLengths() {
        IntegrationLogService.LogInput input = new IntegrationLogService.LogInput();
        input.correlationId = text('C', 50);
        input.idempotencyKey = text('I', 80);
        input.systemName = 'NotASystem';
        input.operation = text('O', 80);
        input.endpoint = text('E', 300);
        input.status = 'NotAStatus';
        input.statusCode = text('5', 12);
        input.durationMs = 123;
        input.payloadSummary = text('P', 300);
        input.errorMessage = text('M', 300);
        input.errorStack = text('S', 33000);
        input.retryCount = 2;
        input.inbound = true;

        Integration_Log__c record = IntegrationLogService.build(input);

        System.assertEquals(36, record.Correlation_Id__c.length());
        System.assertEquals(64, record.Idempotency_Key__c.length());
        System.assertEquals('Other', record.System__c);
        System.assertEquals(60, record.Operation__c.length());
        System.assertEquals(255, record.Endpoint__c.length());
        System.assertEquals('Failure', record.Status__c);
        System.assertEquals(10, record.Status_Code__c.length());
        System.assertEquals(123, record.Duration_Ms__c);
        System.assertEquals(255, record.Payload_Summary__c.length());
        System.assertEquals(255, record.Error_Message__c.length());
        System.assertEquals(32768, record.Error_Stack__c.length());
        System.assertEquals(2, record.Retry_Count__c);
        System.assertEquals('Inbound', record.Direction__c);
    }

    @IsTest
    static void publishedEventCreatesAuditRow() {
        String correlationId = correlation('LOG');
        IntegrationLogService.LogInput input = new IntegrationLogService.LogInput();
        input.correlationId = correlationId;
        input.systemName = 'BSS';
        input.operation = 'provisionSubscription';
        input.endpoint = 'https://bss.example/v1/provision';
        input.status = 'Success';
        input.statusCode = '200';
        input.durationMs = 42;
        input.idempotencyKey = 'SUB-1001';

        Integration_Log_Event__e published = IntegrationLogService.publish(input);
        System.assertEquals(correlationId, published.Correlation_Id__c);
        System.assertEquals('Success', published.Status__c);

        Test.getEventBus().deliver();

        List<Integration_Log__c> rows = [
            SELECT Id, Correlation_Id__c, Status__c, System__c, Operation__c,
                Endpoint__c, Status_Code__c, Idempotency_Key__c, Duration_Ms__c,
                Direction__c
            FROM Integration_Log__c
            WHERE Correlation_Id__c = :correlationId
        ];
        System.assertEquals(1, rows.size());
        System.assertNotEquals(null, rows[0].Id);
        System.assertEquals('Success', rows[0].Status__c);
        System.assertEquals('BSS', rows[0].System__c);
        System.assertEquals('provisionSubscription', rows[0].Operation__c);
        System.assertEquals('https://bss.example/v1/provision', rows[0].Endpoint__c);
        System.assertEquals('200', rows[0].Status_Code__c);
        System.assertEquals('SUB-1001', rows[0].Idempotency_Key__c);
        System.assertEquals(42, rows[0].Duration_Ms__c);
        System.assertEquals('Outbound', rows[0].Direction__c);
    }

    // Apex forbids an open savepoint across Http.send(), so rollback durability
    // is proven at the publisher boundary, which is where the event is emitted.
    @IsTest
    static void failureLogSurvivesBusinessRollback() {
        String correlationId = correlation('ROLL');
        Savepoint savepoint = Database.setSavepoint();
        IntegrationLogService.LogInput input = new IntegrationLogService.LogInput();
        input.correlationId = correlationId;
        input.systemName = 'BSS';
        input.operation = 'provisionSubscription';
        input.endpoint = 'https://bss.example/v1/provision';
        input.status = 'Failure';
        input.statusCode = '500';
        input.errorMessage = 'BSS unavailable';
        input.errorStack = 'Class.Bss: line 12';

        IntegrationLogService.publish(input);
        Database.rollback(savepoint);
        Test.getEventBus().deliver();

        List<Integration_Log__c> rows = [
            SELECT Id, Status__c, Status_Code__c, Error_Message__c, Error_Stack__c
            FROM Integration_Log__c
            WHERE Correlation_Id__c = :correlationId
        ];
        System.assertEquals(1, rows.size(),
            'Publish Immediately events must survive a business rollback.');
        System.assertEquals('Failure', rows[0].Status__c);
        System.assertEquals('500', rows[0].Status_Code__c);
        System.assertEquals('BSS unavailable', rows[0].Error_Message__c);
        System.assertEquals('Class.Bss: line 12', rows[0].Error_Stack__c);
    }

    @IsTest
    static void blankInputUsesSafeDefaults() {
        Integration_Log__c record = IntegrationLogService.build(null);

        System.assertEquals(36, record.Correlation_Id__c.length());
        System.assertEquals('Outbound', record.Direction__c);
        System.assertEquals('Other', record.System__c);
        System.assertEquals('Unspecified', record.Operation__c);
        System.assertEquals('Failure', record.Status__c);
        System.assertEquals(0, record.Duration_Ms__c);
        System.assertEquals(0, record.Retry_Count__c);
    }
}
