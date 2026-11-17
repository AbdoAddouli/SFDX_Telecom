@IsTest
private class LifecycleRequestServiceTest {
    private class Fixture {
        Account account;
        Contact contact;
        Subscription__c subscription;
        Engagement__c engagement;
    }

    @IsTest
    static void actionableRequestCreatesLinkedCaseAndRoutesFeeAboveThreshold() {
        Fixture fixture = createFixture(-18, 6);

        Test.startTest();
        LifecycleRequestService.RequestOutput output = create(
            input('Cancellation', fixture, 'Advisor', false, null)
        );
        Test.stopTest();

        System.assertEquals(true, output.success);
        System.assertNotEquals(null, output.caseId);
        System.assertEquals('Awaiting_Approval', output.status);
        System.assertEquals(35.99, output.fee);

        Customer_Request__c request = [
            SELECT Id, Case__c, Impacted_Engagement__c, Calculated_Fee__c, Status__c
            FROM Customer_Request__c
            WHERE Id = :output.requestId
        ];
        System.assertEquals(output.caseId, request.Case__c);
        System.assertEquals(fixture.engagement.Id, request.Impacted_Engagement__c);
        System.assertEquals(35.99, request.Calculated_Fee__c);

        Case linkedCase = [SELECT Id, Request_Link__c FROM Case WHERE Id = :output.caseId];
        System.assertEquals(request.Id, linkedCase.Request_Link__c);
    }

    @IsTest
    static void zeroFeeRequestIsApproved() {
        Fixture fixture = createFixture(-18, 6);

        Test.startTest();
        LifecycleRequestService.RequestOutput output = create(
            input('PlanChange', fixture, 'Advisor', false, null)
        );
        Test.stopTest();

        System.assertEquals(true, output.success);
        System.assertEquals('Approved', output.status);
        System.assertEquals(0, output.fee);

        Customer_Request__c request = [
            SELECT Approved_By__c, Approved_On__c
            FROM Customer_Request__c
            WHERE Id = :output.requestId
        ];
        System.assertNotEquals(null, request.Approved_By__c);
        System.assertNotEquals(null, request.Approved_On__c);
    }

    @IsTest
    static void infoRequestCreatesNoCase() {
        Fixture fixture = createFixture(0, 24);
        LifecycleRequestService.RequestInput input = new LifecycleRequestService.RequestInput();
        input.requestType = 'Info';
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.channel = 'Advisor';

        Test.startTest();
        LifecycleRequestService.RequestOutput output = create(input);
        Test.stopTest();

        System.assertEquals(true, output.success);
        System.assertEquals(null, output.caseId);
        System.assertEquals('Completed', output.status);

        Customer_Request__c request = [
            SELECT Case__c
            FROM Customer_Request__c
            WHERE Id = :output.requestId
        ];
        System.assertEquals(null, request.Case__c);
    }

    @IsTest
    static void goodwillWaiverRequiresJustification() {
        Fixture fixture = createFixture(-18, 6);

        Test.startTest();
        LifecycleRequestService.RequestOutput output = create(
            input('Cancellation', fixture, 'Advisor', true, null)
        );
        Test.stopTest();

        System.assertEquals(false, output.success);
        System.assert(output.message.contains('Goodwill justification'));
        System.assertEquals(0, [SELECT COUNT() FROM Customer_Request__c]);
    }

    @IsTest
    static void goodwillWaiverWithJustificationRequiresApprovalAndStampsEngagement() {
        Fixture fixture = createFixture(-18, 6);

        Test.startTest();
        LifecycleRequestService.RequestOutput output = create(
            input('Cancellation', fixture, 'Advisor', true, 'Loyalty recovery')
        );
        Test.stopTest();

        System.assertEquals(true, output.success);
        System.assertEquals('Awaiting_Approval', output.status);

        Engagement__c engagement = [
            SELECT Goodwill_Waiver__c, Goodwill_Justification__c
            FROM Engagement__c
            WHERE Id = :fixture.engagement.Id
        ];
        System.assertEquals(true, engagement.Goodwill_Waiver__c);
        System.assertEquals('Loyalty recovery', engagement.Goodwill_Justification__c);
    }

    @IsTest
    static void actionableRequestWithoutSubscriptionIsRejected() {
        Fixture fixture = createFixture(0, 24);
        LifecycleRequestService.RequestInput input = new LifecycleRequestService.RequestInput();
        input.requestType = 'Cancellation';
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.channel = 'Advisor';
        input.cancellationReason = 'Price';

        Test.startTest();
        LifecycleRequestService.RequestOutput output = create(input);
        Test.stopTest();

        System.assertEquals(false, output.success);
        System.assert(output.message.contains('Subscription is required'));
    }

    private static LifecycleRequestService.RequestOutput create(
        LifecycleRequestService.RequestInput input
    ) {
        List<LifecycleRequestService.RequestOutput> outputs =
            LifecycleRequestService.createRequests(
                new List<LifecycleRequestService.RequestInput>{ input }
            );
        System.assertEquals(1, outputs.size());
        return outputs[0];
    }

    private static LifecycleRequestService.RequestInput input(
        String requestType,
        Fixture fixture,
        String channel,
        Boolean waiver,
        String justification
    ) {
        LifecycleRequestService.RequestInput input =
            new LifecycleRequestService.RequestInput();
        input.requestType = requestType;
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.channel = channel;
        input.cancellationReason = requestType == 'Cancellation' ? 'Price' : null;
        input.goodwillWaiver = waiver;
        input.goodwillJustification = justification;
        return input;
    }

    private static Fixture createFixture(
        Integer startMonthsAgo,
        Integer endMonthsAhead
    ) {
        Fixture fixture = new Fixture();
        fixture.account = new Account(Name = 'Lifecycle Intake Test', Segment__c = 'Consumer');
        insert fixture.account;

        fixture.contact = new Contact(LastName = 'Requester', AccountId = fixture.account.Id);
        insert fixture.contact;

        Asset assetRecord = new Asset(
            Name = 'Lifecycle Intake Asset',
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Service_Line_Type__c = 'Mobile',
            Status__c = 'PendingActivation',
            Monthly_Amount__c = 39.99
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Start_Date__c = Date.today().addMonths(startMonthsAgo),
            End_Date__c = Date.today().addMonths(endMonthsAhead),
            Duration_Months__c = 24,
            Monthly_Amount__c = 39.99,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = 'Active';
        update fixture.subscription;
        return fixture;
    }
}
