/**
 * Tests for IntegrationLogCleanupBatch.
 */
@IsTest
private class IntegrationLogCleanupBatchTest {

    private static Integration_Log__c logRow(String correlationId) {
        return new Integration_Log__c(
            Correlation_Id__c = correlationId,
            Direction__c = 'Outbound',
            System__c = 'BSS',
            Operation__c = 'testCleanup',
            Status__c = 'Success'
        );
    }

    @IsTest
    static void deletesOnlyLogsOlderThanThirteenMonths() {
        Integration_Log__c oldLog = logRow('old-log');
        Integration_Log__c recentLog = logRow('recent-log');
        insert new List<Integration_Log__c>{ oldLog, recentLog };

        Test.setCreatedDate(oldLog.Id, DateTime.now().addMonths(-14));
        Test.setCreatedDate(recentLog.Id, DateTime.now().addMonths(-1));

        Test.startTest();
        Database.executeBatch(new IntegrationLogCleanupBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Log__c WHERE Id = :oldLog.Id],
            'A log older than 13 months must be hard-deleted'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Integration_Log__c WHERE Id = :recentLog.Id],
            'A recent log must be retained'
        );
    }

    @IsTest
    static void schedulableRunsTheCleanup() {
        Integration_Log__c oldLog = logRow('scheduled-old-log');
        insert oldLog;
        Test.setCreatedDate(oldLog.Id, DateTime.now().addMonths(-14));

        Test.startTest();
        new IntegrationLogCleanupBatch().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Log__c WHERE Id = :oldLog.Id],
            'The Schedulable entry point must run the cleanup batch'
        );
    }
}
