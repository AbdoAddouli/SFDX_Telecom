@IsTest
private class PlanChangeServiceTest {
    private class Fixture {
        Account account;
        Contact contact;
        Subscription__c subscription;
        Engagement__c engagement;
        Product2 currentProduct;
        Product2 targetProduct;
    }

    @IsTest
    static void compliantPlanChangeSupersedesOldLineAndKeepsEngagement() {
        Fixture fixture = createFixture(-18, 6, 'Active');

        Test.startTest();
        List<PlanChangeService.PlanChangeResult> results =
            PlanChangeService.apply(new List<PlanChangeService.PlanChangeInput>{ input(fixture) });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('Completed', results[0].status);
        System.assertNotEquals(null, results[0].subscriptionId);
        System.assert(results[0].monthlyAmount > 0);

        Subscription__c oldLine = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Superseded', oldLine.Status__c);

        Subscription__c newLine = [
            SELECT
                Id,
                Status__c,
                Parent_Subscription__c,
                Engagement__c,
                Product__c,
                Monthly_Amount__c
            FROM Subscription__c
            WHERE Id = :results[0].subscriptionId
        ];
        System.assertEquals('Active', newLine.Status__c);
        System.assertEquals(fixture.subscription.Id, newLine.Parent_Subscription__c);
        System.assertEquals(fixture.engagement.Id, newLine.Engagement__c);
        System.assertEquals(fixture.targetProduct.Id, newLine.Product__c);
        System.assertEquals(results[0].monthlyAmount, newLine.Monthly_Amount__c);

        Customer_Request__c request = [
            SELECT Status__c, Fee_Breakdown__c, Case__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assertEquals('Completed', request.Status__c);
        System.assert(request.Fee_Breakdown__c.contains('New monthly amount: ' + results[0].monthlyAmount));

        Case linkedCase = [SELECT Status FROM Case WHERE Id = :request.Case__c];
        System.assertEquals('Closed', linkedCase.Status);
    }

    @IsTest
    static void ineligibleEngagementIsRejectedWithoutSuperseding() {
        Fixture fixture = createFixture(-24, -1, 'Expired');

        Test.startTest();
        List<PlanChangeService.PlanChangeResult> results =
            PlanChangeService.apply(new List<PlanChangeService.PlanChangeInput>{ input(fixture) });
        Test.stopTest();

        System.assertEquals('Rejected', results[0].status);
        System.assert(results[0].message.contains('engagement'));

        Subscription__c oldLine = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals('Active', oldLine.Status__c);
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Parent_Subscription__c = :fixture.subscription.Id
            ]
        );

        Customer_Request__c request = [
            SELECT Status__c, Rejection_Reason__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assertEquals('Rejected', request.Status__c);
        System.assertNotEquals(null, request.Rejection_Reason__c);
    }

    @IsTest
    static void applyApprovedIsIdempotent() {
        Fixture fixture = createFixture(-18, 6, 'Active');
        LifecycleRequestService.RequestInput intakeInput =
            new LifecycleRequestService.RequestInput();
        intakeInput.requestType = 'PlanChange';
        intakeInput.accountId = fixture.account.Id;
        intakeInput.contactId = fixture.contact.Id;
        intakeInput.subscriptionId = fixture.subscription.Id;
        intakeInput.channel = 'Advisor';
        Id requestId = LifecycleRequestService.createRequests(
            new List<LifecycleRequestService.RequestInput>{ intakeInput }
        )[0].requestId;

        Customer_Request__c request = [
            SELECT Id, Status__c, Requested_Product__c, Fee_Breakdown__c
            FROM Customer_Request__c
            WHERE Id = :requestId
        ];
        request.Status__c = 'Approved';
        request.Requested_Product__c = fixture.targetProduct.Id;
        request.Fee_Breakdown__c = 'New monthly amount: 59.99';
        update request;

        PlanChangeService.ApprovalInput approval = new PlanChangeService.ApprovalInput();
        approval.requestId = requestId;
        List<PlanChangeService.ApprovalInput> approvals =
            new List<PlanChangeService.ApprovalInput>{ approval };

        Test.startTest();
        List<PlanChangeService.PlanChangeResult> first =
            PlanChangeService.applyApproved(approvals);
        List<PlanChangeService.PlanChangeResult> second =
            PlanChangeService.applyApproved(approvals);
        Test.stopTest();

        System.assertEquals(true, first[0].success);
        System.assertEquals('Completed', first[0].status);
        System.assertEquals(true, second[0].success);
        System.assert(second[0].message.contains('already applied'));
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Parent_Subscription__c = :fixture.subscription.Id
            ]
        );
    }

    private static PlanChangeService.PlanChangeInput input(Fixture fixture) {
        PlanChangeService.PlanChangeInput input = new PlanChangeService.PlanChangeInput();
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.targetProductId = fixture.targetProduct.Id;
        input.channel = 'Advisor';
        input.commitmentCode = 'NOCOMMIT';
        input.customerComment = 'Upgrade to a faster plan';
        return input;
    }

    private static Fixture createFixture(
        Integer startMonthsAgo,
        Integer endMonthsAhead,
        String engagementStatus
    ) {
        Fixture fixture = new Fixture();
        fixture.account = new Account(
            Name = 'Plan Change Test',
            Segment__c = 'Consumer',
            BillingPostalCode = '75001'
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'Plan Changer',
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        Pricebook2 pricebook = new Pricebook2(
            Name = 'Plan Change Test Pricebook',
            IsActive = true
        );
        insert pricebook;

        fixture.currentProduct = product('Current Plan', 'PC_CURRENT');
        fixture.targetProduct = product('Target Plan', 'PC_TARGET');
        insert new List<Product2>{ fixture.currentProduct, fixture.targetProduct };
        insert new List<PricebookEntry>{
            pricebookEntry(Test.getStandardPricebookId(), fixture.currentProduct.Id),
            pricebookEntry(Test.getStandardPricebookId(), fixture.targetProduct.Id),
            pricebookEntry(pricebook.Id, fixture.currentProduct.Id),
            pricebookEntry(pricebook.Id, fixture.targetProduct.Id)
        };

        Asset assetRecord = new Asset(
            Name = 'Plan Change Asset',
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = fixture.currentProduct.Id,
            Monthly_Amount__c = 39.99,
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Start_Date__c = Date.today().addMonths(startMonthsAgo),
            End_Date__c = Date.today().addMonths(endMonthsAhead),
            Duration_Months__c = 24,
            Monthly_Amount__c = 39.99,
            Status__c = engagementStatus
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = 'Active';
        update fixture.subscription;
        return fixture;
    }

    private static Product2 product(String name, String code) {
        return new Product2(
            Name = name,
            ProductCode = code,
            ATS_Product_Code__c = 'PC_' + code,
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            Data_GB__c = 20,
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = true,
            Requires_Commitment__c = false
        );
    }

    private static PricebookEntry pricebookEntry(Id pricebookId, Id productId) {
        return new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            UnitPrice = 50,
            IsActive = true,
            UseStandardPrice = false
        );
    }
}