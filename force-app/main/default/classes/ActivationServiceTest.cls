@IsTest
private class ActivationServiceTest {
    private static final String ACCOUNT_NAME = 'Activation Test Account';
    private static final String BUSINESS_ACCOUNT_NAME =
        'Activation Business Account';
    private static final String CONTACT_LAST_NAME = 'Activation Contact';
    private static final String BUSINESS_CONTACT_LAST_NAME =
        'Activation Business Contact';
    private static final String PRICEBOOK_NAME = 'Activation Test Pricebook';
    private static final String MOBILE_CODE = 'ACT_MOBILE';
    private static final String FIBER_CODE = 'ACT_FIBER';
    private static final String DEVICE_CODE = 'ACT_DEVICE';
    private static final String LANDLINE_CODE = 'ACT_LANDLINE';

    @TestSetup
    static void createTestData() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getOrgDefaults();
        if (flags == null || flags.Id == null) {
            insert new ATS_Feature_Flags__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                BSS_Provisioning_Enabled__c = true
            );
        } else {
            flags.BSS_Provisioning_Enabled__c = true;
            update flags;
        }

        Pricebook2 pricebook = new Pricebook2(
            Name = PRICEBOOK_NAME,
            IsActive = true
        );
        insert pricebook;

        List<Product2> products = new List<Product2>{
            new Product2(
                Name = 'Activation Mobile 20',
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 20,
                Unlimited_Calls__c = true,
                Unlimited_SMS__c = true,
                Recurring__c = true,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = MOBILE_CODE
            ),
            new Product2(
                Name = 'Activation Fiber 100',
                Family = 'TELCO_FIBER',
                Plan_Type__c = 'Fiber',
                Speed_Mbps__c = 100,
                Recurring__c = true,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = FIBER_CODE
            ),
            new Product2(
                Name = 'Activation Handset',
                Family = 'TELCO_DEVICE',
                Recurring__c = false,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = DEVICE_CODE
            ),
            new Product2(
                Name = 'Activation Landline',
                Family = 'TELCO_FIBER',
                Plan_Type__c = 'Landline',
                Recurring__c = true,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = LANDLINE_CODE
            )
        };
        insert products;

        Map<String, Decimal> prices = new Map<String, Decimal>{
            MOBILE_CODE => 29.99,
            FIBER_CODE => 39.99,
            DEVICE_CODE => 199.00,
            LANDLINE_CODE => 19.99
        };
        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> standardEntries = new List<PricebookEntry>();
        for (Product2 product : products) {
            standardEntries.add(
                new PricebookEntry(
                    Pricebook2Id = standardPricebookId,
                    Product2Id = product.Id,
                    UnitPrice = prices.get(product.ATS_Product_Code__c),
                    IsActive = true,
                    UseStandardPrice = false
                )
            );
        }
        insert standardEntries;

        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 product : products) {
            entries.add(
                new PricebookEntry(
                    Pricebook2Id = pricebook.Id,
                    Product2Id = product.Id,
                    UnitPrice = prices.get(product.ATS_Product_Code__c),
                    IsActive = true,
                    UseStandardPrice = false
                )
            );
        }
        insert entries;

        List<Account> accounts = new List<Account>{
            new Account(Name = ACCOUNT_NAME, Segment__c = 'Consumer'),
            new Account(Name = BUSINESS_ACCOUNT_NAME, Segment__c = 'Business')
        };
        insert accounts;

        insert new List<Contact>{
            new Contact(
                LastName = CONTACT_LAST_NAME,
                AccountId = accounts[0].Id,
                Email = 'activation.consumer@example.com'
            ),
            new Contact(
                LastName = BUSINESS_CONTACT_LAST_NAME,
                AccountId = accounts[1].Id,
                Email = 'activation.business@example.com'
            )
        };
    }

    @IsTest
    static void activatesCommittedFiberOrder() {
        Account account = consumerAccount();
        Contact contact = consumerContact();
        Order order = newOrder(account, contact, 'Activation Fiber Order');
        OrderItem item = insertLine(order, FIBER_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(1, result.assetCount);
        System.assertEquals(1, result.subscriptionCount);
        System.assertEquals(1, result.engagementCount);
        System.assertNotEquals(null, result.contractId);

        Order refreshedOrder = [
            SELECT
                Id,
                Status,
                Activation_State__c,
                Failure_Reason__c,
                ContractId,
                Activated_By__c,
                Activated_On__c,
                BSS_Order_Key__c
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Activated', refreshedOrder.Status);
        System.assertEquals('Activated', refreshedOrder.Activation_State__c);
        System.assertEquals(null, refreshedOrder.Failure_Reason__c);
        System.assertEquals(result.contractId, refreshedOrder.ContractId);
        System.assertEquals(UserInfo.getUserId(), refreshedOrder.Activated_By__c);
        System.assertNotEquals(null, refreshedOrder.Activated_On__c);
        System.assertNotEquals(null, refreshedOrder.BSS_Order_Key__c);

        Contract contract = [
            SELECT
                Id,
                Status,
                StartDate,
                ContractTerm,
                ATS_Contract_Type__c,
                Pricebook2Id
            FROM Contract
            WHERE Id = :result.contractId
        ];
        System.assertEquals('Activated', contract.Status);
        System.assertEquals(Date.today(), contract.StartDate);
        System.assertEquals(12, contract.ContractTerm);
        System.assertEquals('Fiber', contract.ATS_Contract_Type__c);
        System.assertNotEquals(null, contract.Pricebook2Id);

        Asset asset = [
            SELECT
                Id,
                AccountId,
                Product2Id,
                Status,
                Service_Line_Type__c,
                Provisioned_Status__c,
                Is_Primary__c,
                UsageEndDate
            FROM Asset
            WHERE AccountId = :account.Id
        ];
        System.assertEquals('Installed', asset.Status);
        System.assertEquals('Fiber', asset.Service_Line_Type__c);
        System.assertEquals('Active', asset.Provisioned_Status__c);
        System.assertEquals(true, asset.Is_Primary__c);
        System.assertEquals(Date.today().addMonths(12), asset.UsageEndDate);

        Subscription__c subscription = [
            SELECT
                Id,
                Name,
                Status__c,
                Activation_Date__c,
                External_Reference__c,
                External_Status__c,
                Asset__c,
                Contract__c,
                Engagement__c,
                Root_Engagement__c,
                Billing_End_Date__c
            FROM Subscription__c
            WHERE Order_Product__c = :item.Id
        ];
        System.assertEquals('Active', subscription.Status__c);
        System.assertEquals(Date.today(), subscription.Activation_Date__c);
        System.assertEquals('Active', subscription.External_Status__c);
        System.assertEquals(asset.Id, subscription.Asset__c);
        System.assertEquals(contract.Id, subscription.Contract__c);
        System.assertNotEquals(null, subscription.Engagement__c);
        System.assertEquals(
            subscription.Engagement__c,
            subscription.Root_Engagement__c
        );
        System.assertEquals(
            'SIM-' + subscription.Name,
            subscription.External_Reference__c
        );
        System.assertEquals(
            Date.today().addMonths(12),
            subscription.Billing_End_Date__c
        );

        Engagement__c engagement = [
            SELECT
                Id,
                Engagement_Key__c,
                Status__c,
                Duration_Months__c,
                Start_Date__c,
                End_Date__c,
                Monthly_Amount__c,
                Penalty_Rate__c,
                Penalty_Rule__c,
                Subscription__c,
                Asset__c,
                Contract__c
            FROM Engagement__c
            WHERE Id = :subscription.Engagement__c
        ];
        System.assertEquals(
            'ENG-' + item.Id,
            engagement.Engagement_Key__c
        );
        System.assertEquals('Active', engagement.Status__c);
        System.assertEquals(12, engagement.Duration_Months__c);
        System.assertEquals(Date.today(), engagement.Start_Date__c);
        System.assertEquals(
            Date.today().addMonths(12),
            engagement.End_Date__c
        );
        System.assertEquals(39.99, engagement.Monthly_Amount__c);
        System.assertEquals(25, engagement.Penalty_Rate__c);
        System.assertEquals(
            'Consumer_Fiber_12M',
            engagement.Penalty_Rule__c
        );
        System.assertEquals(subscription.Id, engagement.Subscription__c);
        System.assertEquals(asset.Id, engagement.Asset__c);
        System.assertEquals(contract.Id, engagement.Contract__c);

        OrderItem refreshedItem = [
            SELECT Id, Subscription_Number__c
            FROM OrderItem
            WHERE Id = :item.Id
        ];
        System.assertEquals(
            subscription.Name,
            refreshedItem.Subscription_Number__c
        );

        Integration_Log__c log = [
            SELECT
                Correlation_Id__c,
                System__c,
                Direction__c,
                Operation__c,
                Status__c,
                Status_Code__c,
                Order__c,
                Subscription__c,
                Idempotency_Key__c
            FROM Integration_Log__c
            WHERE Order__c = :order.Id AND Status__c = 'Success'
            LIMIT 1
        ];
        System.assertEquals('BSS', log.System__c);
        System.assertEquals('Outbound', log.Direction__c);
        System.assertEquals('activateOrder', log.Operation__c);
        System.assertEquals('200', log.Status_Code__c);
        System.assertEquals(subscription.Id, log.Subscription__c);
        System.assertEquals(subscription.Name, log.Idempotency_Key__c);
    }

    @IsTest
    static void retryIsIdempotent() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Idempotent Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult first =
            ActivationService.activateOrder(order.Id);
        ActivationService.ActivationResult second =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', first.status, first.message);
        System.assertEquals('NoOp', second.status);
        System.assertEquals(
            'The order is already activated.',
            second.message
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Contract WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void bssFailureRollsBackAndReturnsOrderToReady() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation BSS Failure Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT12');

        ActivationService.setBssGateway(new FailingGateway());
        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();
        ActivationService.setBssGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals('Failed', result.status);
        System.assert(
            result.message.contains('BSS unavailable'),
            result.message
        );

        Order refreshedOrder = [
            SELECT
                Id,
                Status,
                Activation_State__c,
                Failure_Reason__c,
                ContractId
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Draft', refreshedOrder.Status);
        System.assertEquals('Ready', refreshedOrder.Activation_State__c);
        System.assert(
            refreshedOrder.Failure_Reason__c.contains('BSS unavailable')
        );
        System.assertEquals(null, refreshedOrder.ContractId);

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contract WHERE AccountId = :account.Id]
        );

        Integration_Log__c log = [
            SELECT
                System__c,
                Status__c,
                Error_Message__c,
                Order__c
            FROM Integration_Log__c
            WHERE Order__c = :order.Id AND Status__c = 'Failure'
            LIMIT 1
        ];
        System.assertEquals('BSS', log.System__c);
        System.assert(log.Error_Message__c.contains('BSS unavailable'));
    }

    @IsTest
    static void noCommitmentCreatesNoEngagement() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation No Commitment Order'
        );
        insertLine(order, FIBER_CODE, '');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(0, result.engagementCount);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );

        Contract contract = [
            SELECT Id, Status, ContractTerm, ATS_Contract_Type__c
            FROM Contract
            WHERE AccountId = :account.Id
        ];
        System.assertEquals('Activated', contract.Status);
        System.assertEquals(null, contract.ContractTerm);
        System.assertEquals('Fiber', contract.ATS_Contract_Type__c);

        Subscription__c subscription = [
            SELECT Id, Status__c, Engagement__c, Billing_End_Date__c
            FROM Subscription__c
            WHERE Account__c = :account.Id
        ];
        System.assertEquals('Active', subscription.Status__c);
        System.assertEquals(null, subscription.Engagement__c);
        System.assertEquals(null, subscription.Billing_End_Date__c);
    }

    @IsTest
    static void deviceInheritsPlanEngagement() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Device Bundle Order'
        );
        OrderItem planLine = insertLine(order, FIBER_CODE, 'COMMIT12');
        OrderItem deviceLine = insertLine(order, DEVICE_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(2, result.assetCount);
        System.assertEquals(2, result.subscriptionCount);
        System.assertEquals(1, result.engagementCount);

        Subscription__c planSubscription = [
            SELECT
                Id,
                Engagement__c,
                Root_Engagement__c,
                Parent_Subscription__c
            FROM Subscription__c
            WHERE Order_Product__c = :planLine.Id
        ];
        Subscription__c deviceSubscription = [
            SELECT
                Id,
                Engagement__c,
                Root_Engagement__c,
                Parent_Subscription__c
            FROM Subscription__c
            WHERE Order_Product__c = :deviceLine.Id
        ];

        System.assertNotEquals(null, planSubscription.Engagement__c);
        System.assertEquals(
            planSubscription.Engagement__c,
            deviceSubscription.Engagement__c
        );
        System.assertEquals(
            planSubscription.Engagement__c,
            deviceSubscription.Root_Engagement__c
        );
        System.assertEquals(
            planSubscription.Id,
            deviceSubscription.Parent_Subscription__c
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );
    }

    @IsTest
    static void existingContractIsAmendedNotDuplicated() {
        Account account = consumerAccount();
        Date originalStart = Date.today().addMonths(-6);
        Contract existing = new Contract(
            AccountId = account.Id,
            Status = 'Draft',
            StartDate = originalStart,
            ContractTerm = 24,
            Pricebook2Id = pricebook().Id
        );
        insert existing;

        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Amend Order'
        );
        order.ContractId = existing.Id;
        update order;
        insertLine(order, FIBER_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(existing.Id, result.contractId);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Contract WHERE AccountId = :account.Id]
        );

        Contract refreshed = [
            SELECT
                Id,
                Status,
                StartDate,
                ContractTerm,
                ATS_Contract_Type__c,
                Signed_On__c
            FROM Contract
            WHERE Id = :existing.Id
        ];
        System.assertEquals('Activated', refreshed.Status);
        System.assertEquals(originalStart, refreshed.StartDate);
        System.assertEquals(24, refreshed.ContractTerm);
        System.assertEquals('Fiber', refreshed.ATS_Contract_Type__c);
        System.assertEquals(Date.today(), refreshed.Signed_On__c);
    }

    @IsTest
    static void mixedOrderCreatesBundleContract() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Bundle Contract Order'
        );
        insertLine(order, MOBILE_CODE, 'COMMIT24');
        insertLine(order, FIBER_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(2, result.engagementCount);

        Contract contract = [
            SELECT Id, ATS_Contract_Type__c, ContractTerm
            FROM Contract
            WHERE AccountId = :account.Id
        ];
        System.assertEquals('Bundle', contract.ATS_Contract_Type__c);
        System.assertEquals(24, contract.ContractTerm);
    }

    @IsTest
    static void businessPenaltyUsesGenericRule() {
        Account account = businessAccount();
        Order order = newOrder(
            account,
            businessContact(),
            'Activation Business Order'
        );
        insertLine(order, MOBILE_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        Engagement__c engagement = [
            SELECT Penalty_Rate__c, Penalty_Rule__c, Duration_Months__c
            FROM Engagement__c
            WHERE Account__c = :account.Id
        ];
        System.assertEquals(15, engagement.Penalty_Rate__c);
        System.assertEquals('Business_Any', engagement.Penalty_Rule__c);
        System.assertEquals(12, engagement.Duration_Months__c);
    }

    @IsTest
    static void missingPenaltyRuleRollsBack() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Missing Penalty Order'
        );
        insertLine(order, LANDLINE_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Failed', result.status);
        System.assert(
            result.message.contains('No active penalty rule'),
            result.message
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contract WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void rejectsOrderWithoutItems() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Empty Order'
        );

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('no order items'));
        Order refreshed = [
            SELECT Activation_State__c, Failure_Reason__c
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Ready', refreshed.Activation_State__c);
        System.assert(refreshed.Failure_Reason__c.contains('no order items'));
    }

    @IsTest
    static void rejectsOrderThatIsNotReady() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Not Eligible Order'
        );
        order.Activation_State__c = 'Not_Eligible';
        update order;
        insertLine(order, FIBER_CODE, 'COMMIT12');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('not in Ready state'));
        Order refreshed = [
            SELECT Activation_State__c, Failure_Reason__c
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Not_Eligible', refreshed.Activation_State__c);
        System.assert(refreshed.Failure_Reason__c.contains('not in Ready state'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void rejectsUnsupportedCommitmentCode() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Bad Commitment Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT99');

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Failed', result.status);
        System.assert(
            result.message.contains('Unsupported commitment option code')
        );
        Order refreshed = [
            SELECT Activation_State__c, Failure_Reason__c
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Ready', refreshed.Activation_State__c);
    }

    @IsTest
    static void blocksWhenBssProvisioningIsDisabled() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Flag Off Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT12');
        setBssFlag(false);

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();
        setBssFlag(true);

        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('BSS provisioning is disabled'));
        Order refreshed = [
            SELECT Activation_State__c, Failure_Reason__c
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Ready', refreshed.Activation_State__c);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void acceptsEmptyAndNullOrderInputs() {
        System.assertEquals(
            0,
            ActivationService.activate(new List<Id>()).size()
        );

        Test.startTest();
        List<ActivationService.ActivationResult> results =
            ActivationService.activate(new List<Id>{ null });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Failed', results[0].status);
        System.assertEquals('An Order Id is required.', results[0].message);
    }

    @IsTest
    static void rejectsMoreThanEightyOrdersPerCall() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Oversized Batch Order'
        );
        List<Id> orderIds = new List<Id>();
        for (Integer index = 0; index < 81; index++) {
            orderIds.add(order.Id);
        }

        Test.startTest();
        List<ActivationService.ActivationResult> results =
            ActivationService.activate(orderIds);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Failed', results[0].status);
        System.assert(results[0].message.contains('at most 80 orders'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void nullBssResponseRollsBack() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Null BSS Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT12');

        ActivationService.setBssGateway(new NullGateway());
        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();
        ActivationService.setBssGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('incomplete provisioning response'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void nullSubscriptionIdInBssResponseRollsBack() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Null Subscription BSS Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT12');

        ActivationService.setBssGateway(new NullSubscriptionIdGateway());
        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();
        ActivationService.setBssGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('did not identify a subscription'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void incompleteBssCoverageRollsBack() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Incomplete Coverage Order'
        );
        insertLine(order, FIBER_CODE, 'COMMIT12');
        insertLine(order, MOBILE_CODE, 'COMMIT12');

        ActivationService.setBssGateway(new DuplicateSubscriptionGateway());
        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();
        ActivationService.setBssGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals('Failed', result.status);
        System.assert(result.message.contains('did not cover every subscription'));
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
    }

    @IsTest
    static void bulkTwoHundredOrderItems() {
        Account account = consumerAccount();
        Order order = newOrder(
            account,
            consumerContact(),
            'Activation Bulk Order'
        );
        Product2 product = product(FIBER_CODE);
        PricebookEntry entry = pricebookEntry(FIBER_CODE);
        List<OrderItem> items = new List<OrderItem>();
        for (Integer index = 0; index < 200; index++) {
            items.add(
                new OrderItem(
                    OrderId = order.Id,
                    PricebookEntryId = entry.Id,
                    Product2Id = product.Id,
                    Quantity = 1,
                    UnitPrice = entry.UnitPrice,
                    ServiceDate = Date.today(),
                    Description = product.Name,
                    Commitment_Option_Code__c = 'COMMIT12'
                )
            );
        }
        insert items;

        Test.startTest();
        ActivationService.ActivationResult result =
            ActivationService.activateOrder(order.Id);
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(200, result.assetCount);
        System.assertEquals(200, result.subscriptionCount);
        System.assertEquals(200, result.engagementCount);
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Asset WHERE AccountId = :account.Id]
        );
        System.assertEquals(
            200,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );
        System.assertEquals(
            200,
            [
                SELECT COUNT()
                FROM OrderItem
                WHERE OrderId = :order.Id
                    AND Subscription_Number__c != null
            ]
        );
    }

    private class FailingGateway implements BssProvisioningGateway {
        public List<BssProvisioningResponse> provision(
            List<BssProvisioningRequest> requests
        ) {
            List<BssProvisioningResponse> responses =
                new List<BssProvisioningResponse>();
            for (BssProvisioningRequest request : requests) {
                BssProvisioningResponse response =
                    new BssProvisioningResponse();
                response.subscriptionId = request.subscriptionId;
                response.success = false;
                response.statusCode = '503';
                response.message = 'BSS unavailable';
                responses.add(response);
            }
            return responses;
        }
    }

    private class NullGateway implements BssProvisioningGateway {
        public List<BssProvisioningResponse> provision(
            List<BssProvisioningRequest> requests
        ) {
            return null;
        }
    }

    private class NullSubscriptionIdGateway
        implements BssProvisioningGateway {
        public List<BssProvisioningResponse> provision(
            List<BssProvisioningRequest> requests
        ) {
            List<BssProvisioningResponse> responses =
                new List<BssProvisioningResponse>();
            for (BssProvisioningRequest request : requests) {
                BssProvisioningResponse response =
                    new BssProvisioningResponse();
                response.success = true;
                response.statusCode = '200';
                responses.add(response);
            }
            return responses;
        }
    }

    private class DuplicateSubscriptionGateway
        implements BssProvisioningGateway {
        public List<BssProvisioningResponse> provision(
            List<BssProvisioningRequest> requests
        ) {
            List<BssProvisioningResponse> responses =
                new List<BssProvisioningResponse>();
            if (requests.isEmpty()) {
                return responses;
            }
            BssProvisioningRequest first = requests[0];
            for (BssProvisioningRequest request : requests) {
                BssProvisioningResponse response =
                    new BssProvisioningResponse();
                response.subscriptionId = first.subscriptionId;
                response.success = true;
                response.statusCode = '200';
                response.externalReference =
                    'SIM-' + first.subscriptionNumber;
                responses.add(response);
            }
            return responses;
        }
    }

    private static Account consumerAccount() {
        return [
            SELECT Id, Name, Segment__c
            FROM Account
            WHERE Name = :ACCOUNT_NAME
            LIMIT 1
        ];
    }

    private static Account businessAccount() {
        return [
            SELECT Id, Name, Segment__c
            FROM Account
            WHERE Name = :BUSINESS_ACCOUNT_NAME
            LIMIT 1
        ];
    }

    private static Contact consumerContact() {
        return [
            SELECT Id, LastName, AccountId
            FROM Contact
            WHERE LastName = :CONTACT_LAST_NAME
            LIMIT 1
        ];
    }

    private static Contact businessContact() {
        return [
            SELECT Id, LastName, AccountId
            FROM Contact
            WHERE LastName = :BUSINESS_CONTACT_LAST_NAME
            LIMIT 1
        ];
    }

    private static Pricebook2 pricebook() {
        return [
            SELECT Id, Name
            FROM Pricebook2
            WHERE Name = :PRICEBOOK_NAME
            LIMIT 1
        ];
    }

    private static Product2 product(String productCode) {
        return [
            SELECT
                Id,
                Name,
                Family,
                Plan_Type__c,
                Recurring__c,
                ATS_Product_Code__c
            FROM Product2
            WHERE ATS_Product_Code__c = :productCode
            LIMIT 1
        ];
    }

    private static PricebookEntry pricebookEntry(String productCode) {
        Pricebook2 book = pricebook();
        Product2 prod = product(productCode);
        return [
            SELECT Id, UnitPrice, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :book.Id AND Product2Id = :prod.Id
            LIMIT 1
        ];
    }

    private static Order newOrder(
        Account account,
        Contact contact,
        String name
    ) {
        Order order = new Order(
            Name = name,
            AccountId = account.Id,
            BillToContactId = contact.Id,
            Pricebook2Id = pricebook().Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Activation_State__c = 'Ready'
        );
        insert order;
        return order;
    }

    private static OrderItem insertLine(
        Order order,
        String productCode,
        String commitmentCode
    ) {
        Product2 prod = product(productCode);
        PricebookEntry entry = pricebookEntry(productCode);
        OrderItem item = new OrderItem(
            OrderId = order.Id,
            PricebookEntryId = entry.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = entry.UnitPrice,
            ServiceDate = Date.today(),
            Description = prod.Name,
            Commitment_Option_Code__c = commitmentCode
        );
        insert item;
        return item;
    }

    private static void setBssFlag(Boolean enabled) {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        if (flags == null) {
            flags = new ATS_Feature_Flags__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }
        flags.BSS_Provisioning_Enabled__c = enabled;
        upsert flags;
    }
}
