@IsTest
private class BssReconciliationTest {
    @TestSetup
    static void createSubscriptions() {
        Account account = new Account(Name = 'ATS Reconciliation Test');
        insert account;
        Asset asset = new Asset(
            Name = 'ATS Reconciliation Asset',
            AccountId = account.Id
        );
        insert asset;

        List<Subscription__c> rows = new List<Subscription__c>();
        for (Integer index = 1; index <= 2; index++) {
            rows.add(
                new Subscription__c(
                    Account__c = account.Id,
                    Asset__c = asset.Id,
                    Service_Line_Type__c = 'Mobile',
                    Status__c = 'Draft',
                    External_Reference__c = 'SIM-REC-00' + index
                )
            );
        }
        insert rows;
    }

    @IsTest
    static void factoryDefaultsToSimulatedAndExposesRealSeam() {
        BssStatusReconciliationGateway defaultGateway =
            BssStatusReconciliationGatewayFactory.create();
        System.assert(
            defaultGateway instanceof SimulatedBssStatusReconciliationGateway,
            'The flag-off default must stay simulated.'
        );

        BssStatusReconciliationGateway liveGateway =
            BssStatusReconciliationGatewayFactory.create(true);
        System.assert(
            liveGateway instanceof RealBssStatusReconciliationGateway,
            'The cutover seam must select the real gateway.'
        );
    }

    @IsTest
    static void realGatewaySendsNoPiiAndMapsStatus() {
        RealBssStatusReconciliationGateway gateway =
            new RealBssStatusReconciliationGateway();
        BssStatusRequest request = sampleRequest();

        ExternalApiService.Request apiRequest =
            gateway.buildRequest(new List<BssStatusRequest>{ request });
        System.assertEquals('Bss_Status', apiRequest.apiName);
        System.assertEquals('status', apiRequest.path);
        System.assertEquals(request.correlationId, apiRequest.correlationId);
        System.assert(!apiRequest.body.contains('MSISDN'));
        System.assert(!apiRequest.body.contains('accountName'));
        System.assert(apiRequest.body.contains(request.subscriptionNumber));

        ExternalApiService.Response apiResponse =
            new ExternalApiService.Response();
        apiResponse.statusCode = 200;
        apiResponse.durationMs = 12;
        apiResponse.endpoint = 'https://bss.example.invalid/status';
        apiResponse.body = '[{"subscriptionNumber":"' + request.subscriptionNumber
            + '","externalStatus":"Active","success":true,'
            + '"statusCode":"200"}]';

        List<BssStatusResponse> mapped = gateway.mapResponses(
            new List<BssStatusRequest>{ request },
            apiResponse
        );
        System.assertEquals(1, mapped.size());
        System.assertEquals(request.subscriptionId, mapped[0].subscriptionId);
        System.assertEquals('Active', mapped[0].externalStatus);
        System.assertEquals(true, mapped[0].success);
    }

    @IsTest
    static void batchDetectsDriftWithoutChangingLocalStatus() {
        List<Subscription__c> originals = subscriptions();
        Map<String, String> overrides = new Map<String, String>{
            originals[0].Name => 'Active'
        };
        BssReconciliationBatch.setGateway(
            new SimulatedBssStatusReconciliationGateway(overrides)
        );

        Test.startTest();
        Database.executeBatch(new BssReconciliationBatch(), 200);
        Test.stopTest();
        Test.getEventBus().deliver();

        List<Subscription__c> refreshed = subscriptions();
        System.assertEquals('Active', refreshed[0].External_Status__c);
        System.assertEquals('Draft', refreshed[0].Status__c);
        System.assertEquals('Draft', refreshed[1].External_Status__c);
        System.assertNotEquals(null, refreshed[0].Last_Sync_DateTime__c);

        List<Integration_Log__c> driftLogs = [
            SELECT Error_Message__c, Subscription__c
            FROM Integration_Log__c
            WHERE Operation__c = 'BssReconciliation'
              AND Status__c = 'Failure'
        ];
        System.assertEquals(1, driftLogs.size());
        System.assertEquals(refreshed[0].Id, driftLogs[0].Subscription__c);
        System.assert(
            driftLogs[0].Error_Message__c.contains(
                'Drift: Salesforce=Draft; BSS=Active'
            )
        );

        Integration_Log__c summary = [
            SELECT Status__c, Payload_Summary__c
            FROM Integration_Log__c
            WHERE Operation__c = 'BssReconciliationSummary'
            LIMIT 1
        ];
        System.assertEquals('Failure', summary.Status__c);
        System.assertEquals('checked=2; drift=1', summary.Payload_Summary__c);
    }

    @IsTest
    static void batchWithNoDriftWritesExternalStatusOnly() {
        BssReconciliationBatch.setGateway(
            new SimulatedBssStatusReconciliationGateway()
        );

        Test.startTest();
        Database.executeBatch(new BssReconciliationBatch(), 200);
        Test.stopTest();
        Test.getEventBus().deliver();

        List<Subscription__c> refreshed = subscriptions();
        for (Subscription__c subscription : refreshed) {
            System.assertEquals('Draft', subscription.External_Status__c);
            System.assertEquals('Draft', subscription.Status__c);
        }

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Integration_Log__c
                WHERE Operation__c = 'BssReconciliation'
                  AND Status__c = 'Failure'
            ]
        );
        Integration_Log__c summary = [
            SELECT Status__c, Payload_Summary__c
            FROM Integration_Log__c
            WHERE Operation__c = 'BssReconciliationSummary'
            LIMIT 1
        ];
        System.assertEquals('Success', summary.Status__c);
        System.assertEquals('checked=2; drift=0', summary.Payload_Summary__c);
    }

    private static List<Subscription__c> subscriptions() {
        return [
            SELECT
                Id,
                Name,
                Status__c,
                External_Status__c,
                External_Reference__c,
                Last_Sync_DateTime__c
            FROM Subscription__c
            WHERE External_Reference__c LIKE 'SIM-REC-%'
            ORDER BY External_Reference__c
        ];
    }

    private static BssStatusRequest sampleRequest() {
        BssStatusRequest request = new BssStatusRequest();
        request.subscriptionId = (Id) (
            Subscription__c.SObjectType.getDescribe().getKeyPrefix()
            + '000000000000'
        );
        request.subscriptionNumber = 'SUB-RECON-SCAFFOLD';
        request.externalReference = 'SIM-RECON-SCAFFOLD';
        request.localStatus = 'Draft';
        request.correlationId = 'e8-recon-scaffold';
        return request;
    }
}
