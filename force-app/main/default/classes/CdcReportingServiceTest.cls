@IsTest
private class CdcReportingServiceTest {
    @TestSetup
    static void createFixture() {
        insert new ATS_Feature_Flags__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            CDC_Reporting_Live__c = false
        );
    }

    @IsTest
    static void flagDefaultsOff() {
        CdcReportingService.liveOverride = null;
        System.assertEquals(false, CdcReportingService.isLive());
    }

    @IsTest
    static void allowlistExcludesPiiFields() {
        Subscription__c sample = new Subscription__c(
            Status__c = 'Active',
            MSISDN__c = '+33123456789',
            Monthly_Amount__c = 29.99
        );

        Map<String, Object> values =
            CdcReportingService.allowedValues(sample, 'Subscription__c');

        System.assertEquals('Active', values.get('Status__c'));
        System.assertEquals(29.99, values.get('Monthly_Amount__c'));
        System.assert(!values.containsKey('MSISDN__c'));
        System.assert(!values.containsKey('Account__c'));
        System.assert(!values.containsKey('Contact__c'));
    }

    @IsTest
    static void flagOffIgnoresEvents() {
        CdcReportingService.liveOverride = null;

        Test.startTest();
        CdcReportingService.handle(
            new List<SObject>{ new Eligibility__c(Name = 'CDC-OFF-TEST') },
            'Eligibility__c'
        );
        Test.stopTest();
        Test.getEventBus().deliver();

        System.assertEquals(0, logs().size());
    }

    @IsTest
    static void liveHandlePublishesSanitisedAudit() {
        CdcReportingService.liveOverride = null;
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance(
            UserInfo.getOrganizationId()
        );
        flags.CDC_Reporting_Live__c = true;
        update flags;
        System.assertEquals(true, CdcReportingService.isLive());

        Eligibility__c sample = new Eligibility__c(
            Name = 'CDC-ON-TEST',
            Country__c = 'FR',
            Postal_Code__c = '75002',
            Fiber_Available__c = true,
            Max_Downstream_Mbps__c = 1000
        );

        Test.startTest();
        CdcReportingService.handle(
            new List<SObject>{ sample },
            'Eligibility__c'
        );
        Test.stopTest();
        Test.getEventBus().deliver();

        List<Integration_Log__c> rows = logs();
        System.assertEquals(1, rows.size());
        System.assertEquals('CDC', rows[0].System__c);
        System.assertEquals('CDC.Eligibility__c', rows[0].Operation__c);
        System.assert(rows[0].Payload_Summary__c.contains('events=1'));
        System.assert(rows[0].Payload_Summary__c.contains('Fiber_Available__c'));
        System.assert(!rows[0].Payload_Summary__c.contains('Postal_Code__c'));
        System.assert(!rows[0].Payload_Summary__c.contains('Geo_Hash__c'));
        System.assert(!rows[0].Payload_Summary__c.contains('75002'));
    }

    private static List<Integration_Log__c> logs() {
        return [
            SELECT Id, System__c, Operation__c, Payload_Summary__c
            FROM Integration_Log__c
            WHERE Operation__c LIKE 'CDC.%'
        ];
    }
}
