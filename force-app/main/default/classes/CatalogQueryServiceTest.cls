@IsTest
private class CatalogQueryServiceTest {
    private static final Date PRICING_DATE = Date.newInstance(2026, 11, 7);
    private static final String POSTAL_FULL = 'TST75001';
    private static final String POSTAL_CAPPED = 'TST69001';
    private static final String POSTAL_NO_FIBER = 'TST59000';
    private static final String POSTAL_FUTURE = 'TST13001';
    private static final String POSTAL_UNKNOWN = 'TST00000';

    @TestSetup
    static void createTestData() {
        Pricebook2 pricebook = new Pricebook2(
            Name = 'ATS Catalog Test Pricebook',
            IsActive = true
        );
        insert pricebook;

        List<Product2> products = new List<Product2>{
            new Product2(
                Name = 'Catalog Mobile 20',
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 20,
                Unlimited_Calls__c = true,
                Unlimited_SMS__c = true,
                Recurring__c = true,
                Requires_Commitment__c = false,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_MOBILE_20',
                Specs__c = 'Test mobile specs'
            ),
            new Product2(
                Name = 'Catalog Fiber 20',
                Family = 'TELCO_FIBER',
                Plan_Type__c = 'Fiber',
                Speed_Mbps__c = 20,
                Recurring__c = true,
                Requires_Commitment__c = false,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_FIBER_20'
            ),
            new Product2(
                Name = 'Catalog Fiber 100',
                Family = 'TELCO_FIBER',
                Plan_Type__c = 'Fiber',
                Speed_Mbps__c = 100,
                Recurring__c = true,
                Requires_Commitment__c = false,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_FIBER_100'
            ),
            new Product2(
                Name = 'Catalog Device',
                Family = 'TELCO_DEVICE',
                Recurring__c = false,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_DEVICE',
                Device_Image_URL__c = 'https://example.com/catalog-device.png',
                Specs__c = 'Test device specs'
            ),
            new Product2(
                Name = 'Catalog Commitment Mobile',
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 1,
                Recurring__c = true,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_COMMIT_MOBILE'
            ),
            new Product2(
                Name = 'Catalog Inactive Mobile',
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 2,
                IsActive = false,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_INACTIVE_MOBILE'
            ),
            new Product2(
                Name = 'Catalog Retired Mobile',
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 3,
                IsActive = true,
                Is_Active__c = false,
                ATS_Product_Code__c = 'CAT_RETIRED_MOBILE'
            ),
            new Product2(
                Name = 'Catalog Inactive Device',
                Family = 'TELCO_DEVICE',
                IsActive = false,
                Is_Active__c = true,
                ATS_Product_Code__c = 'CAT_INACTIVE_DEVICE'
            )
        };
        insert products;

        Map<String, Product2> byCode = new Map<String, Product2>();
        for (Product2 product : products) {
            byCode.put(product.ATS_Product_Code__c, product);
        }

        Id standardPricebookId = Test.getStandardPricebookId();
        insert new List<PricebookEntry>{
            standardEntry(standardPricebookId, byCode.get('CAT_MOBILE_20').Id, 100),
            standardEntry(standardPricebookId, byCode.get('CAT_DEVICE').Id, 1000)
        };
        insert new List<PricebookEntry>{
            customEntry(pricebook.Id, byCode.get('CAT_MOBILE_20').Id, 100),
            customEntry(pricebook.Id, byCode.get('CAT_DEVICE').Id, 1000)
        };

        insert new List<Eligibility__c>{
            new Eligibility__c(
                Name = 'TST75001 - Full fibre',
                Postal_Code__c = POSTAL_FULL,
                Country__c = 'FR',
                Fiber_Available__c = true,
                Max_Downstream_Mbps__c = 500,
                Earliest_Activation_Date__c = Date.today().addDays(-1),
                Is_Active__c = true
            ),
            new Eligibility__c(
                Name = 'TST69001 - Capped fibre',
                Postal_Code__c = POSTAL_CAPPED,
                Country__c = 'FR',
                Fiber_Available__c = true,
                Max_Downstream_Mbps__c = 50,
                Earliest_Activation_Date__c = Date.today().addDays(-1),
                Is_Active__c = true
            ),
            new Eligibility__c(
                Name = 'TST59000 - No fibre',
                Postal_Code__c = POSTAL_NO_FIBER,
                Country__c = 'FR',
                Fiber_Available__c = false,
                Is_Active__c = true
            ),
            new Eligibility__c(
                Name = 'TST13001 - Future activation',
                Postal_Code__c = POSTAL_FUTURE,
                Country__c = 'FR',
                Fiber_Available__c = true,
                Max_Downstream_Mbps__c = 500,
                Earliest_Activation_Date__c = Date.today().addDays(30),
                Is_Active__c = true
            )
        };
    }

    private static PricebookEntry standardEntry(
        Id pricebookId,
        Id productId,
        Decimal unitPrice
    ) {
        return new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true,
            UseStandardPrice = false
        );
    }

    private static PricebookEntry customEntry(
        Id pricebookId,
        Id productId,
        Decimal unitPrice
    ) {
        return standardEntry(pricebookId, productId, unitPrice);
    }

    private static Product2 productByCode(String productCode) {
        return [
            SELECT Id, Name, Family, ATS_Product_Code__c
            FROM Product2
            WHERE ATS_Product_Code__c = :productCode
            LIMIT 1
        ];
    }

    private static CatalogQueryService.ProductView findView(
        List<CatalogQueryService.ProductView> views,
        String productCode
    ) {
        for (CatalogQueryService.ProductView view : views) {
            if (view != null && productCode.equals(view.productCode)) {
                return view;
            }
        }
        return null;
    }

    @IsTest
    static void getPlansFiltersByTypeActivityAndCommitment() {
        Test.startTest();
        List<CatalogQueryService.ProductView> noCommit =
            CatalogQueryService.getPlans('mobile', null);
        List<CatalogQueryService.ProductView> committed =
            CatalogQueryService.getPlans('MOBILE', 'COMMIT12');
        List<CatalogQueryService.ProductView> fiber =
            CatalogQueryService.getPlans('Fiber', 'NOCOMMIT');
        Test.stopTest();

        CatalogQueryService.ProductView mobile =
            findView(noCommit, 'CAT_MOBILE_20');
        System.assertNotEquals(null, mobile, 'The active mobile plan should be returned.');
        System.assertNotEquals(
            null,
            findView(committed, 'CAT_COMMIT_MOBILE'),
            'A committed request should include commitment-only plans.'
        );
        System.assertEquals(
            null,
            findView(noCommit, 'CAT_COMMIT_MOBILE'),
            'NOCOMMIT should exclude plans that require a commitment.'
        );
        System.assertEquals(
            null,
            findView(noCommit, 'CAT_INACTIVE_MOBILE'),
            'Inactive products must not appear in the catalogue.'
        );
        System.assertEquals(
            null,
            findView(noCommit, 'CAT_RETIRED_MOBILE'),
            'Retired products must not appear in the catalogue.'
        );
        System.assertEquals(
            null,
            findView(noCommit, 'CAT_DEVICE'),
            'Devices belong to getDevices(), not getPlans().'
        );
        System.assertNotEquals(
            null,
            findView(fiber, 'CAT_FIBER_20'),
            'Fibre plans should be returned for the Fiber offer type.'
        );
        System.assertNotEquals(null, findView(fiber, 'CAT_FIBER_100'));

        System.assertEquals('CAT_MOBILE_20', mobile.productCode);
        System.assertEquals('TELCO_MOBILE', mobile.family);
        System.assertEquals('Mobile', mobile.planType);
        System.assertEquals(20.0, mobile.dataGb);
        System.assert(mobile.unlimitedCalls);
        System.assert(mobile.unlimitedSms);
        System.assert(mobile.recurring);
        System.assert(!mobile.requiresCommitment);
        System.assertEquals('Test mobile specs', mobile.specs);
    }

    @IsTest
    static void getPlansRejectsMissingAndUnknownOfferTypes() {
        Boolean blankThrew = false;
        Boolean unknownThrew = false;

        Test.startTest();
        try {
            CatalogQueryService.getPlans('  ', 'COMMIT12');
        } catch (CatalogQueryService.CatalogException e) {
            blankThrew = true;
        }
        try {
            CatalogQueryService.getPlans('Television', 'COMMIT12');
        } catch (CatalogQueryService.CatalogException e) {
            unknownThrew = true;
        }
        Test.stopTest();

        System.assert(blankThrew, 'A blank offer type must be rejected.');
        System.assert(unknownThrew, 'An unsupported offer type must be rejected.');
    }

    @IsTest
    static void getDevicesReturnsOnlyActiveDevices() {
        Test.startTest();
        List<CatalogQueryService.ProductView> devices =
            CatalogQueryService.getDevices();
        Test.stopTest();

        CatalogQueryService.ProductView device = findView(devices, 'CAT_DEVICE');
        System.assertNotEquals(null, device, 'The active device should be returned.');
        System.assertEquals('TELCO_DEVICE', device.family);
        System.assert(device.requiresCommitment);
        System.assertEquals(
            'https://example.com/catalog-device.png',
            device.deviceImageUrl
        );
        System.assertEquals('Test device specs', device.specs);
        System.assert(!device.recurring);
        System.assertEquals(
            null,
            findView(devices, 'CAT_INACTIVE_DEVICE'),
            'Inactive devices must not appear in the catalogue.'
        );
    }

    @IsTest
    static void filterByEligibilityAppliesSpeedAndServiceability() {
        List<CatalogQueryService.ProductView> fiber =
            CatalogQueryService.getPlans('Fiber', 'NOCOMMIT');

        Test.startTest();
        List<CatalogQueryService.ProductView> full =
            CatalogQueryService.filterByEligibility(fiber, POSTAL_FULL);
        List<CatalogQueryService.ProductView> capped =
            CatalogQueryService.filterByEligibility(fiber, POSTAL_CAPPED);
        List<CatalogQueryService.ProductView> noFiber =
            CatalogQueryService.filterByEligibility(fiber, POSTAL_NO_FIBER);
        List<CatalogQueryService.ProductView> unknown =
            CatalogQueryService.filterByEligibility(fiber, POSTAL_UNKNOWN);
        List<CatalogQueryService.ProductView> future =
            CatalogQueryService.filterByEligibility(fiber, POSTAL_FUTURE);
        Test.stopTest();

        System.assertNotEquals(null, findView(full, 'CAT_FIBER_20'));
        System.assertNotEquals(null, findView(full, 'CAT_FIBER_100'));
        System.assertNotEquals(null, findView(capped, 'CAT_FIBER_20'));
        System.assertEquals(
            null,
            findView(capped, 'CAT_FIBER_100'),
            'A 50 Mbps postcode must exclude the 100 Mbps plan.'
        );
        System.assertEquals(
            null,
            findView(noFiber, 'CAT_FIBER_20'),
            'A non-fibre postcode must exclude all fibre plans.'
        );
        System.assertEquals(
            null,
            findView(unknown, 'CAT_FIBER_20'),
            'An unknown postcode must not expose fibre plans.'
        );

        CatalogQueryService.ProductView futurePlan =
            findView(future, 'CAT_FIBER_100');
        System.assertNotEquals(null, futurePlan);
        System.assert(futurePlan.activationBlocked);
        System.assertEquals(
            Date.today().addDays(30),
            futurePlan.earliestActivationDate
        );
    }

    @IsTest
    static void filterByEligibilityLeavesNonFibrePlansUntouched() {
        List<CatalogQueryService.ProductView> mobile =
            CatalogQueryService.getPlans('Mobile', 'NOCOMMIT');

        Test.startTest();
        List<CatalogQueryService.ProductView> filtered =
            CatalogQueryService.filterByEligibility(mobile, POSTAL_NO_FIBER);
        Test.stopTest();

        System.assertEquals(
            mobile.size(),
            filtered.size(),
            'Mobile plans must not be removed by a fibre eligibility check.'
        );
        System.assertNotEquals(null, findView(filtered, 'CAT_MOBILE_20'));
    }

    @IsTest
    static void filterByEligibilityKeepsMixedNonFibrePlans() {
        CatalogQueryService.ProductView mobile = findView(
            CatalogQueryService.getPlans('Mobile', 'NOCOMMIT'),
            'CAT_MOBILE_20'
        );
        CatalogQueryService.ProductView fiber = findView(
            CatalogQueryService.getPlans('Fiber', 'NOCOMMIT'),
            'CAT_FIBER_20'
        );

        System.assertEquals(
            false,
            CatalogEligibilityFilter.requiresFiltering(null),
            'A null plan list needs no eligibility query.'
        );

        Test.startTest();
        List<CatalogQueryService.ProductView> filtered =
            CatalogQueryService.filterByEligibility(
                new List<CatalogQueryService.ProductView>{ mobile, fiber },
                POSTAL_FULL
            );
        Test.stopTest();

        System.assertEquals(2, filtered.size());
        System.assertNotEquals(null, findView(filtered, 'CAT_MOBILE_20'));
        System.assertNotEquals(null, findView(filtered, 'CAT_FIBER_20'));
    }

    @IsTest
    static void filterByEligibilityHandlesNullAndEmptyInputs() {
        List<CatalogQueryService.ProductView> fiber =
            CatalogQueryService.getPlans('Fiber', 'NOCOMMIT');

        Test.startTest();
        List<CatalogQueryService.ProductView> nullInput =
            CatalogQueryService.filterByEligibility(null, POSTAL_FULL);
        List<CatalogQueryService.ProductView> emptyInput =
            CatalogQueryService.filterByEligibility(
                new List<CatalogQueryService.ProductView>(),
                POSTAL_FULL
            );
        List<CatalogQueryService.ProductView> blankPostal =
            CatalogQueryService.filterByEligibility(fiber, '  ');
        List<CatalogQueryService.ProductView> nullElement =
            CatalogQueryService.filterByEligibility(
                new List<CatalogQueryService.ProductView>{
                    null,
                    findView(fiber, 'CAT_FIBER_20')
                },
                POSTAL_FULL
            );
        Test.stopTest();

        System.assertEquals(null, nullInput);
        System.assertEquals(0, emptyInput.size());
        System.assertEquals(fiber.size(), blankPostal.size());
        System.assertEquals(1, nullElement.size());
    }

    @IsTest
    static void getOptionsDelegatesConfigurationRules() {
        Product2 device = productByCode('CAT_DEVICE');

        Test.startTest();
        List<PricingService.ConfigResult> noCommit =
            CatalogQueryService.getOptions(device.Id, null);
        List<PricingService.ConfigResult> committed =
            CatalogQueryService.getOptions(device.Id, 'COMMIT12');
        Test.stopTest();

        System.assertEquals(1, noCommit.size());
        System.assertEquals('Requires_Commitment_Device', noCommit[0].developerName);
        System.assert(noCommit[0].blocking);
        System.assertEquals(0, committed.size());
    }

    @IsTest
    static void getOptionsRejectsMissingProduct() {
        Boolean threw = false;

        Test.startTest();
        try {
            CatalogQueryService.getOptions(null, 'COMMIT12');
        } catch (CatalogQueryService.CatalogException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Configuration evaluation requires a product id.');
    }

    @IsTest
    static void getPriceBreakdownDelegatesToPricingService() {
        Product2 mobile = productByCode('CAT_MOBILE_20');
        Product2 device = productByCode('CAT_DEVICE');

        Test.startTest();
        PricingService.PriceBreakdown mobileBreakdown =
            CatalogQueryService.getPriceBreakdown(
                mobile.Id,
                'COMMIT12',
                'Consumer',
                PRICING_DATE,
                null
            );
        PricingService.PriceBreakdown bundledDevice =
            CatalogQueryService.getPriceBreakdown(
                device.Id,
                'COMMIT12',
                'Consumer',
                PRICING_DATE,
                new List<String>{ 'TELCO_MOBILE' }
            );
        PricingService.PriceBreakdown unbundledDevice =
            CatalogQueryService.getPriceBreakdown(
                device.Id,
                'COMMIT12',
                'Consumer',
                PRICING_DATE,
                null
            );
        Test.stopTest();

        System.assertEquals(100.00, mobileBreakdown.listPrice);
        System.assertEquals(10.00, mobileBreakdown.adjustmentTotal);
        System.assertEquals(90.00, mobileBreakdown.finalPrice);
        System.assertEquals(1, mobileBreakdown.appliedRules.size());
        System.assertEquals(
            'Commitment_Variant_12M',
            mobileBreakdown.appliedRules[0].developerName
        );
        System.assertEquals('CONSUMER', mobileBreakdown.segment);
        System.assertEquals(PRICING_DATE, mobileBreakdown.effectiveDate);
        System.assertNotEquals(null, mobileBreakdown.pricebookId);
        System.assertNotEquals(null, mobileBreakdown.pricebookEntryId);

        System.assertEquals(700.00, bundledDevice.finalPrice);
        System.assertEquals(1000.00, unbundledDevice.finalPrice);
        System.assertEquals(0, unbundledDevice.appliedRules.size());
    }

    @IsTest
    static void getPriceBreakdownRejectsMissingProduct() {
        Boolean threw = false;

        Test.startTest();
        try {
            CatalogQueryService.getPriceBreakdown(
                null,
                'COMMIT12',
                'Consumer',
                PRICING_DATE,
                null
            );
        } catch (CatalogQueryService.CatalogException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Pricing requires a product id.');
    }

    @IsTest
    static void catalogueQueriesStayBounded() {
        Test.startTest();
        CatalogQueryService.getPlans('Mobile', 'NOCOMMIT');
        Integer afterPlans = Limits.getQueries();
        CatalogQueryService.getDevices();
        Integer afterDevices = Limits.getQueries();
        CatalogQueryService.filterByEligibility(
            CatalogQueryService.getPlans('Fiber', 'NOCOMMIT'),
            POSTAL_FULL
        );
        Integer afterEligibility = Limits.getQueries();
        Test.stopTest();

        System.assertEquals(
            1,
            afterPlans,
            'getPlans must issue one product query, not one per product.'
        );
        System.assertEquals(
            2,
            afterDevices,
            'getDevices must issue one additional product query.'
        );
        System.assertEquals(
            4,
            afterEligibility,
            'A fibre filter must add one plan query and one eligibility query.'
        );
    }

    @IsTest
    static void filterByEligibilitySkipsQueryForNonFibrePlans() {
        List<CatalogQueryService.ProductView> mobile =
            CatalogQueryService.getPlans('Mobile', 'NOCOMMIT');

        Test.startTest();
        Integer before = Limits.getQueries();
        CatalogQueryService.filterByEligibility(mobile, POSTAL_FULL);
        Integer after = Limits.getQueries();
        Test.stopTest();

        System.assertEquals(
            before,
            after,
            'A non-fibre list must not pay for an eligibility lookup.'
        );
    }

    @IsTest
    static void filterByEligibilityDoesNotMutateInputViews() {
        List<CatalogQueryService.ProductView> fiber =
            CatalogQueryService.getPlans('Fiber', 'NOCOMMIT');
        CatalogQueryService.ProductView original =
            findView(fiber, 'CAT_FIBER_100');

        Test.startTest();
        List<CatalogQueryService.ProductView> filtered =
            CatalogQueryService.filterByEligibility(fiber, POSTAL_FUTURE);
        Test.stopTest();

        System.assertNotEquals(null, original);
        System.assert(
            !original.activationBlocked,
            'The eligibility filter must not modify the caller list.'
        );
        System.assert(findView(filtered, 'CAT_FIBER_100').activationBlocked);
    }

    @IsTest
    static void pricingQueriesStayBounded() {
        Product2 device = productByCode('CAT_DEVICE');
        Product2 mobile = productByCode('CAT_MOBILE_20');

        Test.startTest();
        Integer beforeOptions = Limits.getQueries();
        CatalogQueryService.getOptions(device.Id, 'COMMIT12');
        Integer afterOptions = Limits.getQueries();
        CatalogQueryService.getPriceBreakdown(
            mobile.Id,
            'COMMIT12',
            'Consumer',
            PRICING_DATE,
            null
        );
        Integer afterPrice = Limits.getQueries();
        Test.stopTest();

        System.assert(
            afterOptions - beforeOptions <= 2,
            'getOptions must load the product and configuration rules once.'
        );
        System.assert(
            afterPrice - afterOptions <= 4,
            'A single price breakdown must stay within the batch pricing budget.'
        );
    }
}
