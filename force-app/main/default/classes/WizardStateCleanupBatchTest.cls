/**
 * Tests for WizardStateCleanupBatch.
 */
@IsTest
private class WizardStateCleanupBatchTest {

    private static Subscription_Wizard_State__c wizardState(
        Date expiresOn,
        DateTime lastActivity,
        Boolean isActive
    ) {
        return new Subscription_Wizard_State__c(
            Advisor__c = UserInfo.getUserId(),
            Step__c = 1,
            Last_Activity_On__c = lastActivity,
            Expires_On__c = expiresOn,
            Is_Active__c = isActive
        );
    }

    @IsTest
    static void deletesExpiredStatesAndKeepsCurrentOnes() {
        Subscription_Wizard_State__c expired = wizardState(
            Date.today().addDays(-1),
            DateTime.now().addDays(-8),
            false
        );
        Subscription_Wizard_State__c current = wizardState(
            Date.today().addDays(1),
            DateTime.now().addDays(-1),
            true
        );
        insert new List<Subscription_Wizard_State__c>{ expired, current };

        Test.startTest();
        Database.executeBatch(new WizardStateCleanupBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Subscription_Wizard_State__c WHERE Id = :expired.Id],
            'An expired wizard state must be hard-deleted'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Subscription_Wizard_State__c WHERE Id = :current.Id],
            'An unexpired wizard state must be retained'
        );
    }

    @IsTest
    static void deletesOldStatesWithNoExpiryDate() {
        Subscription_Wizard_State__c noExpiry = wizardState(
            null,
            DateTime.now().addDays(-8),
            false
        );
        insert noExpiry;

        Test.startTest();
        Database.executeBatch(new WizardStateCleanupBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Subscription_Wizard_State__c WHERE Id = :noExpiry.Id],
            'A stale state with no expiry date must still be purged'
        );
    }

    @IsTest
    static void schedulableRunsTheCleanup() {
        Subscription_Wizard_State__c expired = wizardState(
            Date.today().addDays(-1),
            DateTime.now().addDays(-8),
            false
        );
        insert expired;

        Test.startTest();
        new WizardStateCleanupBatch().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Subscription_Wizard_State__c WHERE Id = :expired.Id],
            'The Schedulable entry point must run the cleanup batch'
        );
    }
}
