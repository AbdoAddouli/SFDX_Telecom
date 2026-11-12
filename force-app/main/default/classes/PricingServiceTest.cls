@IsTest
private class PricingServiceTest {
    private static final Date PRICING_DATE = Date.newInstance(2026, 11, 7);

    @TestSetup
    static void createTestData() {
        Pricebook2 pricebook = new Pricebook2(
            Name = 'ATS Test Pricebook',
            IsActive = true
        );
        insert pricebook;

        List<Product2> products = new List<Product2>{
            new Product2(
                Name = 'Test Device',
                Family = 'TELCO_DEVICE',
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'TEST_DEVICE'
            ),
            new Product2(
                Name = 'Test Mobile',
                Family = 'TELCO_MOBILE',
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'TEST_MOBILE'
            ),
            new Product2(
                Name = 'Test Orphan',
                Family = 'TELCO_DEVICE',
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'TEST_ORPHAN'
            )
        };
        insert products;

        Map<String, Product2> byCode = new Map<String, Product2>();
        for (Product2 product : products) {
            byCode.put(product.ATS_Product_Code__c, product);
        }

        Id standardPricebookId = Test.getStandardPricebookId();

        // A custom pricebook entry requires a matching standard-price row first.
        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = byCode.get('TEST_DEVICE').Id,
                UnitPrice = 1000,
                IsActive = true,
                UseStandardPrice = false
            ),
            new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = byCode.get('TEST_MOBILE').Id,
                UnitPrice = 100,
                IsActive = true,
                UseStandardPrice = false
            )
        };

        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = pricebook.Id,
                Product2Id = byCode.get('TEST_DEVICE').Id,
                UnitPrice = 1000,
                IsActive = true,
                UseStandardPrice = false
            ),
            new PricebookEntry(
                Pricebook2Id = pricebook.Id,
                Product2Id = byCode.get('TEST_MOBILE').Id,
                UnitPrice = 100,
                IsActive = true,
                UseStandardPrice = false
            )
        };
    }

    private static Product2 getProduct(String productCode) {
        return [
            SELECT Id, Name, Family, ATS_Product_Code__c
            FROM Product2
            WHERE ATS_Product_Code__c = :productCode
            LIMIT 1
        ];
    }

    @IsTest
    static void appliesDeviceBundleWhenRecurringCompanionPresent() {
        Product2 device = getProduct('TEST_DEVICE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            device.Id,
            'COMMIT12',
            'Consumer',
            PRICING_DATE,
            new Set<String>{ 'TELCO_MOBILE' }
        );
        Test.stopTest();

        System.assertEquals(1000.00, result.listPrice, 'List price should come from the active pricebook entry.');
        System.assertEquals(300.00, result.adjustmentTotal, '30% device bundle should be applied.');
        System.assertEquals(700.00, result.finalPrice, 'Device price should be discounted by 30%.');
        System.assertEquals(1, result.appliedRules.size(), 'Exactly one rule should fire.');
        System.assertEquals(
            'Device_Bundle_30_Percent',
            result.appliedRules[0].developerName,
            'The applied rule must be auditable by name.'
        );
        System.assertEquals('Bundle Adjustment', result.appliedRules[0].ruleType);
        System.assertEquals(300.00, result.appliedRules[0].amount);
    }

    @IsTest
    static void doesNotApplyBundleWithoutCompanion() {
        Product2 device = getProduct('TEST_DEVICE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            device.Id,
            'COMMIT12',
            'Consumer',
            PRICING_DATE
        );
        Test.stopTest();

        System.assertEquals(1000.00, result.finalPrice, 'A device-only quote must not receive the bundle discount.');
        System.assertEquals(0.00, result.adjustmentTotal);
        System.assertEquals(0, result.appliedRules.size(), 'The companion requirement must block the bundle rule.');
    }

    @IsTest
    static void appliesCommitmentVariantToRecurringProduct() {
        Product2 mobile = getProduct('TEST_MOBILE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            mobile.Id,
            'COMMIT12',
            'Consumer',
            PRICING_DATE
        );
        Test.stopTest();

        System.assertEquals(100.00, result.listPrice);
        System.assertEquals(10.00, result.adjustmentTotal);
        System.assertEquals(90.00, result.finalPrice);
        System.assertEquals(1, result.appliedRules.size());
        System.assertEquals('Commitment_Variant_12M', result.appliedRules[0].developerName);
    }

    @IsTest
    static void appliesCommitmentThenFiberBundleInPriorityOrder() {
        Product2 mobile = getProduct('TEST_MOBILE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            mobile.Id,
            'COMMIT12',
            'Consumer',
            PRICING_DATE,
            new Set<String>{ 'TELCO_FIBER' }
        );
        Test.stopTest();

        System.assertEquals(100.00, result.listPrice);
        System.assertEquals(23.50, result.adjustmentTotal);
        System.assertEquals(76.50, result.finalPrice);
        System.assertEquals(2, result.appliedRules.size());
        System.assertEquals('Commitment_Variant_12M', result.appliedRules[0].developerName);
        System.assertEquals('Fiber_Mobile_Bundle_15_Percent', result.appliedRules[1].developerName);
    }

    @IsTest
    static void isDeterministicForIdenticalInputs() {
        Product2 device = getProduct('TEST_DEVICE');
        Set<String> companions = new Set<String>{ 'TELCO_RECURRING' };

        Test.startTest();
        PricingService.PriceBreakdown first = PricingService.price(
            device.Id,
            'COMMIT24',
            'Business',
            PRICING_DATE,
            companions
        );
        PricingService.PriceBreakdown second = PricingService.price(
            device.Id,
            'COMMIT24',
            'Business',
            PRICING_DATE,
            companions
        );
        Test.stopTest();

        System.assertEquals(first.listPrice, second.listPrice);
        System.assertEquals(first.adjustmentTotal, second.adjustmentTotal);
        System.assertEquals(first.finalPrice, second.finalPrice);
        System.assertEquals(first.appliedRules.size(), second.appliedRules.size());
        System.assertEquals(
            first.appliedRules[0].developerName,
            second.appliedRules[0].developerName
        );
    }

    @IsTest
    static void doesNotApplyRulesBeforeEffectiveDate() {
        Product2 device = getProduct('TEST_DEVICE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            device.Id,
            'COMMIT12',
            'Consumer',
            Date.newInstance(2025, 12, 31),
            new Set<String>{ 'TELCO_MOBILE' }
        );
        Test.stopTest();

        System.assertEquals(1000.00, result.finalPrice);
        System.assertEquals(0, result.appliedRules.size());
    }

    @IsTest
    static void doesNotApplyCommitmentVariantForNoCommit() {
        Product2 mobile = getProduct('TEST_MOBILE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            mobile.Id,
            'NOCOMMIT',
            'Consumer',
            PRICING_DATE
        );
        Test.stopTest();

        System.assertEquals(100.00, result.finalPrice);
        System.assertEquals(0, result.appliedRules.size());
    }

    @IsTest
    static void throwsWhenNoActivePricebookEntryExists() {
        Product2 orphan = getProduct('TEST_ORPHAN');
        Boolean threw = false;

        Test.startTest();
        try {
            PricingService.price(orphan.Id, 'COMMIT12', 'Consumer', PRICING_DATE);
        } catch (PricingService.PricingException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('No active pricebook entry'),
                'Exception should identify the missing pricebook entry.'
            );
        }
        Test.stopTest();

        System.assert(threw, 'Pricing should fail when no active pricebook entry exists.');
    }

    @IsTest
    static void throwsWhenProductIdIsNull() {
        Boolean threw = false;

        Test.startTest();
        try {
            PricingService.price(null, 'COMMIT12', 'Consumer', PRICING_DATE);
        } catch (PricingService.PricingException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Pricing should fail when the product id is null.');
    }

    @IsTest
    static void evaluatesRequiresCommitmentDeviceForNoCommit() {
        Product2 device = getProduct('TEST_DEVICE');

        Test.startTest();
        List<PricingService.ConfigResult> results =
            PricingService.evaluateConfiguration(device.Id, 'NOCOMMIT');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Requires_Commitment_Device', results[0].developerName);
        System.assertEquals('Requires Commitment', results[0].ruleKind);
        System.assertEquals('Block', results[0].severity);
        System.assert(results[0].blocking);
        System.assert(
            results[0].message.contains('requires a 12 or 24 month commitment'),
            'The advisor-facing message should come from Config_Rule__mdt.'
        );
    }

    @IsTest
    static void evaluatesConfigurationsInBulk() {
        Product2 device = getProduct('TEST_DEVICE');
        Product2 mobile = getProduct('TEST_MOBILE');

        Test.startTest();
        Map<Id, List<PricingService.ConfigResult>> results =
            PricingService.evaluateConfigurations(
                new List<Product2>{ device, mobile },
                'NOCOMMIT'
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(1, results.get(device.Id).size());
        System.assert(
            results.get(device.Id)[0].blocking,
            'The NOCOMMIT device rule must block the device.'
        );
        System.assertEquals(0, results.get(mobile.Id).size());
    }

    @IsTest
    static void evaluatesNoConfigurationRulesForCommittedDevice() {
        Product2 device = getProduct('TEST_DEVICE');

        Test.startTest();
        List<PricingService.ConfigResult> results =
            PricingService.evaluateConfiguration(device.Id, 'COMMIT12');
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @IsTest
    static void priceAddsBlockingReasonForNoCommitDevice() {
        Product2 device = getProduct('TEST_DEVICE');

        Test.startTest();
        PricingService.PriceBreakdown result = PricingService.price(
            device.Id,
            'NOCOMMIT',
            'Consumer',
            PRICING_DATE,
            new Set<String>{ 'TELCO_MOBILE' }
        );
        Test.stopTest();

        System.assertEquals(700.00, result.finalPrice);
        System.assertEquals(1, result.blockingReasons.size());
        System.assertEquals(0, result.warningReasons.size());
    }

    @IsTest
    static void priceBulkPreservesOrderAndCarriesConfiguration() {
        Product2 device = getProduct('TEST_DEVICE');
        Product2 mobile = getProduct('TEST_MOBILE');

        List<PricingService.PriceRequest> requests = new List<PricingService.PriceRequest>{
            new PricingService.PriceRequest(
                device.Id, 'COMMIT12', 'Consumer', PRICING_DATE,
                new Set<String>{ 'TELCO_MOBILE' }
            ),
            new PricingService.PriceRequest(
                device.Id, 'NOCOMMIT', 'Consumer', PRICING_DATE,
                new Set<String>{ 'TELCO_MOBILE' }
            ),
            new PricingService.PriceRequest(
                mobile.Id, 'COMMIT12', 'Consumer', PRICING_DATE
            ),
            new PricingService.PriceRequest(
                mobile.Id, 'NOCOMMIT', 'Consumer', PRICING_DATE
            )
        };

        Test.startTest();
        List<PricingService.PriceBreakdown> results = PricingService.priceBulk(requests);
        Test.stopTest();

        System.assertEquals(4, results.size());
        System.assertEquals(700.00, results[0].finalPrice);
        System.assertEquals(0, results[0].blockingReasons.size());
        System.assertEquals(700.00, results[1].finalPrice);
        System.assertEquals(1, results[1].blockingReasons.size());
        System.assertEquals(90.00, results[2].finalPrice);
        System.assertEquals(0, results[2].blockingReasons.size());
        System.assertEquals(100.00, results[3].finalPrice);
        System.assertEquals(0, results[3].blockingReasons.size());
    }

    @IsTest
    static void priceBulkHandlesTwoHundredMixedRequests() {
        Product2 device = getProduct('TEST_DEVICE');
        Product2 mobile = getProduct('TEST_MOBILE');
        List<PricingService.PriceRequest> requests = new List<PricingService.PriceRequest>();

        for (Integer i = 0; i < 200; i++) {
            if (Math.mod(i, 2) == 0) {
                requests.add(new PricingService.PriceRequest(
                    device.Id, 'COMMIT12', 'Consumer', PRICING_DATE,
                    new Set<String>{ 'TELCO_MOBILE' }
                ));
            } else {
                requests.add(new PricingService.PriceRequest(
                    mobile.Id, 'COMMIT12', 'Consumer', PRICING_DATE
                ));
            }
        }

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        List<PricingService.PriceBreakdown> results = PricingService.priceBulk(requests);
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(200, results.size());
        System.assertEquals(700.00, results[0].finalPrice);
        System.assertEquals(90.00, results[1].finalPrice);
        System.assertEquals(700.00, results[198].finalPrice);
        System.assertEquals(90.00, results[199].finalPrice);
        System.assert(
            Limits.getQueries() <= 4,
            'Bulk pricing must use at most one query per object type, not per request.'
        );
        System.assertEquals(
            dmlBefore,
            dmlAfter,
            'Pricing must not perform DML.'
        );
    }

    @IsTest
    static void priceBulkRejectsMoreThanTwoHundredRequests() {
        List<PricingService.PriceRequest> requests =
            new List<PricingService.PriceRequest>();
        for (Integer i = 0; i <= PricingService.MAX_BATCH_SIZE; i++) {
            requests.add(new PricingService.PriceRequest());
        }

        Boolean threw = false;

        Test.startTest();
        try {
            PricingService.priceBulk(requests);
        } catch (PricingService.PricingException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('at most'),
                'Exception should explain the supported batch size.'
            );
        }
        Test.stopTest();

        System.assert(threw, 'Bulk pricing should reject more than 200 requests.');
    }

    @IsTest
    static void priceBulkReturnsEmptyForEmptyInput() {
        Test.startTest();
        List<PricingService.PriceBreakdown> results =
            PricingService.priceBulk(new List<PricingService.PriceRequest>());
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @IsTest
    static void priceBulkThrowsForNullInput() {
        Boolean threw = false;

        Test.startTest();
        try {
            PricingService.priceBulk(null);
        } catch (PricingService.PricingException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Bulk pricing should fail when the request list is null.');
    }
}
