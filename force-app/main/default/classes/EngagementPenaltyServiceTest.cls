@IsTest
private class EngagementPenaltyServiceTest {
    @IsTest
    static void calculatesFeeFromSnapshotsAndMatrix() {
        Date today = Date.today();
        Engagement__c engagement = engagement(
            today.addMonths(-18),
            today.addMonths(6),
            24,
            39.99
        );

        Test.startTest();
        EngagementPenaltyService.Result result =
            EngagementPenaltyService.calculate(
                engagement,
                'Consumer',
                'Mobile',
                today
            );
        Test.stopTest();

        System.assertEquals(35.99, result.fee);
        System.assertEquals(15, result.rate);
        System.assertEquals(6, result.monthsRemaining);
        System.assertEquals('Consumer_Mobile_24M', result.ruleName);
        System.assertEquals(false, result.expired);
        System.assertEquals('Consumer_Mobile_24M', engagement.Penalty_Rule__c);
        System.assertEquals(35.99, engagement.Early_Termination_Fee__c);
        System.assert(
            String.isNotBlank(engagement.Penalty_Breakdown__c),
            'Breakdown should explain the fee'
        );
    }

    @IsTest
    static void missingMatrixRowUsesDefaultRule() {
        Date today = Date.today();
        Engagement__c engagement = engagement(
            today.addMonths(-2),
            today.addMonths(10),
            12,
            39.99
        );

        Test.startTest();
        EngagementPenaltyService.Result result =
            EngagementPenaltyService.calculate(
                engagement,
                'Partner',
                'Satellite',
                today
            );
        Test.stopTest();

        System.assertEquals(0, result.fee);
        System.assertEquals('Default_No_Penalty', result.ruleName);
        System.assert(result.breakdown.contains('Default no-penalty rule'));
    }

    @IsTest
    static void expiredCommitmentHasNoFee() {
        Date today = Date.today();
        Engagement__c engagement = engagement(
            today.addMonths(-13),
            today.addDays(-1),
            12,
            39.99
        );

        Test.startTest();
        EngagementPenaltyService.Result result =
            EngagementPenaltyService.calculate(
                engagement,
                'Consumer',
                'Mobile',
                today
            );
        Test.stopTest();

        System.assertEquals(true, result.expired);
        System.assertEquals(0, result.fee);
        System.assert(result.breakdown.contains('expired'));
    }

    @IsTest
    static void deviceWindowUsesFourteenDays() {
        Date today = Date.today();

        Engagement__c withinWindow = engagement(
            today,
            today.addMonths(12),
            12,
            20
        );
        EngagementPenaltyService.Result inside =
            EngagementPenaltyService.calculate(
                withinWindow,
                'Consumer',
                'Device',
                today.addDays(13)
            );
        System.assertEquals(true, inside.withinPenaltyFreeWindow);
        System.assertEquals(0, inside.fee);

        Engagement__c afterWindow = engagement(
            today,
            today.addMonths(12),
            12,
            20
        );

        Test.startTest();
        EngagementPenaltyService.Result outside =
            EngagementPenaltyService.calculate(
                afterWindow,
                'Consumer',
                'Device',
                today.addDays(15)
            );
        Test.stopTest();

        System.assertEquals(false, outside.withinPenaltyFreeWindow);
        System.assertEquals('Consumer_Device_Any', outside.ruleName);
        System.assertEquals(50, outside.rate);
        System.assertEquals(100, outside.fee);
    }

    private static Engagement__c engagement(
        Date startDate,
        Date endDate,
        Integer durationMonths,
        Decimal monthlyAmount
    ) {
        return new Engagement__c(
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Duration_Months__c = durationMonths,
            Monthly_Amount__c = monthlyAmount
        );
    }
}
