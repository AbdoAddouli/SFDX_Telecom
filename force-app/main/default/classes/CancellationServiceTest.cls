@IsTest
private class CancellationServiceTest {
    private class Fixture {
        Account account;
        Contact contact;
        Subscription__c subscription;
        Engagement__c engagement;
    }

    @IsTest
    static void compliantCancellationSchedulesPendingCancellation() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        CancellationService.CancellationInput input = input(fixture);

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.apply(
                new List<CancellationService.CancellationInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('In_Fulfilment', results[0].status);
        System.assertEquals(fixture.subscription.Id, results[0].subscriptionId);
        System.assertEquals(0, results[0].calculatedFee.intValue());
        System.assert(results[0].message.contains('service continues'));

        Subscription__c subscription = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('PendingCancellation', subscription.Status__c);

        Customer_Request__c request = [
            SELECT Status__c, Due_Date__c, Resolution_Summary__c, Case__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assertEquals('In_Fulfilment', request.Status__c);
        System.assertEquals(Date.today().addDays(30), request.Due_Date__c);
        System.assert(request.Resolution_Summary__c.contains('service continues'));
        System.assertNotEquals(null, request.Case__c);

        Case linkedCase = [SELECT Status FROM Case WHERE Id = :request.Case__c];
        System.assertEquals('New', linkedCase.Status);
    }

    @IsTest
    static void shortNoticeIsRejectedBeforeIntake() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        CancellationService.CancellationInput input = input(fixture);
        input.cancellationEffectiveDate = Date.today().addDays(29);

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.apply(
                new List<CancellationService.CancellationInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('30 days notice'));
        System.assertEquals(null, results[0].requestId);
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Customer_Request__c
                WHERE Subscription__c = :fixture.subscription.Id
            ]
        );

        Subscription__c subscription = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Active', subscription.Status__c);
    }

    @IsTest
    static void goodwillWaiverRequiresJustification() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        CancellationService.CancellationInput input = input(fixture);
        input.goodwillWaiver = true;
        input.goodwillJustification = null;

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.apply(
                new List<CancellationService.CancellationInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Goodwill justification'));
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Customer_Request__c
                WHERE Subscription__c = :fixture.subscription.Id
            ]
        );
    }

    @IsTest
    static void paidCancellationWaitsForApprovalThenSchedules() {
        Fixture fixture = createFixture(-18, 6, 39.99);
        CancellationService.CancellationInput input = input(fixture);

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.apply(
                new List<CancellationService.CancellationInput>{ input }
            );

        System.assertEquals(true, results[0].success);
        System.assertEquals('Awaiting_Approval', results[0].status);
        System.assert(results[0].calculatedFee > 0);

        Subscription__c awaiting = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Active', awaiting.Status__c);

        Customer_Request__c request = [
            SELECT Id, Status__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assertEquals('Awaiting_Approval', request.Status__c);
        request.Status__c = 'Approved';
        update request;

        CancellationApprovalService.ApprovalInput approval =
            new CancellationApprovalService.ApprovalInput();
        approval.requestId = request.Id;

        List<CancellationService.CancellationResult> approved =
            CancellationApprovalService.apply(
                new List<CancellationApprovalService.ApprovalInput>{ approval }
            );
        Test.stopTest();

        System.assertEquals(true, approved[0].success);
        System.assertEquals('In_Fulfilment', approved[0].status);

        Subscription__c scheduled = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('PendingCancellation', scheduled.Status__c);

        Customer_Request__c scheduledRequest = [
            SELECT Status__c
            FROM Customer_Request__c
            WHERE Id = :request.Id
        ];
        System.assertEquals('In_Fulfilment', scheduledRequest.Status__c);
    }

    @IsTest
    static void approvalSchedulingIsIdempotent() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        LifecycleRequestService.RequestInput intakeInput =
            new LifecycleRequestService.RequestInput();
        intakeInput.requestType = 'Cancellation';
        intakeInput.accountId = fixture.account.Id;
        intakeInput.contactId = fixture.contact.Id;
        intakeInput.subscriptionId = fixture.subscription.Id;
        intakeInput.channel = 'Advisor';
        intakeInput.cancellationReason = 'Price';
        intakeInput.cancellationEffectiveDate = Date.today().addDays(30);
        Id requestId = LifecycleRequestService.createRequests(
            new List<LifecycleRequestService.RequestInput>{ intakeInput }
        )[0].requestId;

        CancellationApprovalService.ApprovalInput approval =
            new CancellationApprovalService.ApprovalInput();
        approval.requestId = requestId;
        List<CancellationApprovalService.ApprovalInput> approvals =
            new List<CancellationApprovalService.ApprovalInput>{ approval };

        Test.startTest();
        List<CancellationService.CancellationResult> first =
            CancellationApprovalService.apply(approvals);
        List<CancellationService.CancellationResult> second =
            CancellationApprovalService.apply(approvals);
        Test.stopTest();

        System.assertEquals(true, first[0].success);
        System.assertEquals('In_Fulfilment', first[0].status);
        System.assertEquals(true, second[0].success);
        System.assert(second[0].message.contains('already scheduled'));

        Subscription__c subscription = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('PendingCancellation', subscription.Status__c);
    }

    private static CancellationService.CancellationInput input(Fixture fixture) {
        CancellationService.CancellationInput input =
            new CancellationService.CancellationInput();
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.channel = 'Advisor';
        input.cancellationReason = 'Price';
        input.cancellationEffectiveDate = Date.today().addDays(30);
        input.customerComment = 'Moving to another provider';
        input.priority = 'Normal';
        return input;
    }

    private static Fixture createFixture(
        Integer startMonthsAgo,
        Integer endMonthsAhead,
        Decimal monthlyAmount
    ) {
        Fixture fixture = new Fixture();
        fixture.account = new Account(
            Name = 'Cancellation Test',
            Segment__c = 'Consumer',
            BillingPostalCode = '75001'
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'Canceller',
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        Product2 product = new Product2(
            Name = 'Cancellation Test Plan',
            ProductCode = 'CAN_TEST',
            ATS_Product_Code__c = 'PC_CAN_TEST',
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            Data_GB__c = 20,
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = true,
            Requires_Commitment__c = false
        );
        insert product;

        Asset assetRecord = new Asset(
            Name = 'Cancellation Test Asset',
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = product.Id,
            Monthly_Amount__c = monthlyAmount,
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Start_Date__c = Date.today().addMonths(startMonthsAgo),
            End_Date__c = Date.today().addMonths(endMonthsAhead),
            Duration_Months__c = 24,
            Monthly_Amount__c = monthlyAmount,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = 'Active';
        update fixture.subscription;
        return fixture;
    }
}
