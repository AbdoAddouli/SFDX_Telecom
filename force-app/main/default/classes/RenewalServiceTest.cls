@IsTest
private class RenewalServiceTest {
    private static Integer uniqueIndex = 0;

    private class Fixture {
        Account account;
        Contact contact;
        Subscription__c subscription;
        Engagement__c engagement;
        Product2 currentProduct;
        Product2 targetProduct;
        Contract contractRecord;
    }

    @IsTest
    static void renewSameTermsExpiresOldEngagementAndCreatesNewOne() {
        Fixture fixture = createFixture(45);

        Test.startTest();
        List<RenewalService.RenewalResult> results =
            RenewalService.apply(
                new List<RenewalService.RenewalInput>{
                    input(fixture, RenewalPolicy.DECISION_SAME_TERMS)
                }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(RenewalPolicy.STATUS_COMPLETED, results[0].status);
        System.assert(results[0].monthlyAmount > 0);

        System.assertEquals(
            'Expired',
            [
                SELECT Status__c
                FROM Engagement__c
                WHERE Id = :fixture.engagement.Id
            ].Status__c
        );
        Engagement__c renewed = [
            SELECT
                Id,
                Status__c,
                Root_Engagement__c,
                Monthly_Amount__c,
                Start_Date__c
            FROM Engagement__c
            WHERE Root_Engagement__c = :fixture.engagement.Id
        ];
        System.assertEquals('Active', renewed.Status__c);
        System.assertEquals(results[0].monthlyAmount, renewed.Monthly_Amount__c);

        Subscription__c line = [
            SELECT
                Product__c,
                Monthly_Amount__c,
                Engagement__c,
                Root_Engagement__c,
                Billing_Start_Date__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals(fixture.currentProduct.Id, line.Product__c);
        System.assertEquals(results[0].monthlyAmount, line.Monthly_Amount__c);
        System.assertEquals(renewed.Id, line.Engagement__c);
        System.assertEquals(fixture.engagement.Id, line.Root_Engagement__c);
        System.assertNotEquals(null, line.Billing_Start_Date__c);

        System.assertEquals(
            true,
            [
                SELECT Auto_Renew__c
                FROM Contract
                WHERE Id = :fixture.contractRecord.Id
            ].Auto_Renew__c
        );
        assertRequestCompleted(results[0]);
    }

    @IsTest
    static void renewNewPlanUsesCataloguePriceForNewEngagement() {
        Fixture fixture = createFixture(30);
        RenewalService.RenewalInput input = input(
            fixture,
            RenewalPolicy.DECISION_NEW_PLAN
        );
        input.targetProductId = fixture.targetProduct.Id;

        Test.startTest();
        List<RenewalService.RenewalResult> results =
            RenewalService.apply(
                new List<RenewalService.RenewalInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assert(results[0].monthlyAmount > 0);
        System.assertEquals(
            fixture.targetProduct.Id,
            [
                SELECT Product__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].Product__c
        );
        Customer_Request__c request = [
            SELECT Fee_Breakdown__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assert(
            request.Fee_Breakdown__c.contains(
                RenewalPolicy.QUOTE_MARKER + results[0].monthlyAmount
            )
        );
    }

    @IsTest
    static void letLapseAppliesMonthlyRolloverWithoutNewEngagement() {
        Fixture fixture = createFixture(7);
        Decimal originalAmount = fixture.subscription.Monthly_Amount__c;
        RenewalService.RenewalInput input = input(
            fixture,
            RenewalPolicy.DECISION_LAPSE
        );

        Test.startTest();
        List<RenewalService.RenewalResult> results =
            RenewalService.apply(
                new List<RenewalService.RenewalInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('monthly rollover'));
        System.assertEquals(
            'Expired',
            [
                SELECT Status__c
                FROM Engagement__c
                WHERE Id = :fixture.engagement.Id
            ].Status__c
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Engagement__c
                WHERE Root_Engagement__c = :fixture.engagement.Id
            ]
        );
        Subscription__c line = [
            SELECT Billing_End_Date__c, Monthly_Amount__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals(Date.today().addMonths(1), line.Billing_End_Date__c);
        System.assertEquals(originalAmount, line.Monthly_Amount__c);
        System.assertEquals(
            false,
            [
                SELECT Auto_Renew__c
                FROM Contract
                WHERE Id = :fixture.contractRecord.Id
            ].Auto_Renew__c
        );
    }

    @IsTest
    static void cancelEarlyIsRejectedWithoutCreatingARequest() {
        Fixture fixture = createFixture(30);

        Test.startTest();
        List<RenewalService.RenewalResult> results =
            RenewalService.apply(
                new List<RenewalService.RenewalInput>{
                    input(fixture, RenewalPolicy.DECISION_CANCEL)
                }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assertEquals(RenewalPolicy.STATUS_REJECTED, results[0].status);
        System.assert(results[0].message.contains('cancellation flow'));
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
    static void inFlightRenewalBlocksDuplicateRequest() {
        Fixture fixture = createFixture(30);
        LifecycleRequestService.RequestInput intake =
            new LifecycleRequestService.RequestInput();
        intake.requestType = RenewalPolicy.REQUEST_TYPE;
        intake.accountId = fixture.account.Id;
        intake.contactId = fixture.contact.Id;
        intake.subscriptionId = fixture.subscription.Id;
        intake.channel = 'Advisor';
        LifecycleRequestService.createRequests(
            new List<LifecycleRequestService.RequestInput>{ intake }
        );

        Test.startTest();
        List<RenewalService.RenewalResult> results =
            RenewalService.apply(
                new List<RenewalService.RenewalInput>{
                    input(fixture, RenewalPolicy.DECISION_SAME_TERMS)
                }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('already in flight'));
    }

    private static void assertRequestCompleted(
        RenewalService.RenewalResult result
    ) {
        Customer_Request__c request = [
            SELECT Status__c, Case__c, Resolution_Summary__c
            FROM Customer_Request__c
            WHERE Id = :result.requestId
        ];
        System.assertEquals('Completed', request.Status__c);
        System.assert(request.Resolution_Summary__c.contains('Expired'));
        System.assertEquals(
            'Closed',
            [SELECT Status FROM Case WHERE Id = :request.Case__c].Status
        );
    }

    private static RenewalService.RenewalInput input(
        Fixture fixture,
        String decision
    ) {
        RenewalService.RenewalInput input =
            new RenewalService.RenewalInput();
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.decision = decision;
        input.channel = 'Advisor';
        input.customerComment = 'Renewal handled by advisor';
        input.priority = 'Normal';
        return input;
    }

    private static Fixture createFixture(Integer daysToRenewal) {
        uniqueIndex++;
        String suffix = String.valueOf(uniqueIndex);
        Fixture fixture = new Fixture();
        fixture.account = new Account(
            Name = 'Renewal Test ' + suffix,
            Segment__c = 'Consumer',
            BillingPostalCode = '75001'
        );
        insert fixture.account;

        Pricebook2 pricebook = new Pricebook2(
            Name = 'Renewal Test Pricebook ' + suffix,
            IsActive = true
        );
        insert pricebook;

        fixture.contact = new Contact(
            LastName = 'Renewer',
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        fixture.currentProduct = product('Current Plan ' + suffix, 'PC_RENEW_C');
        fixture.targetProduct = product('Target Plan ' + suffix, 'PC_RENEW_T');
        insert new List<Product2>{ fixture.currentProduct, fixture.targetProduct };
        insert new List<PricebookEntry>{
            pricebookEntry(
                Test.getStandardPricebookId(),
                fixture.currentProduct.Id
            ),
            pricebookEntry(
                Test.getStandardPricebookId(),
                fixture.targetProduct.Id
            )
        };
        insert new List<PricebookEntry>{
            pricebookEntry(pricebook.Id, fixture.currentProduct.Id),
            pricebookEntry(pricebook.Id, fixture.targetProduct.Id)
        };

        Asset assetRecord = new Asset(
            Name = 'Renewal Asset ' + suffix,
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        fixture.contractRecord = new Contract(
            AccountId = fixture.account.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-18),
            ContractTerm = 24,
            Auto_Renew__c = false,
            Pricebook2Id = pricebook.Id
        );
        insert fixture.contractRecord;
        fixture.contractRecord.Status = 'Activated';
        update fixture.contractRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = fixture.contact.Id,
            Contract__c = fixture.contractRecord.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = fixture.currentProduct.Id,
            Monthly_Amount__c = 39.99,
            Billing_Start_Date__c = Date.today().addMonths(-18),
            Billing_End_Date__c = Date.today().addDays(daysToRenewal),
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Contract__c = fixture.contractRecord.Id,
            Asset__c = assetRecord.Id,
            Start_Date__c = Date.today().addMonths(-18),
            End_Date__c = Date.today().addDays(daysToRenewal),
            Duration_Months__c = 24,
            Monthly_Amount__c = 39.99,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = SubscriptionStateMachine.ACTIVE;
        update fixture.subscription;
        return fixture;
    }

    private static Product2 product(String name, String code) {
        return new Product2(
            Name = name,
            ProductCode = code,
            ATS_Product_Code__c = code,
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            Data_GB__c = 20,
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = true,
            Requires_Commitment__c = false
        );
    }

    private static PricebookEntry pricebookEntry(
        Id pricebookId,
        Id productId
    ) {
        return new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            UnitPrice = 50,
            IsActive = true,
            UseStandardPrice = false
        );
    }
}
