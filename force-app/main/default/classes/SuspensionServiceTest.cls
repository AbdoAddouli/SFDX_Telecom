@IsTest
private class SuspensionServiceTest {
    private static Integer uniqueIndex = 0;

    private class Fixture {
        Account account;
        Contact contact;
        Product2 product;
        Asset assetRecord;
        Contract contractRecord;
        Subscription__c subscription;
        Engagement__c engagement;
    }

    private class FailingGateway implements BssSuspensionGateway {
        public List<BssProvisioningResponse> suspend(
            List<BssProvisioningRequest> requests
        ) {
            return failure(requests);
        }

        public List<BssProvisioningResponse> resume(
            List<BssProvisioningRequest> requests
        ) {
            return failure(requests);
        }

        private List<BssProvisioningResponse> failure(
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

    private class CountingGateway implements BssSuspensionGateway {
        public Integer calls = 0;
        private final BssSuspensionGateway delegate =
            new SimulatedBssProvisioningGateway();

        public List<BssProvisioningResponse> suspend(
            List<BssProvisioningRequest> requests
        ) {
            calls++;
            return delegate.suspend(requests);
        }

        public List<BssProvisioningResponse> resume(
            List<BssProvisioningRequest> requests
        ) {
            calls++;
            return delegate.resume(requests);
        }
    }

    @IsTest
    static void suspendLeavesContractAndEngagementUntouched() {
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());
        Fixture fixture = createFixture(false);

        Test.startTest();
        List<SuspensionService.SuspensionResult> results =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{
                    input(fixture, SuspensionPolicy.ACTION_SUSPEND)
                }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(SuspensionPolicy.STATUS_COMPLETED, results[0].status);
        System.assertEquals(SuspensionPolicy.ACTION_SUSPEND, results[0].action);

        Subscription__c subscription = [
            SELECT Status__c, External_Status__c, Last_Sync_DateTime__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Suspended', subscription.Status__c);
        System.assertEquals('Suspended', subscription.External_Status__c);
        System.assertNotEquals(null, subscription.Last_Sync_DateTime__c);

        System.assertEquals(
            'Activated',
            [SELECT Status FROM Contract WHERE Id = :fixture.contractRecord.Id]
                .Status
        );
        Engagement__c engagement = [
            SELECT Status__c, Monthly_Amount__c
            FROM Engagement__c
            WHERE Id = :fixture.engagement.Id
        ];
        System.assertEquals('Active', engagement.Status__c);
        System.assertEquals(39.99, engagement.Monthly_Amount__c);

        Customer_Request__c request = [
            SELECT Status__c, Case__c, Resolution_Summary__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assertEquals('Completed', request.Status__c);
        System.assert(request.Resolution_Summary__c.contains('unchanged'));
        System.assertEquals(
            'Closed',
            [SELECT Status FROM Case WHERE Id = :request.Case__c].Status
        );

        List<Integration_Log__c> logs = [
            SELECT Status__c, Operation__c
            FROM Integration_Log__c
            WHERE Subscription__c = :fixture.subscription.Id
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
        System.assertEquals('suspendSubscription', logs[0].Operation__c);
    }

    @IsTest
    static void unfreezeReturnsSuspendedLineToActive() {
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());
        Fixture fixture = createFixture(true);

        Test.startTest();
        List<SuspensionService.SuspensionResult> results =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{
                    input(fixture, SuspensionPolicy.ACTION_UNFREEZE)
                }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(SuspensionPolicy.ACTION_UNFREEZE, results[0].action);
        Subscription__c subscription = [
            SELECT Status__c, External_Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Active', subscription.Status__c);
        System.assertEquals('Active', subscription.External_Status__c);
        System.assertEquals(
            'resumeSubscription',
            [
                SELECT Operation__c
                FROM Integration_Log__c
                WHERE Subscription__c = :fixture.subscription.Id
                LIMIT 1
            ].Operation__c
        );
    }

    @IsTest
    static void bssFailureRollsBackStatusChangeOnly() {
        Fixture fixture = createFixture(false);
        SuspensionBssClient.setGateway(new FailingGateway());

        Test.startTest();
        List<SuspensionService.SuspensionResult> results =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{
                    input(fixture, SuspensionPolicy.ACTION_SUSPEND)
                }
            );
        Test.stopTest();
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('BSS unavailable'));
        System.assertEquals(
            'Active',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].Status__c
        );
        System.assertEquals(
            'Activated',
            [SELECT Status FROM Contract WHERE Id = :fixture.contractRecord.Id]
                .Status
        );
        System.assertEquals(
            'Approved',
            [
                SELECT Status__c
                FROM Customer_Request__c
                WHERE Id = :results[0].requestId
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
    static void goodwillWaiverWaitsForApprovalWithoutCallingBss() {
        Fixture fixture = createFixture(false);
        CountingGateway counting = new CountingGateway();
        SuspensionBssClient.setGateway(counting);
        SuspensionService.SuspensionInput input = input(
            fixture,
            SuspensionPolicy.ACTION_SUSPEND
        );
        input.goodwillWaiver = true;
        input.goodwillJustification = 'VIP escalation';

        Test.startTest();
        List<SuspensionService.SuspensionResult> results =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{ input }
            );
        Test.stopTest();
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());

        System.assertEquals(true, results[0].success);
        System.assertEquals(
            SuspensionPolicy.STATUS_AWAITING,
            results[0].status
        );
        System.assertEquals(0, counting.calls);
        System.assertEquals(
            'Active',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].Status__c
        );
    }

    @IsTest
    static void approvedUnfreezeRequestIsAppliedByManager() {
        Fixture fixture = createFixture(true);
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());
        SuspensionService.SuspensionInput input = input(
            fixture,
            SuspensionPolicy.ACTION_UNFREEZE
        );
        input.goodwillWaiver = true;
        input.goodwillJustification = 'Priority restore';
        SuspensionService.SuspensionResult submitted =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{ input }
            )[0];

        Customer_Request__c request = [
            SELECT Status__c
            FROM Customer_Request__c
            WHERE Id = :submitted.requestId
        ];
        System.assertEquals(SuspensionPolicy.STATUS_AWAITING, request.Status__c);
        request.Status__c = SuspensionPolicy.STATUS_APPROVED;
        update request;

        SuspensionApprovalService.ApprovalInput approval =
            new SuspensionApprovalService.ApprovalInput();
        approval.requestId = request.Id;

        Test.startTest();
        List<SuspensionService.SuspensionResult> approved =
            SuspensionApprovalService.apply(
                new List<SuspensionApprovalService.ApprovalInput>{ approval }
            );
        Test.stopTest();

        System.assertEquals(true, approved[0].success);
        System.assertEquals('Active', [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ].Status__c);
        System.assertEquals(
            'Completed',
            [
                SELECT Status__c
                FROM Customer_Request__c
                WHERE Id = :request.Id
            ].Status__c
        );
    }

    @IsTest
    static void mixedBatchAppliesSuspendAndUnfreezeTogether() {
        Fixture first = createFixture(false);
        Fixture second = createFixture(true);
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());

        Test.startTest();
        List<SuspensionService.SuspensionResult> results =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{
                    input(first, SuspensionPolicy.ACTION_SUSPEND),
                    input(second, SuspensionPolicy.ACTION_UNFREEZE)
                }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
        System.assertEquals(
            'Suspended',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :first.subscription.Id
            ].Status__c
        );
        System.assertEquals(
            'Active',
            [
                SELECT Status__c
                FROM Subscription__c
                WHERE Id = :second.subscription.Id
            ].Status__c
        );
    }

    @IsTest
    static void invalidStatusIsRejectedBeforeIntake() {
        Fixture fixture = createFixture(true);
        CountingGateway counting = new CountingGateway();
        SuspensionBssClient.setGateway(counting);

        Test.startTest();
        List<SuspensionService.SuspensionResult> results =
            SuspensionService.apply(
                new List<SuspensionService.SuspensionInput>{
                    input(fixture, SuspensionPolicy.ACTION_SUSPEND)
                }
            );
        Test.stopTest();
        SuspensionBssClient.setGateway(new SimulatedBssProvisioningGateway());

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('active line'));
        System.assertEquals(0, counting.calls);
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Customer_Request__c
                WHERE Subscription__c = :fixture.subscription.Id
            ]
        );
    }

    private static SuspensionService.SuspensionInput input(
        Fixture fixture,
        String action
    ) {
        SuspensionService.SuspensionInput input =
            new SuspensionService.SuspensionInput();
        input.action = action;
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.channel = 'Advisor';
        input.customerComment = 'Temporary network fix';
        input.priority = 'Normal';
        return input;
    }

    private static Fixture createFixture(Boolean suspended) {
        uniqueIndex++;
        String suffix = String.valueOf(uniqueIndex);
        Fixture fixture = new Fixture();
        fixture.account = new Account(
            Name = 'Suspension Test ' + suffix,
            Segment__c = 'Consumer',
            BillingPostalCode = '750' + suffix,
            Customer_Status__c = 'Subscribed'
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'SuspendTest',
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        fixture.product = new Product2(
            Name = 'Suspension Test Plan ' + suffix,
            ProductCode = 'SUS_TEST' + suffix,
            ATS_Product_Code__c = 'PC_SUS_TEST' + suffix,
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
            Name = 'Suspension Test Asset ' + suffix,
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
        fixture.subscription.Status__c = SubscriptionStateMachine.ACTIVE;
        update fixture.subscription;

        if (suspended == true) {
            fixture.subscription.Status__c = SubscriptionStateMachine.SUSPENDED;
            update fixture.subscription;
        }
        return fixture;
    }
}
