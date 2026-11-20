@IsTest
private class EquipmentSwapServiceTest {
    private static final String OLD_PRODUCT_CODE = 'SWAP_OLD_DEVICE';
    private static final String NEW_PRODUCT_CODE = 'SWAP_NEW_DEVICE';
    private static final String SECOND_PRODUCT_CODE = 'SWAP_SECOND_DEVICE';
    private static final String PLAN_PRODUCT_CODE = 'SWAP_NOT_DEVICE';

    @TestSetup
    static void createCatalogue() {
        Pricebook2 pricebook = new Pricebook2(
            Name = 'Equipment Swap Test Pricebook',
            IsActive = true
        );
        insert pricebook;

        List<Product2> products = new List<Product2>{
            device(OLD_PRODUCT_CODE, 'Swap Old Device', 199.00),
            device(NEW_PRODUCT_CODE, 'Swap New Device', 249.00),
            device(SECOND_PRODUCT_CODE, 'Swap Second Device', 299.00)
        };
        products.add(
            new Product2(
                Name = 'Swap Mobile Plan',
                ProductCode = PLAN_PRODUCT_CODE,
                ATS_Product_Code__c = 'PC_' + PLAN_PRODUCT_CODE,
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 20,
                IsActive = true,
                Is_Active__c = true,
                Recurring__c = true,
                Requires_Commitment__c = true
            )
        );
        insert products;

        List<PricebookEntry> entries = new List<PricebookEntry>();
        Id standardPricebookId = Test.getStandardPricebookId();
        for (Product2 product : products) {
            Decimal unitPrice = product.Name.contains('Old')
                ? 199.00
                : (product.Name.contains('Second') ? 299.00 : 249.00);
            entries.add(
                new PricebookEntry(
                    Pricebook2Id = standardPricebookId,
                    Product2Id = product.Id,
                    UnitPrice = unitPrice,
                    IsActive = true,
                    UseStandardPrice = false
                )
            );
            entries.add(
                new PricebookEntry(
                    Pricebook2Id = pricebook.Id,
                    Product2Id = product.Id,
                    UnitPrice = unitPrice,
                    IsActive = true,
                    UseStandardPrice = false
                )
            );
        }
        insert entries;
    }

    @IsTest
    static void validSwapRetiresOldAssetAndCreatesNewAsset() {
        Fixture fixture = createFixture(1);
        EquipmentSwapBssClient.setGateway(new CountingGateway());

        Test.startTest();
        List<EquipmentSwapService.EquipmentSwapResult> results =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(fixture, productId(NEW_PRODUCT_CODE), false)
                }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result was expected.');
        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals(
            EquipmentSwapPolicy.STATUS_COMPLETED,
            results[0].status,
            'Approved swaps should complete in intake.'
        );
        System.assertNotEquals(null, results[0].newAssetId, 'New asset is required.');

        Asset oldAsset = [
            SELECT Id, Status, Provisioned_Status__c
            FROM Asset
            WHERE Id = :fixture.oldAsset.Id
        ];
        Asset newAsset = [
            SELECT
                Id,
                Name,
                AccountId,
                ParentId,
                Product2Id,
                SerialNumber,
                Colour__c,
                Image_URL__c,
                Order_Item__c,
                Status,
                Provisioned_Status__c
            FROM Asset
            WHERE Id = :results[0].newAssetId
        ];
        System.assertEquals(
            EquipmentSwapPolicy.OLD_ASSET_STATUS,
            oldAsset.Status,
            'Old asset should be retired.'
        );
        System.assertEquals(
            EquipmentSwapPolicy.OLD_ASSET_PROVISIONED_STATUS,
            oldAsset.Provisioned_Status__c,
            'Old asset provisioning should be superseded.'
        );
        System.assertEquals(
            EquipmentSwapPolicy.NEW_ASSET_STATUS,
            newAsset.Status,
            'New asset should be installed.'
        );
        System.assertEquals(fixture.parentAsset.Id, newAsset.ParentId, 'Parent lineage should be preserved.');
        System.assertEquals(
            productId(NEW_PRODUCT_CODE),
            newAsset.Product2Id,
            'New asset should use the requested device.'
        );
        System.assertEquals('SERNEW0001', newAsset.SerialNumber, 'Serial should be stamped.');
        System.assertEquals('Midnight', newAsset.Colour__c, 'Colour should be stamped.');
        System.assertNotEquals(null, newAsset.Image_URL__c, 'Image URL should be stamped.');

        OrderItem swapItem = [
            SELECT Id, OrderId, Product2Id, Creates_Asset__c, Subscription_Number__c
            FROM OrderItem
            WHERE Id = :newAsset.Order_Item__c
        ];
        System.assertEquals(
            fixture.orderItem.OrderId,
            swapItem.OrderId,
            'Swap OrderItem should reuse the source order.'
        );
        System.assertEquals(true, swapItem.Creates_Asset__c, 'Swap line should create an asset.');

        Subscription__c subscription = [
            SELECT Id, Name, Status__c, Asset__c, Engagement__c, Monthly_Amount__c
            FROM Subscription__c
            WHERE Id = :fixture.subscription.Id
        ];
        System.assertEquals(
            subscription.Name,
            swapItem.Subscription_Number__c,
            'Swap line should carry the subscription number.'
        );
        System.assertEquals('Active', subscription.Status__c, 'Service status must not change.');
        System.assertEquals(newAsset.Id, subscription.Asset__c, 'Subscription should point to the new asset.');
        System.assertEquals(fixture.engagement.Id, subscription.Engagement__c, 'Engagement must not change.');
        System.assertEquals(
            fixture.subscription.Monthly_Amount__c,
            subscription.Monthly_Amount__c,
            'Price must not change.'
        );

        Customer_Request__c request = [
            SELECT
                Id,
                Status__c,
                Case__c,
                Requested_Product__c,
                Old_Asset__c,
                New_Asset__c,
                BSS_Swap_Reference__c,
                Calculated_Fee__c,
                Fee_Breakdown__c,
                Completed_On__c
            FROM Customer_Request__c
            WHERE Id = :results[0].requestId
        ];
        System.assertEquals(EquipmentSwapPolicy.STATUS_COMPLETED, request.Status__c);
        System.assertEquals(fixture.oldAsset.Id, request.Old_Asset__c);
        System.assertEquals(newAsset.Id, request.New_Asset__c);
        System.assertNotEquals(null, request.BSS_Swap_Reference__c, 'BSS reference is required.');
        System.assertEquals(0, request.Calculated_Fee__c, 'Swap must be fee-free.');
        System.assert(request.Fee_Breakdown__c.contains('BQ5/Q7'), 'Fee breakdown should record the open decision.');
        System.assertNotEquals(null, request.Completed_On__c);

        Case requestCase = [SELECT Id, Status FROM Case WHERE Id = :request.Case__c];
        System.assertEquals('Closed', requestCase.Status, 'Linked Case should close.');

        List<Integration_Log__c> logs = [
            SELECT Id, Operation__c, Status__c
            FROM Integration_Log__c
            WHERE Subscription__c = :fixture.subscription.Id
        ];
        System.assertEquals(1, logs.size(), 'One BSS audit log was expected.');
        System.assertEquals(EquipmentSwapPolicy.OPERATION_SWAP, logs[0].Operation__c);
        System.assertEquals('Success', logs[0].Status__c);
    }

    @IsTest
    static void goodwillWaiverWaitsForApprovalAndDoesNotCallBss() {
        Fixture fixture = createFixture(2);
        CountingGateway gateway = new CountingGateway();
        EquipmentSwapBssClient.setGateway(gateway);

        Test.startTest();
        List<EquipmentSwapService.EquipmentSwapResult> results =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(fixture, productId(NEW_PRODUCT_CODE), true)
                }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals(
            EquipmentSwapPolicy.STATUS_AWAITING,
            results[0].status,
            'Goodwill waiver should require approval.'
        );
        System.assertEquals(0, gateway.calls, 'BSS must not be called before approval.');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Asset
                WHERE AccountId = :fixture.account.Id
                AND Id NOT IN :new List<Id>{ fixture.parentAsset.Id, fixture.oldAsset.Id }
            ],
            'No replacement asset should exist before approval.'
        );
    }

    @IsTest
    static void approvalAppliesAnAwaitingSwap() {
        Fixture fixture = createFixture(3);
        EquipmentSwapBssClient.setGateway(new CountingGateway());
        List<EquipmentSwapService.EquipmentSwapResult> submitted =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(fixture, productId(NEW_PRODUCT_CODE), true)
                }
            );
        Customer_Request__c request = [
            SELECT Id, Status__c
            FROM Customer_Request__c
            WHERE Id = :submitted[0].requestId
        ];
        request.Status__c = EquipmentSwapPolicy.STATUS_APPROVED;
        update request;

        EquipmentSwapApprovalService.ApprovalInput approvalInput =
            new EquipmentSwapApprovalService.ApprovalInput();
        approvalInput.requestId = request.Id;

        Test.startTest();
        List<EquipmentSwapService.EquipmentSwapResult> results =
            EquipmentSwapApprovalService.apply(
                new List<EquipmentSwapApprovalService.ApprovalInput>{ approvalInput }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals(EquipmentSwapPolicy.STATUS_COMPLETED, results[0].status);
        System.assertNotEquals(null, results[0].newAssetId, 'Approval should create the new asset.');
    }

    @IsTest
    static void bssFailureRollsBackWritesAndApprovalCanRetry() {
        Fixture fixture = createFixture(4);
        FailingGateway failing = new FailingGateway();
        EquipmentSwapBssClient.setGateway(failing);

        List<EquipmentSwapService.EquipmentSwapResult> failed =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(fixture, productId(NEW_PRODUCT_CODE), false)
                }
            );
        System.assertEquals(false, failed[0].success, 'BSS failure should fail the result.');
        System.assert(failed[0].message.contains('BSS unavailable'), failed[0].message);

        Asset oldAsset = [
            SELECT Id, Status
            FROM Asset
            WHERE Id = :fixture.oldAsset.Id
        ];
        System.assertEquals('Installed', oldAsset.Status, 'Old asset must survive a BSS failure.');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Asset
                WHERE AccountId = :fixture.account.Id
                AND Id NOT IN :new List<Id>{ fixture.parentAsset.Id, fixture.oldAsset.Id }
            ],
            'No replacement asset should survive a BSS failure.'
        );
        Customer_Request__c request = [
            SELECT Id, Status__c, New_Asset__c, Completed_On__c
            FROM Customer_Request__c
            WHERE Id = :failed[0].requestId
        ];
        System.assertEquals(EquipmentSwapPolicy.STATUS_APPROVED, request.Status__c, 'Request should remain Approved for retry.');
        System.assertEquals(null, request.New_Asset__c);
        System.assertEquals(null, request.Completed_On__c);

        EquipmentSwapBssClient.setGateway(new CountingGateway());
        EquipmentSwapService.ApprovalInput retryInput =
            new EquipmentSwapService.ApprovalInput();
        retryInput.requestId = request.Id;
        List<EquipmentSwapService.EquipmentSwapResult> retried =
            EquipmentSwapService.applyApproved(
                new List<EquipmentSwapService.ApprovalInput>{ retryInput }
            );
        System.assertEquals(true, retried[0].success, retried[0].message);
        System.assertNotEquals(null, retried[0].newAssetId, 'Retry should create the new asset.');
    }

    @IsTest
    static void inFlightSwapIsRejectedBeforeIntake() {
        Fixture fixture = createFixture(5);
        insert new Customer_Request__c(
            Account__c = fixture.account.Id,
            Contact__c = fixture.contact.Id,
            Subscription__c = fixture.subscription.Id,
            Channel__c = 'Advisor',
            Request_Type__c = EquipmentSwapPolicy.REQUEST_TYPE,
            Status__c = EquipmentSwapPolicy.STATUS_APPROVED
        );

        List<EquipmentSwapService.EquipmentSwapResult> results =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(fixture, productId(NEW_PRODUCT_CODE), false)
                }
            );

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('already in progress'), results[0].message);
        System.assertEquals(null, results[0].requestId, 'No new request should be created.');
    }

    @IsTest
    static void nonDeviceProductIsRejected() {
        Fixture fixture = createFixture(6);

        List<EquipmentSwapService.EquipmentSwapResult> results =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(fixture, productId(PLAN_PRODUCT_CODE), false)
                }
            );

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('active product catalogue'), results[0].message);
        System.assertEquals(null, results[0].requestId);
    }

    @IsTest
    static void bulkSwapsAreAppliedIndependently() {
        Fixture first = createFixture(7);
        Fixture second = createFixture(8);
        EquipmentSwapBssClient.setGateway(new CountingGateway());

        Test.startTest();
        List<EquipmentSwapService.EquipmentSwapResult> results =
            EquipmentSwapService.requestSwaps(
                new List<EquipmentSwapService.EquipmentSwapInput>{
                    input(first, productId(NEW_PRODUCT_CODE), false),
                    input(second, productId(SECOND_PRODUCT_CODE), false)
                }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals(true, results[1].success, results[1].message);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Asset
                WHERE Id IN :new List<Id>{ results[0].newAssetId, results[1].newAssetId }
            ],
            'Two replacement assets were expected.'
        );
    }

    private static EquipmentSwapService.EquipmentSwapInput input(
        Fixture fixture,
        Id newProductId,
        Boolean waiver
    ) {
        EquipmentSwapService.EquipmentSwapInput input =
            new EquipmentSwapService.EquipmentSwapInput();
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.newProductId = newProductId;
        input.serialNumber = 'SERNEW0001';
        input.colour = 'Midnight';
        input.imageUrl = 'https://example.com/swap-device.png';
        input.channel = 'Advisor';
        input.customerComment = 'Customer requested a colour change.';
        input.goodwillWaiver = waiver;
        input.goodwillJustification = waiver ? 'Loyalty gesture.' : null;
        input.priority = 'High';
        return input;
    }

    private static Id productId(String productCode) {
        return [
            SELECT Id
            FROM Product2
            WHERE ProductCode = :productCode
            LIMIT 1
        ].Id;
    }

    private static Product2 device(
        String productCode,
        String name,
        Decimal price
    ) {
        return new Product2(
            Name = name,
            ProductCode = productCode,
            ATS_Product_Code__c = 'PC_' + productCode,
            Family = 'TELCO_DEVICE',
            Plan_Type__c = 'Mobile',
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = false,
            Requires_Commitment__c = true,
            Device_Image_URL__c = 'https://example.com/' + productCode + '.png',
            Specs__c = 'Test device specs'
        );
    }

    private static Fixture createFixture(Integer suffix) {
        String runId = String.valueOf(DateTime.now().getTime());
        Fixture fixture = new Fixture();

        fixture.account = new Account(
            Name = 'Swap Test ' + runId + '-' + suffix,
            Segment__c = 'Consumer',
            BillingPostalCode = '7500' + String.valueOf(suffix)
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'Swapper' + runId + suffix,
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        Pricebook2 pricebook = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'Equipment Swap Test Pricebook'
            LIMIT 1
        ];
        PricebookEntry entry = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE
                Pricebook2Id = :pricebook.Id
                AND Product2Id = :productId(OLD_PRODUCT_CODE)
            LIMIT 1
        ];

        Order order = new Order(
            Name = 'Swap Test Order ' + runId + '-' + suffix,
            AccountId = fixture.account.Id,
            BillToContactId = fixture.contact.Id,
            Pricebook2Id = pricebook.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Activation_State__c = 'Ready'
        );
        insert order;

        fixture.orderItem = new OrderItem(
            OrderId = order.Id,
            PricebookEntryId = entry.Id,
            Product2Id = productId(OLD_PRODUCT_CODE),
            Quantity = 1,
            UnitPrice = entry.UnitPrice,
            ServiceDate = Date.today(),
            Description = 'Original device',
            Creates_Asset__c = true,
            Commitment_Option_Code__c = 'COMMIT24'
        );
        insert fixture.orderItem;

        fixture.parentAsset = new Asset(
            Name = 'Swap Parent ' + runId + '-' + suffix,
            AccountId = fixture.account.Id,
            Status = 'Installed',
            Service_Line_Type__c = 'Mobile'
        );
        insert fixture.parentAsset;

        fixture.oldAsset = new Asset(
            Name = 'Swap Old Asset ' + runId + '-' + suffix,
            AccountId = fixture.account.Id,
            ParentId = fixture.parentAsset.Id,
            Product2Id = productId(OLD_PRODUCT_CODE),
            SerialNumber = 'SEROLD0001',
            Order_Item__c = fixture.orderItem.Id,
            Status = 'Installed',
            Provisioned_Status__c = 'Active',
            Service_Line_Type__c = 'Mobile',
            Is_Primary__c = true
        );
        insert fixture.oldAsset;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = fixture.oldAsset.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = productId(OLD_PRODUCT_CODE),
            Monthly_Amount__c = 39.99,
            MSISDN__c = '+33612' + ('00000' + String.valueOf(suffix)).right(6),
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Start_Date__c = Date.today().addMonths(-2),
            End_Date__c = Date.today().addMonths(22),
            Duration_Months__c = 24,
            Monthly_Amount__c = 39.99,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = 'Active';
        update fixture.subscription;
        fixture.subscription.Order_Product__c = fixture.orderItem.Id;
        update fixture.subscription;
        return fixture;
    }

    private class Fixture {
        Account account;
        Contact contact;
        OrderItem orderItem;
        Asset parentAsset;
        Asset oldAsset;
        Subscription__c subscription;
        Engagement__c engagement;
    }

    private class CountingGateway implements BssEquipmentSwapGateway {
        Integer calls = 0;

        public List<BssProvisioningResponse> swap(
            List<BssEquipmentSwapRequest> requests
        ) {
            calls++;
            return SimulatedBssEquipmentSwapGatewayResponse(requests);
        }
    }

    private class FailingGateway implements BssEquipmentSwapGateway {
        public List<BssProvisioningResponse> swap(
            List<BssEquipmentSwapRequest> requests
        ) {
            throw new EquipmentSwapException('BSS unavailable');
        }
    }

    private static List<BssProvisioningResponse>
        SimulatedBssEquipmentSwapGatewayResponse(
            List<BssEquipmentSwapRequest> requests
        ) {
        return new SimulatedBssEquipmentSwapGateway().swap(requests);
    }
}
