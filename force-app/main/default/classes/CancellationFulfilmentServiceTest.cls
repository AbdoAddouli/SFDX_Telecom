@IsTest
private class CancellationFulfilmentServiceTest {
    private static Integer uniqueIndex = 0;

    private class Fixture {
        Account account;
        Contact contact;
        Product2 product;
        Asset assetRecord;
        Contract contractRecord;
        Subscription__c subscription;
        Engagement__c engagement;
        Case caseRecord;
        Customer_Request__c request;
    }

    private class FailingGateway implements BssDeprovisioningGateway {
        public List<BssProvisioningResponse> deprovision(
            List<BssProvisioningRequest> requests
        ) {
            List<BssProvisioningResponse> responses =
                new List<BssProvisioningResponse>();
            for (BssProvisioningRequest request : requests) {
                BssProvisioningResponse response = new BssProvisioningResponse();
                response.subscriptionId = request.subscriptionId;
                response.success = false;
                response.message = 'BSS unavailable';
                response.statusCode = '503';
                responses.add(response);
            }
            return responses;
        }
    }

    private class CountingGateway implements BssDeprovisioningGateway {
        public Integer calls = 0;
        private final BssDeprovisioningGateway delegate =
            new SimulatedBssProvisioningGateway();

        public List<BssProvisioningResponse> deprovision(
            List<BssProvisioningRequest> requests
        ) {
            calls++;
            return delegate.deprovision(requests);
        }
    }

    @IsTest
    static void batchFulfilsDueCancellationAndChurnsAccount() {
        Fixture fixture = createFixture(Date.today().addDays(-1), 35.99);

        List<SObject> scope = new List<SObject>();
        for (Customer_Request__c loaded :
            loadRequests(new Set<Id>{ fixture.request.Id })) {
            scope.add(loaded);
        }

        Test.startTest();
        new CancellationFulfilmentBatch().execute(null, scope);
        Test.stopTest();

        Subscription__c subscription = [
            SELECT Status__c, External_Status__c, Last_Sync_DateTime__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Cancelled', subscription.Status__c);
        System.assertEquals('Cancelled', subscription.External_Status__c);
        System.assertNotEquals(null, subscription.Last_Sync_DateTime__c);

        System.assertEquals(
            'Retired',
            [SELECT Status FROM Asset WHERE Id = :fixture.assetRecord.Id].Status
        );
        System.assertEquals(
            'Terminated',
            [
                SELECT Status
                FROM Contract
                WHERE Id = :fixture.contractRecord.Id
            ].Status
        );

        Engagement__c engagement = [
            SELECT Status__c, Early_Termination_Fee__c, Breach_Amount__c
            FROM Engagement__c
            WHERE Id = :fixture.engagement.Id
        ];
        System.assertEquals('Breached', engagement.Status__c);
        System.assertEquals(35.99, engagement.Early_Termination_Fee__c);
        System.assertEquals(35.99, engagement.Breach_Amount__c);

        System.assertEquals(
            'Churned',
            [SELECT Customer_Status__c FROM Account WHERE Id = :fixture.account.Id]
                .Customer_Status__c
        );
        System.assertEquals(
            'Closed',
            [SELECT Status FROM Case WHERE Id = :fixture.caseRecord.Id].Status
        );

        Customer_Request__c request = [
            SELECT Status__c, Completed_On__c, Resolution_Summary__c
            FROM Customer_Request__c
            WHERE Id = :fixture.request.Id
        ];
        System.assertEquals('Completed', request.Status__c);
        System.assertNotEquals(null, request.Completed_On__c);
        System.assert(request.Resolution_Summary__c.contains('fulfilled'));

        List<Integration_Log__c> logs = [
            SELECT Status__c, Operation__c
            FROM Integration_Log__c
            WHERE Subscription__c = :fixture.subscription.Id
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
        System.assertEquals('cancelSubscription', logs[0].Operation__c);
    }

    @IsTest
    static void accountStaysSubscribedWhenAnotherLineIsActive() {
        Fixture fixture = createFixture(Date.today().addDays(-1), 0);
        createActiveLine(fixture.account, fixture.contact, fixture.product);

        Test.startTest();
        List<CancellationFulfilmentResult> results =
            CancellationFulfilmentService.fulfil(
                loadRequests(new Set<Id>{ fixture.request.Id })
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(
            'Subscribed',
            [SELECT Customer_Status__c FROM Account WHERE Id = :fixture.account.Id]
                .Customer_Status__c
        );
    }

    @IsTest
    static void bssFailureRollsBackEverySalesforceWrite() {
        Fixture fixture = createFixture(Date.today().addDays(-1), 35.99);
        CancellationBssClient.setGateway(new FailingGateway());

        Test.startTest();
        List<CancellationFulfilmentResult> results =
            CancellationFulfilmentService.fulfil(
                loadRequests(new Set<Id>{ fixture.request.Id })
            );
        Test.stopTest();
        CancellationBssClient.setGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('BSS unavailable'));
        System.assertEquals(
            'PendingCancellation',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].Status__c
        );
        System.assertEquals(
            'Registered',
            [SELECT Status FROM Asset WHERE Id = :fixture.assetRecord.Id].Status
        );
        System.assertEquals(
            'Activated',
            [
                SELECT Status
                FROM Contract
                WHERE Id = :fixture.contractRecord.Id
            ].Status
        );
        System.assertEquals(
            'In_Fulfilment',
            [
                SELECT Status__c
                FROM Customer_Request__c
                WHERE Id = :fixture.request.Id
            ].Status__c
        );
        List<Integration_Log__c> logs = [
            SELECT Status__c, Error_Message__c
            FROM Integration_Log__c
            WHERE Subscription__c = :fixture.subscription.Id
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failure', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('BSS unavailable'));
    }

    @IsTest
    static void completedRequestIsNotFulfilledTwice() {
        Fixture fixture = createFixture(Date.today().addDays(-1), 0);
        CancellationFulfilmentService.fulfil(
            loadRequests(new Set<Id>{ fixture.request.Id })
        );
        CountingGateway counting = new CountingGateway();
        CancellationBssClient.setGateway(counting);

        Test.startTest();
        List<CancellationFulfilmentResult> results =
            CancellationFulfilmentService.fulfil(
                loadRequests(new Set<Id>{ fixture.request.Id })
            );
        Test.stopTest();
        CancellationBssClient.setGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('not ready'));
        System.assertEquals(0, counting.calls);
    }

    @IsTest
    static void futureEffectiveDateIsSkipped() {
        Fixture fixture = createFixture(Date.today().addDays(30), 0);
        CountingGateway counting = new CountingGateway();
        CancellationBssClient.setGateway(counting);

        Test.startTest();
        List<CancellationFulfilmentResult> results =
            CancellationFulfilmentService.fulfil(
                loadRequests(new Set<Id>{ fixture.request.Id })
            );
        Test.stopTest();
        CancellationBssClient.setGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('not been reached'));
        System.assertEquals(0, counting.calls);
    }

    @IsTest
    static void scheduledBatchSelectsOnlyDueRequests() {
        Fixture due = createFixture(Date.today().addDays(-1), 0);
        Fixture future = createFixture(Date.today().addDays(30), 0);

        Test.startTest();
        Database.executeBatch(new CancellationFulfilmentBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Cancelled',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :due.subscription.Id
            ].Status__c
        );
        System.assertEquals(
            'PendingCancellation',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :future.subscription.Id
            ].Status__c
        );
    }

    @IsTest
    static void bulkFulfilmentProcessesEveryRequest() {
        Fixture first = createFixture(Date.today().addDays(-1), 0);
        Fixture second = createFixture(Date.today().addDays(-1), 10);

        Test.startTest();
        List<CancellationFulfilmentResult> results =
            CancellationFulfilmentService.fulfil(
                loadRequests(
                    new Set<Id>{ first.request.Id, second.request.Id }
                )
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE
                    Id IN :new Set<Id>{
                        first.subscription.Id,
                        second.subscription.Id
                    }
                    AND Status__c = 'Cancelled'
            ]
        );
    }

    private static List<Customer_Request__c> loadRequests(Set<Id> requestIds) {
        return [
            SELECT
                Id,
                Account__c,
                Account__r.Name,
                Case__c,
                Subscription__c,
                Cancellation_Effective_Date__c,
                Calculated_Fee__c,
                Status__c,
                Subscription__r.Name,
                Subscription__r.Status__c,
                Subscription__r.Account__c,
                Subscription__r.Asset__c,
                Subscription__r.Contract__c,
                Subscription__r.Engagement__c,
                Subscription__r.Service_Line_Type__c,
                Subscription__r.Product__r.ATS_Product_Code__c
            FROM Customer_Request__c
            WHERE Id IN :requestIds
        ];
    }

    private static Fixture createFixture(Date effectiveDate, Decimal fee) {
        uniqueIndex++;
        String suffix = String.valueOf(uniqueIndex);
        Fixture fixture = new Fixture();
        fixture.account = new Account(
            Name = 'Cancellation Fulfilment Test ' + suffix,
            Segment__c = 'Consumer',
            BillingPostalCode = '750' + suffix,
            Customer_Status__c = 'Subscribed'
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'Fulfilment',
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        fixture.product = new Product2(
            Name = 'Cancellation Fulfilment Plan ' + suffix,
            ProductCode = 'CAN_FULFIL' + suffix,
            ATS_Product_Code__c = 'PC_CAN_FULFIL' + suffix,
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            Data_GB__c = 20,
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = true,
            Requires_Commitment__c = false
        );
        insert fixture.product;

        fixture.assetRecord = new Asset(
            Name = 'Cancellation Fulfilment Asset ' + suffix,
            AccountId = fixture.account.Id,
            Status = 'Registered',
            Service_Line_Type__c = 'Mobile'
        );
        insert fixture.assetRecord;

        fixture.contractRecord = new Contract(
            AccountId = fixture.account.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-6),
            ContractTerm = 24,
            Signed_On__c = Date.today().addMonths(-6),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert fixture.contractRecord;
        fixture.contractRecord.Status = 'Activated';
        update fixture.contractRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = fixture.assetRecord.Id,
            Contract__c = fixture.contractRecord.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = fixture.product.Id,
            Monthly_Amount__c = 39.99,
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Start_Date__c = Date.today().addMonths(-6),
            End_Date__c = Date.today().addMonths(18),
            Duration_Months__c = 24,
            Monthly_Amount__c = 39.99,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = 'Active';
        update fixture.subscription;

        fixture.subscription.Status__c = 'PendingCancellation';
        update fixture.subscription;

        fixture.caseRecord = new Case(
            AccountId = fixture.account.Id,
            ContactId = fixture.contact.Id,
            Subject = 'Cancellation fulfilment test ' + suffix,
            Status = 'New',
            Origin = 'Phone',
            Priority = 'Medium'
        );
        insert fixture.caseRecord;

        fixture.request = new Customer_Request__c(
            Account__c = fixture.account.Id,
            Contact__c = fixture.contact.Id,
            Subscription__c = fixture.subscription.Id,
            Impacted_Engagement__c = fixture.engagement.Id,
            Case__c = fixture.caseRecord.Id,
            Request_Type__c = 'Cancellation',
            Channel__c = 'Advisor',
            Cancellation_Reason__c = 'Price',
            Cancellation_Effective_Date__c = effectiveDate,
            Calculated_Fee__c = fee,
            Due_Date__c = effectiveDate,
            Status__c = 'In_Fulfilment'
        );
        insert fixture.request;
        return fixture;
    }

    private static void createActiveLine(
        Account account,
        Contact contact,
        Product2 product
    ) {
        Asset assetRecord = new Asset(
            Name = 'Remaining Active Asset',
            AccountId = account.Id,
            Status = 'Installed',
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;
        Subscription__c subscription = new Subscription__c(
            Account__c = account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = product.Id,
            Monthly_Amount__c = 19.99,
            Status__c = 'PendingActivation'
        );
        insert subscription;
        subscription.Status__c = 'Active';
        update subscription;
    }
}
